#' Connect another database package to a user's sign-in
#'
#' Use this when a database driver accepts an OAuth token and has no dedicated
#' shinyOAuthDB helper. Supply the function that opens its connection and name
#' the argument that receives the token.
#'
#' @param authorization `auth$connection` from a shinyOAuth server module,
#'   without parentheses. To select a saved authorization, pass a function
#'   that calls `auth$connection(id)`.
#' @param connect Function that opens the connection, such as `DBI::dbConnect`.
#' @param ... Named arguments for `connect`, excluding the token argument.
#' @param token_arg Name of the argument that receives the user's access token.
#' @param target Token target name in the shinyOAuth client. `NULL` uses its
#'   default token, including for clients without named targets.
#' @param required_scopes Additional permissions to check before use. Request
#'   consent and set the client's permission requirements in shinyOAuth.
#' @param disconnect Function to close the connection. By default, DBI
#'   connections use `DBI::dbDisconnect()`; other objects have no cleanup.
#' @param min_valid_for Minimum remaining token lifetime, in seconds, when
#'   obtaining a token. Use `0` to accept any unexpired token.
#' @param session Shiny session. Inferred when the helper is created in
#'   `server()`.
#' @return A reactive function such as `con`. Call `connection <- con()`
#'   inside a render or reactive expression to get the connection.
#'   Before sign-in, it waits quietly, like `shiny::req()`.
#' @details
#' Create the helper inside `server()` and call `con()` before each query.
#' The helper reuses the connection and closes it when the selected
#' authorization changes, ends, or loses required permissions, or when the
#' Shiny session ends.
#'
#' A valid DBI connection stays open through token refresh. If the connection
#' becomes invalid, the next call opens a new one.
#'
#' This helper supplies the token when opening a connection. For a function
#' that takes a token on each request, use [oauth_db_token()] or a platform
#' API client.
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
#'   `vignette("authorization", package = "shinyOAuthDB")`.
#' @family advanced connection helpers
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

#' Get a user's access token for another R package
#'
#' Use this when an R function accepts an access token directly. Call the
#' returned function for a current token each time you make a request.
#'
#' For Fabric or Databricks functions, the platform API clients below can
#' supply the credentials for you.
#'
#' @inheritParams oauth_db_connect
#' @return A reactive function returning a bearer token string. Call
#'   `bearer()` inside the user's Shiny session.
#' @details
#' shinyOAuth obtains or renews the token. Keep the function in the Shiny
#' session and get a token for each operation; a copied token string keeps
#' its own expiry time.
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
#'   See `vignette("authorization", package = "shinyOAuthDB")` for token lifetime.
#' @family advanced connection helpers
#' @export
oauth_db_token <- function(authorization, target = NULL, required_scopes = character(),
                           min_valid_for = 60, session = shiny::getDefaultReactiveDomain()) {
  .odb_bind(authorization, function(token) token(), target = target,
    required_scopes = required_scopes, cache_key = function(token) token(),
    min_valid_for = min_valid_for, session = session)
}

# The token callback can use only the authorization that created it.
# Cache connections and providers; the caller runs queries.
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
        # Permission evidence drives notifications. Watching token status here
        # could retrigger renewal indefinitely when expiry remains unknown.
        status <- shiny::isolate(.odb_authorization_status(next_grant, target))
        # has_scopes() checks operation scopes, not the client's requirements.
        # Validate those separately when expiry masks the permission status;
        # preserve a previous denial while a refresh hides its evidence.
        next_denied <- .odb_authorization_denied(next_grant, required_scopes, target, status)
        if (isTRUE(status %in% c("expired", "expiry_unknown"))) {
          # Validation can renew credentials or end local access on failure.
          next_available <- .odb_authorization_has_scopes(next_grant, required_scopes, target)
          status <- shiny::isolate(.odb_authorization_status(next_grant, target))
        }
        next_denied <- next_denied || identical(status, "insufficient_scope") ||
          (identical(next_grant, grant) && denied &&
            !status %in% c("active", "limited", "expired", "expiry_unknown"))
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
    token <- function(force_refresh = FALSE, scopes = character()) {
      .odb_flag(force_refresh, "force_refresh")
      operation_scopes <- union(required_scopes, .odb_scopes(scopes))
      current(captured)
      value <- shiny::isolate(pinned$access_token(
        required_scopes = operation_scopes, min_valid_for_seconds = min_valid_for,
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
