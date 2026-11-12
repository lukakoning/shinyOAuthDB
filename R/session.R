#' Connect another database package to a user's sign-in
#'
#' Use a database package that accepts access tokens with a visitor's Shiny
#' sign-in. This is the general helper for drivers without a dedicated
#' shinyOAuthDB function. It supplies the user's token when opening the
#' connection and keeps that connection in their Shiny session.
#'
#' @param authorization Function providing the visitor's current sign-in
#'   authorization. Pass `auth$connection` from shinyOAuth without parentheses.
#'   To select a saved account, use a function calling `auth$connection(id)`.
#' @param connect Function that opens the connection, such as `DBI::dbConnect`.
#' @param ... Named arguments for `connect`, excluding the token argument.
#' @param token_arg Name of the argument that receives the user's access token.
#' @param target Name of the service token to use in your shinyOAuth client.
#'   Named targets let one sign-in obtain tokens for different services.
#'   `NULL` uses the client's default token.
#' @param required_scopes Additional OAuth permissions to check before use.
#'   Request them on the shinyOAuth client first; this check doesn't request
#'   consent or grant database privileges.
#' @param disconnect Function to close the connection. By default, DBI
#'   connections use `DBI::dbDisconnect()`; other objects have no cleanup.
#' @param min_valid_for Minimum remaining token lifetime, in seconds, when
#'   obtaining a token. Use `0` to accept any unexpired token.
#' @param session The visitor's Shiny session. Usually inferred when you
#'   create the helper inside `server()`.
#' @return A reactive function, usually named `con`. Call
#'   `connection <- con()` inside a render or reactive expression to get the
#'   database connection. Before sign-in, it waits quietly like `shiny::req()`.
#' @details
#' Create the helper inside `server()` so each visitor has their own
#' connection. Call `con()` before each operation; it checks the current
#' authorization and reuses a valid connection. Sign-out, account changes,
#' loss of required permissions and session end trigger cleanup.
#'
#' A connection you save separately may keep copied credentials, depending
#' on the driver. Obtain it through `con()` each time. A valid DBI connection
#' can stay open through token renewal; a broken one reopens on the next call.
#'
#' If token refresh is running, reactive outputs wait until it finishes.
#' A button-triggered query may need another click. `min_valid_for` checks
#' the token's remaining lifetime at the start; it doesn't guarantee validity
#' throughout a long query.
#'
#' For functions that accept a token on every request, use [oauth_db_token()]
#' or the source's API client.
#' @examples
#' \dontrun{
#' # Inside server(); client configured for Azure PostgreSQL:
#' con <- oauth_db_connect(
#'   auth$connection,
#'   connect = DBI::dbConnect,
#'   drv = RPostgres::Postgres(),
#'   token_arg = "password",
#'   target = "postgres",
#'   host = "example.postgres.database.azure.com",
#'   dbname = "reporting",
#'   user = "reporting-readers",
#'   sslmode = "verify-full"
#' )
#' }
#' @seealso [oauth_db_token()]. For saved results and connection lifetime, see
#'   `vignette("getting-started", package = "shinyOAuthDB")`.
#' @export
oauth_db_connect <- function(
  authorization,
  connect = DBI::dbConnect,
  ...,
  token_arg = "token",
  target = NULL,
  required_scopes = character(),
  disconnect = NULL,
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  if (!is.function(connect)) {
    .odb_abort("connect must be a native connection function.")
  }
  .odb_string(token_arg, "token_arg")
  args <- list(...)
  .odb_named_args(args)
  if (token_arg %in% names(args)) {
    .odb_abort("The bridge supplies the token argument; omit it from ... .")
  }
  .odb_bind(
    authorization,
    .odb_backend_generic,
    native_connect = connect,
    native_args = args,
    token_arg = token_arg,
    target = target,
    required_scopes = required_scopes,
    disconnect = disconnect,
    min_valid_for = min_valid_for,
    session = session
  )
}

.odb_backend_generic <- function(
  token,
  native_connect,
  native_args,
  token_arg
) {
  native_args[[token_arg]] <- token()
  do.call(native_connect, native_args)
}

#' Get a user's access token for another R package
#'
#' Get the visitor's current access token for an R function that accepts one
#' directly. An access token is a temporary credential for making requests
#' on the user's behalf. The returned function gets a current token each
#' time you call it.
#'
#' @inheritParams oauth_db_connect
#' @return A reactive function, such as `bearer`. Call `bearer()` inside
#'   a render or reactive expression to get the current token string.
#' @details
#' Create the helper inside `server()`. shinyOAuth obtains or renews the
#' token when needed. Call `bearer()` for each request; a token string saved
#' earlier still has its original expiry time.
#'
#' For Fabric and Databricks, [oauth_db_fabric_api()] and
#' [oauth_db_databricks_api()] can supply credentials to their supporting
#' packages for you.
#' @examples
#' \dontrun{
#' bearer <- oauth_db_token(auth$connection, required_scopes = "all-apis")
#' output$rows <- shiny::renderPrint({
#'   brickster::db_sql_warehouse_list(
#'     host = "example.cloud.databricks.com",
#'     token = bearer()
#'   )
#' })
#' }
#' @seealso [oauth_db_fabric_api()], [oauth_db_databricks_api()].
#'   See `vignette("getting-started", package = "shinyOAuthDB")` for token lifetime.
#' @export
oauth_db_token <- function(
  authorization,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_bind(
    authorization,
    .odb_backend_token,
    target = target,
    required_scopes = required_scopes,
    cache_key = function(token) token(),
    min_valid_for = min_valid_for,
    session = session
  )
}

.odb_backend_token <- function(token) token()

# The token callback can use only the authorization that created it.
# Cache connections and providers; the caller runs queries.
.odb_bind <- function(
  authorization,
  connect,
  ...,
  target = NULL,
  required_scopes = character(),
  disconnect = NULL,
  cache_key = NULL,
  identity_key = NULL,
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain(),
  is_valid = NULL
) {
  if (
    !is.function(connect) ||
      (!is.null(disconnect) && !is.function(disconnect)) ||
      (!is.null(is_valid) && !is.function(is_valid))
  ) {
    .odb_abort(
      "connect, disconnect and is_valid must be functions (the last two may be NULL)."
    )
  }
  .odb_string(target, "target", optional = TRUE)
  required_scopes <- .odb_scopes(required_scopes)
  .odb_seconds(min_valid_for, "min_valid_for")
  args <- list(...)
  .odb_named_args(args)
  owner <- .odb_root_session(session)
  if (
    is.null(owner) ||
      isTRUE(owner$isClosed()) ||
      !identical(owner, .odb_root_session(shiny::getDefaultReactiveDomain()))
  ) {
    .odb_abort(
      "Create the database helper inside server(), in its owning Shiny session.",
      "authorization_unavailable"
    )
  }
  reader <- .odb_authorization_reader(authorization)
  grant <- native <- native_key <- identity <- failure <- failure_key <- NULL
  available <- closed <- denied <- FALSE
  epoch <- 0L
  changed <- shiny::reactiveVal(0L)
  scope_checks <- list()
  checks_changed <- shiny::reactiveVal(0L)
  background <- FALSE
  permission_validation <- NULL
  identity_pending <- shiny::reactiveVal(FALSE)
  task_changed <- shiny::reactiveVal(0L)

  assert_owner <- function() {
    if (
      closed ||
        isTRUE(owner$isClosed()) ||
        !identical(owner, .odb_root_session(shiny::getDefaultReactiveDomain()))
    ) {
      .odb_abort(
        "Use the connection in its owning, open Shiny session.",
        "authorization_unavailable"
      )
    }
  }
  close_native <- function() {
    value <- native
    native <<- NULL
    native_key <<- NULL
    if (!is.null(value)) {
      tryCatch(.odb_disconnect(value, disconnect), error = function(e) {
        .odb_cleanup_failure()
      })
    }
  }
  scope_coverage <- function(scopes) {
    if (!available) {
      return(FALSE)
    }
    tryCatch(
      .odb_authorization_has_scopes(grant, scopes, target),
      error = .odb_failure_key
    )
  }
  watch_scopes <- function(scopes) {
    key <- paste(sort(scopes), collapse = "\r")
    check <- scope_checks[[key]]
    if (is.null(check)) {
      check <- list(
        scopes = scopes,
        changed = shiny::reactiveVal(shiny::isolate(scope_coverage(scopes)))
      )
      scope_checks[[key]] <<- check
      checks_changed(shiny::isolate(checks_changed()) + 1L)
    }
    check$changed()
    invisible(NULL)
  }
  validate_async <- function(next_grant, status) {
    if (
      is.null(permission_validation) ||
        !identical(permission_validation$grant, next_grant)
    ) {
      state <- new.env(parent = emptyenv())
      state$grant <- next_grant
      state$pending <- TRUE
      state$denied <- FALSE
      state$error <- NULL
      permission_validation <<- state
      finish <- function(denied = FALSE, error = NULL) {
        if (!closed && identical(permission_validation, state)) {
          shiny::withReactiveDomain(
            owner,
            shiny::isolate({
              state$pending <- FALSE
              state$denied <- denied
              state$error <- error
              task_changed(task_changed() + 1L)
              sync()
            })
          )
        }
        invisible(NULL)
      }
      state$promise <- promises::then(
        .odb_authorization_denied(
          next_grant,
          required_scopes,
          target,
          status,
          async = TRUE
        ),
        function(denied) finish(denied = denied),
        function(error) finish(error = error)
      )
    }
    if (!is.null(permission_validation$error)) {
      stop(permission_validation$error)
    }
    permission_validation$denied
  }
  sync <- function(async = background) {
    assert_owner()
    next_grant <- next_identity <- next_failure <- NULL
    next_available <- next_denied <- next_identity_pending <- FALSE
    tryCatch(
      {
        next_grant <- reader()
        if (
          !is.null(permission_validation) &&
            !identical(permission_validation$grant, next_grant)
        ) {
          permission_validation <<- NULL
        }
        if (!is.null(next_grant)) {
          .odb_authorization_validate(next_grant)
          next_available <- .odb_authorization_has_scopes(
            next_grant,
            required_scopes,
            target
          )
          # Identity callbacks can wait on refresh status. Other sources watch
          # permission evidence alone so unknown expiry cannot loop renewal.
          read_status <- function() {
            .odb_authorization_status(next_grant, target)
          }
          status <- if (is.function(identity_key)) {
            read_status()
          } else {
            shiny::isolate(read_status())
          }
          # has_scopes() checks operation scopes, not the client's requirements.
          # Validate those separately when expiry masks the permission status;
          # preserve a previous denial while a refresh hides its evidence.
          next_denied <- if (
            async && isTRUE(status %in% c("expired", "expiry_unknown"))
          ) {
            validate_async(next_grant, status)
          } else {
            .odb_authorization_denied(
              next_grant,
              required_scopes,
              target,
              status
            )
          }
          if (isTRUE(status %in% c("expired", "expiry_unknown"))) {
            # Validation can renew credentials or end local access on failure.
            next_available <- .odb_authorization_has_scopes(
              next_grant,
              required_scopes,
              target
            )
            status <- shiny::isolate(.odb_authorization_status(
              next_grant,
              target
            ))
          }
          next_denied <- next_denied ||
            identical(status, "insufficient_scope") ||
            (identical(next_grant, grant) &&
              denied &&
              !status %in% c("active", "limited", "expired", "expiry_unknown"))
          next_available <- next_available && !next_denied
          if (!next_available) {
            if (identical(status, "refreshing") && !next_denied) {
              shiny::req(FALSE)
            }
            next_available <- !next_denied && identical(status, "not_acquired")
            shiny::validate(shiny::need(
              next_available,
              "The selected authorization lacks the required permissions. Check the client's requested and required scopes, and this helper's target and required_scopes. The helper does not request consent."
            ))
          }
          if (next_available && is.function(identity_key)) {
            next_identity <- tryCatch(identity_key(), error = function(error) {
              pending <- identical(status, "refreshing") ||
                (async &&
                  !is.null(permission_validation) &&
                  permission_validation$pending)
              if (!pending) {
                stop(error)
              }
              next_identity_pending <<- TRUE
              if (identical(next_grant, grant)) identity else NULL
            })
          }
        }
      },
      error = function(e) {
        ended <- inherits(e, "shinyOAuth_access_error") &&
          identical(e$context$reason, "authorization_unavailable")
        if (ended) {
          next_available <<- FALSE
        }
        waiting <- inherits(e, "shiny.silent.error") &&
          !nzchar(conditionMessage(e))
        if (!ended && !waiting) next_failure <<- e
      }
    )
    next_failure_key <- .odb_failure_key(next_failure)
    if (
      !identical(next_grant, grant) ||
        !identical(next_identity, identity) ||
        !identical(next_available, available) ||
        !identical(next_failure_key, failure_key)
    ) {
      close_native()
      epoch <<- epoch + 1L
      changed(epoch)
    }
    grant <<- next_grant
    identity <<- next_identity
    available <<- next_available
    denied <<- next_denied
    failure <<- next_failure
    failure_key <<- next_failure_key
    identity_pending(next_identity_pending)
    checks_changed()
    for (check in scope_checks) {
      check$changed(scope_coverage(check$scopes))
    }
    invisible(NULL)
  }
  current <- function(captured, async = FALSE, allow_pending = FALSE) {
    assert_owner()
    shiny::isolate(sync(async = async))
    if (!available || !identical(epoch, captured)) {
      .odb_abort(
        "This provider's authorization is no longer current.",
        "authorization_unavailable"
      )
    }
    if (shiny::isolate(identity_pending())) {
      .odb_abort(
        "The account identity is unavailable while credentials renew.",
        "authorization_pending"
      )
    }
    if (
      async &&
        !allow_pending &&
        !is.null(permission_validation) &&
        permission_validation$pending
    ) {
      .odb_abort(
        "Authorization validation is still running.",
        "authorization_pending"
      )
    }
  }
  connection <- function(.token_only = FALSE) {
    assert_owner()
    background_token <- .token_only && background
    shiny::isolate(sync(async = background_token))
    changed() # Depend on authorization changes, never on ordinary token rotation.
    if (shiny::isolate(identity_pending())) {
      identity_pending() # Only waiting acquisition subscribes to resumption.
      shiny::req(FALSE)
    }
    if (!is.null(failure)) {
      stop(failure)
    }
    shiny::req(available)
    captured <- epoch
    pinned <- grant
    token <- function(
      force_refresh = FALSE,
      scopes = character(),
      .check_only = FALSE,
      .async = FALSE,
      .min_valid_for = min_valid_for,
      .allow_unacquired = FALSE
    ) {
      .odb_flag(force_refresh, "force_refresh")
      .odb_flag(.check_only, ".check_only")
      .odb_flag(.async, ".async")
      .odb_flag(.allow_unacquired, ".allow_unacquired")
      .odb_seconds(.min_valid_for, ".min_valid_for")
      operation_scopes <- union(required_scopes, .odb_scopes(scopes))
      current(
        captured,
        async = background_token || .async,
        allow_pending = .async || .allow_unacquired
      )
      if (.check_only) {
        if (
          !shiny::isolate(.odb_authorization_has_scopes(
            pinned,
            operation_scopes,
            target
          )) &&
            !(.allow_unacquired &&
              identical(
                shiny::isolate(.odb_authorization_status(pinned, target)),
                "not_acquired"
              ))
        ) {
          .odb_abort(
            "The authorization no longer grants this operation's permissions.",
            "authorization_unavailable"
          )
        }
        return(invisible(NULL))
      }
      # Operation permissions notify only their consumers; token bytes and
      # permissions used by other operations must not replay completed work.
      if (length(setdiff(operation_scopes, required_scopes))) {
        watch_scopes(operation_scopes)
      }
      read <- function() {
        current(captured, async = background_token || .async)
        shiny::isolate(pinned$access_token(
          required_scopes = operation_scopes,
          min_valid_for_seconds = max(min_valid_for, .min_valid_for),
          force_refresh = force_refresh,
          async = .async,
          target = target
        ))
      }
      value <- if (
        .async &&
          !is.null(permission_validation) &&
          permission_validation$pending
      ) {
        promises::then(permission_validation$promise, function(value) read())
      } else {
        read()
      }
      checked <- function(value) {
        current(captured, async = background_token || .async)
        if (
          !shiny::isolate(.odb_authorization_has_scopes(
            pinned,
            operation_scopes,
            target
          ))
        ) {
          .odb_abort(
            "The operation's permissions changed.",
            "authorization_unavailable"
          )
        }
        .odb_string(value, "access token")
        attributes(value) <- NULL
        if (!grepl("^[A-Za-z0-9._~+/-]+=*$", value)) {
          .odb_abort("Invalid bearer token.", "invalid_credential")
        }
        value
      }
      if (.async) {
        promises::then(promises::promise_resolve(value), checked)
      } else {
        checked(value)
      }
    }
    if (.token_only) {
      return(token)
    }
    tryCatch(
      {
        # The backend can check credentials on access and choose its reuse key.
        key <- if (is.function(cache_key)) cache_key(token) else NULL
        if (!is.null(native)) {
          valid <- identical(key, native_key) &&
            if (is.function(is_valid)) {
              tryCatch(isTRUE(is_valid(native)), error = function(e) FALSE)
            } else {
              !inherits(native, "DBIConnection") ||
                tryCatch(isTRUE(DBI::dbIsValid(native)), error = function(e) {
                  FALSE
                })
            }
          if (valid) {
            return(native)
          }
          close_native()
        }
        value <- do.call(connect, c(list(token), args))
        tryCatch(current(captured), error = function(e) {
          tryCatch(.odb_disconnect(value, disconnect), error = function(error) {
            .odb_cleanup_failure()
          })
          stop(e)
        })
        if (is.null(value)) {
          .odb_abort("The connector must return a native connection or client.")
        }
        native <<- value
        native_key <<- key
        value
      },
      error = function(e) {
        if (
          inherits(e, "shinyOAuth_access_error") &&
            isTRUE(
              e$context$reason %in%
                c(
                  "refresh_pending",
                  "interaction_required",
                  "refresh_unavailable",
                  "lifetime_unavailable"
                )
            )
        ) {
          # Only failed acquisition subscribes to credential changes. Retained
          # callbacks run outside this handler, so rotation cannot replay their work.
          status <- .odb_authorization_status(pinned, target)
          if (
            identical(e$context$reason, "refresh_pending") && !is.null(status)
          ) {
            shiny::req(FALSE)
          }
        }
        stop(e)
      }
    )
  }
  observer <- shiny::observe(
    {
      if (!is.null(permission_validation) && !permission_validation$pending) {
        permission_validation <<- NULL
      }
      sync()
    },
    priority = 100,
    domain = owner
  )
  owner$onSessionEnded(function() {
    close_native()
    closed <<- TRUE
    grant <<- NULL
    epoch <<- epoch + 1L
    # Shiny may already have destroyed session-owned reactive values. There
    # are no live consumers to notify; retained accessors check `closed` first.
    observer$destroy()
  })
  attr(connection, ".odb_task") <- list(
    enable_async = function() {
      assert_owner()
      background <<- TRUE
      invisible(NULL)
    },
    pin = function(scopes = required_scopes) {
      scopes <- union(required_scopes, .odb_scopes(scopes))
      provider <- connection(.token_only = TRUE)
      if (!length(setdiff(scopes, required_scopes))) {
        return(provider)
      }
      function(...) provider(..., scopes = scopes)
    },
    watch = function(scopes = required_scopes) {
      assert_owner()
      changed()
      identity_pending()
      task_changed()
      if (length(setdiff(scopes, required_scopes))) {
        watch_scopes(scopes)
      }
      invisible(NULL)
    },
    connect = connect,
    args = args,
    scopes = required_scopes,
    min_valid_for = min_valid_for,
    disconnect = disconnect,
    owner = owner
  )
  connection
}

.odb_disconnect <- function(native, disconnect = NULL) {
  if (is.function(disconnect)) {
    disconnect(native)
  } else if (inherits(native, "AdbiConnection")) {
    suppressWarnings(DBI::dbDisconnect(native, force = TRUE))
  } else if (inherits(native, "DBIConnection")) {
    suppressWarnings(DBI::dbDisconnect(native))
  }
  invisible(NULL)
}

.odb_cleanup_failure <- function() {
  condition <- errorCondition(
    "shinyOAuthDB could not close a native connection.",
    class = c("shinyOAuthDB_cleanup_failed", "shinyOAuthDB_error"),
    reason = "cleanup_failed"
  )
  handler <- getOption("shinyOAuthDB.on_cleanup_error")
  if (is.function(handler)) {
    tryCatch(handler(condition), error = function(error) {
      message(conditionMessage(condition))
    })
  } else {
    message(conditionMessage(condition))
  }
  invisible(NULL)
}
