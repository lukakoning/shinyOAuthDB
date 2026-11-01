#' Connect another database package to a user's sign-in
#'
#' Use this helper when a database driver accepts an OAuth access token but
#' doesn't have a dedicated shinyOAuthDB helper. Supply its connection function
#' and the name of the argument that takes the token.
#'
#' @param authorization `auth$connection` from a shinyOAuth module, without
#'   parentheses. With a connection manager, use a function that selects
#'   `auth$connection(id)`.
#' @param connect Function that opens the connection, such as `DBI::dbConnect`.
#' @param ... Named arguments passed to `connect`, excluding the token argument.
#' @param token_arg Name of the argument that receives the user's access token.
#' @param target Token target name from the shinyOAuth client. `NULL` uses its
#'   default token, including clients without named targets.
#' @param required_scopes Extra permissions to check before use. Configure
#'   consent and client requirements in shinyOAuth.
#' @param disconnect Optional function to close the connection. By default,
#'   DBI connections use `DBI::dbDisconnect()`; other objects have no cleanup.
#' @param min_valid_for Minimum remaining token lifetime in seconds when
#'   obtaining a token. Defaults to 60; use 0 to accept any unexpired token.
#' @param session Shiny session. Usually inferred; create helpers in `server()`.
#' @return A reactive function. Call `connection <- con()` inside a render or
#'   reactive expression to obtain the connection. Before sign-in, it waits
#'   quietly like `shiny::req()`.
#' @details
#' The helper reuses a connection within the selected authorization and closes
#' it on sign-out or session end. A valid DBI connection stays open through token
#' refresh; an invalid connection reopens on the next call to `con()`.
#'
#' This helper supplies a token when opening a connection. For an API that uses
#' a token on every request, use [oauth_db_token()] or a platform API helper.
#' See `vignette("authorization", package = "shinyOAuthDB")` for connection
#' lifetime, cached results, and background work.
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
#' Use this when an R function accepts an access token as an argument.
#' shinyOAuth obtains or renews the token when you call the returned function.
#' For Fabric and Databricks, the platform API helpers supply credentials for you.
#'
#' @inheritParams oauth_db_connect
#' @return A reactive function returning a bearer-token string. Call `bearer()`
#'   when making a request, inside the user's Shiny session.
#' @details
#' Copied token strings have their own lifetime. Obtain the token for each
#' operation and keep it out of global variables.
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
#' @seealso [oauth_db_fabric_api()], [oauth_db_databricks_api()]
#' @family advanced connection helpers
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
