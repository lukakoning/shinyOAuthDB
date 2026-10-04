#' Connect a native database client using a shinyOAuth authorization
#'
#' Supply the native connector and its normal arguments. The bridge obtains the
#' user's token, passes it to the connector, and manages connection lifetime.
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
#' @param scopes Required granted permissions. Consent scopes belong in the
#'   shinyOAuth client configuration; setting this argument does not request
#'   additional consent.
#' @param disconnect Native cleanup function. NULL disconnects DBI connections
#'   automatically and leaves other clients alone.
#' @param min_valid_for Minimum token lifetime requested at acquisition, in seconds.
#' @param session Owning Shiny session. Create the helper inside `server()`;
#'   this argument is normally inferred automatically.
#' @return A reactive accessor function: call `con()` inside normal Shiny
#'   reactive or render code to obtain the native connection. Before authorization
#'   it stops silently, like `shiny::req()`. Resolve `connection <- con()` before
#'   passing `connection` to a DBI method so Shiny can wait quietly for sign-in.
#' @details
#' Native connections are reused within one session and authorization, and
#' closed on logout, replacement, observed scope loss or session end. A valid
#' DBI connection stays open through token refresh, preserving transactions and
#' temporary tables. Invalid DBI connections reopen on next access; operations
#' are never retried. The driver determines established-connection expiry.
#'
#' Queries, their results, event caches and background execution belong to the
#' app and native packages. This bridge does not wrap or store query results.
#' @export
oauth_db_connect <- function(
  authorization, connect = DBI::dbConnect, ..., token_arg = "token",
  target = NULL, scopes = character(), disconnect = NULL, min_valid_for = 60,
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
  .odb_bind(authorization, factory, target = target, scopes = scopes,
            disconnect = disconnect, min_valid_for = min_valid_for, session = session)
}

#' Obtain the user's access token for another native client
#'
#' @inheritParams oauth_db_connect
#' @return A reactive accessor returning a current bearer token. Call `token()`
#'   when making a native request; do not save its value globally.
#' @export
oauth_db_token <- function(authorization, target = NULL, scopes = character(),
                           min_valid_for = 60, session = shiny::getDefaultReactiveDomain()) {
  provider <- .odb_bind(authorization, identity, target = target, scopes = scopes,
                        min_valid_for = min_valid_for, session = session)
  function() provider()()
}

# Backend factories receive a grant-pinned credential callback. Only native
# connections/providers are cached; query execution is entirely outside here.
.odb_bind <- function(authorization, connect, ..., target = NULL, scopes = character(),
                      disconnect = NULL, cache_key = NULL, min_valid_for = 60,
                      session = shiny::getDefaultReactiveDomain()) {
  if (!is.function(connect) || (!is.null(disconnect) && !is.function(disconnect))) {
    .odb_abort("connect and disconnect must be functions (disconnect may be NULL).")
  }
  .odb_string(target, "target", optional = TRUE)
  scopes <- .odb_scopes(scopes)
  .odb_seconds(min_valid_for, "min_valid_for", positive = TRUE)
  args <- list(...)
  .odb_named_args(args)
  owner <- .odb_root_session(session)
  if (is.null(owner) || isTRUE(owner$isClosed()) ||
      !identical(owner, .odb_root_session(shiny::getDefaultReactiveDomain()))) {
    .odb_abort("Create the database helper inside server(), in its owning Shiny session.", "authorization_unavailable")
  }
  reader <- .odb_authorization_reader(authorization)
  grant <- native <- native_key <- NULL
  available <- closed <- FALSE
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
    next_grant <- tryCatch(reader(), shinyOAuth_access_error = function(e) NULL,
                           shiny.silent.error = function(e) NULL)
    next_available <- FALSE
    if (!is.null(next_grant)) {
      .odb_authorization_validate(next_grant)
      next_available <- tryCatch(
        .odb_authorization_has_scopes(next_grant, scopes, target),
        shinyOAuth_access_error = function(e) FALSE
      )
      targets <- .odb_authorization_field(next_grant, "targets")
      if (!next_available && !is.null(target) && is.function(targets)) {
        next_available <- identical(
          tryCatch(targets()[[target]]$status, error = function(e) NULL), "not_acquired"
        )
      }
    }
    if (!identical(next_grant, grant) || !identical(next_available, available)) {
      close_native()
      epoch <<- epoch + 1L
      changed(epoch)
    }
    grant <<- next_grant
    available <<- next_available
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
    shiny::req(available)
    captured <- epoch
    pinned <- grant
    token <- function(force_refresh = FALSE) {
      .odb_flag(force_refresh, "force_refresh")
      current(captured)
      value <- shiny::isolate(.odb_authorization_call(pinned, "access_token", list(
        required_scopes = scopes, min_valid_for = min_valid_for,
        force_refresh = force_refresh, async = FALSE, target = target
      )))
      current(captured)
      .odb_string(value, "access token")
      attributes(value) <- NULL
      if (!grepl("^[A-Za-z0-9._~+/-]+=*$", value)) .odb_abort("Invalid bearer token.", "invalid_credential")
      value
    }
    # A backend may supply a key for deciding when its native value expires.
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
