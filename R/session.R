#' Connect a native database client using a shinyOAuth authorization
#'
#' Supply a native connector that authenticates when opening a connection and
#' its normal arguments. The bridge obtains the user's token when it opens the
#' connection, passes it to the connector, and manages connection lifetime.
#' @param authorization Pass `auth$connection` without calling it, so the helper
#'   follows sign-in and sign-out. Also accepts a reactive selecting
#'   `auth$connection(id)` from a shinyOAuth connection-manager module, or a
#'   module-created connection pinned to one authorization. Select the database
#'   grant explicitly when several exist.
#' @param connect Native connection function, defaulting to `DBI::dbConnect`.
#' @param ... Named arguments for the native connector, such as `drv`, `host`
#'   and `dbname`. Do not include the argument named by `token_arg`.
#' @param token_arg Name of the connector argument receiving the bearer token.
#' @param target Named token target configured on the shinyOAuth client. `NULL`
#'   uses its default, including clients without named token targets.
#' @param required_scopes Required granted permissions. Consent scopes belong in the
#'   shinyOAuth client configuration; setting this argument does not request
#'   additional consent.
#' @param disconnect Native cleanup function. NULL calls `DBI::dbDisconnect()`
#'   for DBI connections and leaves other native values alone. Cleanup is best
#'   effort; it does not revoke credentials already given to the native package.
#' @param min_valid_for Minimum token lifetime requested at acquisition, in seconds.
#'   Defaults to 60; `0` accepts any unexpired token, as in shinyOAuth.
#' @param session Owning Shiny session. Create the helper inside `server()`;
#'   this argument is normally inferred automatically.
#' @return A reactive accessor function: call `con()` inside normal Shiny
#'   reactive or render code to obtain the native connection. Before authorization
#'   it stops silently, like `shiny::req()`. Resolve `connection <- con()` before
#'   passing `connection` to a DBI method so Shiny can wait quietly for sign-in.
#'   Missing permissions produce a Shiny validation message. Invalid targets,
#'   ambiguous authorization selection and other configuration errors retain
#'   their original conditions so the app can explain how to recover.
#' @details
#' Native connections are reused within one session and authorization. Logout,
#' replacement, observed required permission loss or session end retires the
#' cached value and attempts its native cleanup. Subsequent accessor use checks
#' the current authorization. A valid DBI connection stays open through token
#' refresh, preserving transactions and temporary tables. Invalid DBI connections
#' reopen on next access; operations are never retried. The driver determines
#' established-connection expiry.
#'
#' This generic helper injects credentials only when opening a connection. It
#' does not update bearer strings stored inside cached SDK clients, or check
#' non-DBI clients for validity. For APIs authenticating each request with a
#' string, call [oauth_db_token()] for each operation. Backend helpers implement
#' any additional lifecycle their native client needs.
#'
#' Always resolve the accessor for each operation. Previously returned native
#' objects and copied bearer strings retain their own lifetime; the bridge cannot
#' make them unusable or revoke them. A backend's native disconnect operation
#' may be a no-op. See each backend helper for its credential callback and native
#' connection behavior.
#'
#' `min_valid_for` applies when acquiring a token, not to the duration of a query.
#' Credential acquisition is synchronous. If shinyOAuth is already refreshing,
#' the accessor waits silently and a normal reactive consumer resumes when the
#' upstream status changes. Event-bound code keeps its usual Shiny behavior and
#' needs another event. Once a native operation has started, credential callback
#' errors propagate without scheduling a replay. Other acquisition errors remain
#' available to the app. These accessors run in their owning session, not a worker.
#'
#' Queries, their results, event caches and background execution belong to the
#' app and native packages. This bridge does not wrap or store query results.
#' @export
oauth_db_connect <- function(
  authorization, connect = DBI::dbConnect, ..., token_arg = "token",
  target = NULL, required_scopes = character(), disconnect = NULL, min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  if (!is.function(connect)) .odb_abort("connect must be a native connection function.")
  .odb_string(token_arg, "token_arg")
  args <- list(...)
  .odb_named_args(args)
  if (token_arg %in% names(args)) .odb_abort("The bridge supplies the token argument; omit it from ... .")
  factory <- function(token) {
    native_args <- args
    native_args[[token_arg]] <- token()
    do.call(connect, native_args)
  }
  .odb_bind(authorization, factory, target = target, required_scopes = required_scopes,
            disconnect = disconnect, min_valid_for = min_valid_for, session = session)
}

#' Obtain the user's access token for another native client
#'
#' @inheritParams oauth_db_connect
#' @return A reactive accessor returning a current bearer token string. For
#'   `bearer <- oauth_db_token(...)`, call `bearer()`
#'   when making a native request; do not save its value globally.
#' @export
oauth_db_token <- function(authorization, target = NULL, required_scopes = character(),
                           min_valid_for = 60, session = shiny::getDefaultReactiveDomain()) {
  .odb_bind(authorization, function(token) token(), target = target,
    required_scopes = required_scopes, cache_key = function(token) token(),
    min_valid_for = min_valid_for, session = session)
}

# Backend factories receive a grant-pinned credential callback. Only native
# connections/providers are cached; query execution is entirely outside here.
.odb_bind <- function(authorization, connect, ..., target = NULL, required_scopes = character(),
                      disconnect = NULL, cache_key = NULL, min_valid_for = 60,
                      session = shiny::getDefaultReactiveDomain()) {
  if (!is.function(connect) || (!is.null(disconnect) && !is.function(disconnect))) {
    .odb_abort("connect and disconnect must be functions (disconnect may be NULL).")
  }
  .odb_string(target, "target", optional = TRUE)
  required_scopes <- .odb_scopes(required_scopes)
  .odb_seconds(min_valid_for, "min_valid_for")
  args <- list(...)
  .odb_named_args(args)
  owner <- .odb_root_session(session)
  if (is.null(owner) || isTRUE(owner$isClosed()) ||
      !identical(owner, .odb_root_session(shiny::getDefaultReactiveDomain()))) {
    .odb_abort("Create the database helper inside server(), in its owning Shiny session.", "authorization_unavailable")
  }
  reader <- .odb_authorization_reader(authorization)
  grant <- native <- native_key <- failure <- failure_key <- NULL
  available <- closed <- denied <- FALSE
  epoch <- 0L
  changed <- shiny::reactiveVal(0L)

  assert_owner <- function() {
    if (closed || isTRUE(owner$isClosed()) ||
        !identical(owner, .odb_root_session(shiny::getDefaultReactiveDomain()))) {
      .odb_abort("Use the connection in its owning, open Shiny session.", "authorization_unavailable")
    }
  }
  close_native <- function() {
    value <- native
    native <<- NULL
    native_key <<- NULL
    if (!is.null(value)) tryCatch(.odb_disconnect(value, disconnect), error = function(e) NULL)
  }
  sync <- function() {
    assert_owner()
    next_grant <- next_failure <- NULL
    next_available <- next_denied <- FALSE
    tryCatch({
      next_grant <- reader()
      if (!is.null(next_grant)) {
        .odb_authorization_validate(next_grant)
        next_available <- .odb_authorization_has_scopes(next_grant, required_scopes, target)
        status <- .odb_authorization_status(next_grant, target)
        # has_scopes() checks operation scopes, not the client's requirements.
        # Keep an observed denial until upstream supplies affirmative evidence;
        # expiry/refresh can mask it in the public status ordering.
        next_denied <- identical(status, "insufficient_scope") ||
          (identical(next_grant, grant) && denied && !status %in% c("active", "limited"))
        next_available <- next_available && !next_denied
        if (!next_available) {
          if (identical(status, "refreshing") && !next_denied) shiny::req(FALSE)
          next_available <- !next_denied && identical(status, "not_acquired")
          shiny::validate(shiny::need(next_available,
            "The selected authorization lacks the required permissions. Check the client's requested and required scopes, and this helper's target and required_scopes. The helper does not request consent."))
        }
      }
    }, error = function(e) {
      ended <- inherits(e, "shinyOAuth_access_error") &&
        identical(e$context$reason, "authorization_unavailable")
      waiting <- inherits(e, "shiny.silent.error") && !nzchar(conditionMessage(e))
      if (!ended && !waiting) next_failure <<- e
    })
    next_failure_key <- .odb_failure_key(next_failure)
    if (!identical(next_grant, grant) || !identical(next_available, available) ||
        !identical(next_failure_key, failure_key)) {
      close_native()
      epoch <<- epoch + 1L
      changed(epoch)
    }
    grant <<- next_grant
    available <<- next_available
    denied <<- next_denied
    failure <<- next_failure
    failure_key <<- next_failure_key
    invisible(NULL)
  }
  current <- function(captured) {
    assert_owner()
    shiny::isolate(sync())
    if (!available || !identical(epoch, captured)) {
      .odb_abort("This provider's authorization is no longer current.", "authorization_unavailable")
    }
  }
  connection <- function() {
    assert_owner()
    shiny::isolate(sync())
    changed() # Depend on authorization changes, never on ordinary token rotation.
    if (!is.null(failure)) stop(failure)
    shiny::req(available)
    captured <- epoch
    pinned <- grant
    token <- function(force_refresh = FALSE) {
      .odb_flag(force_refresh, "force_refresh")
      current(captured)
      value <- shiny::isolate(pinned$access_token(
        required_scopes = required_scopes, min_valid_for_seconds = min_valid_for,
        force_refresh = force_refresh, async = FALSE, target = target
      ))
      current(captured)
      .odb_string(value, "access token")
      attributes(value) <- NULL
      if (!grepl("^[A-Za-z0-9._~+/-]+=*$", value)) .odb_abort("Invalid bearer token.", "invalid_credential")
      value
    }
    tryCatch({
      # The backend can check credentials on access and choose its reuse key.
      key <- if (is.function(cache_key)) cache_key(token) else NULL
      if (!is.null(native)) {
        valid <- identical(key, native_key) &&
          (!inherits(native, "DBIConnection") ||
            tryCatch(isTRUE(DBI::dbIsValid(native)), error = function(e) FALSE))
        if (valid) return(native)
        close_native()
      }
      value <- do.call(connect, c(list(token), args))
      tryCatch(current(captured), error = function(e) {
        tryCatch(.odb_disconnect(value, disconnect), error = function(e) NULL)
        stop(e)
      })
      if (is.null(value)) .odb_abort("The connector must return a native connection or client.")
      native <<- value
      native_key <<- key
      value
    }, error = function(e) {
      if (inherits(e, "shinyOAuth_access_error") &&
          identical(e$context$reason, "refresh_pending")) {
        # Subscribe only the waiting consumer. Successful operations never
        # depend on token rotation; callbacks already handed out never enter here.
        status <- .odb_authorization_status(pinned, target)
        if (!is.null(status)) shiny::req(FALSE)
      }
      stop(e)
    })
  }
  observer <- shiny::observe(sync(), priority = 100, domain = owner)
  owner$onSessionEnded(function() {
    close_native()
    closed <<- TRUE
    grant <<- NULL
    epoch <<- epoch + 1L
    changed(epoch)
    observer$destroy()
  })
  connection
}

.odb_disconnect <- function(native, disconnect = NULL) {
  if (is.function(disconnect)) disconnect(native)
  else if (inherits(native, "DBIConnection")) suppressWarnings(DBI::dbDisconnect(native))
  invisible(NULL)
}
