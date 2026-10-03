# The internal reference constructor is used only for deterministic fixtures.
# Production code exclusively consumes auth$connection() from public modules.
odb_test_authorization <- function(session, id = "A", scopes = c("read", "write"),
                                   target = NULL, unacquired = FALSE) {
  provider <- shinyOAuth::oauth_provider(
    name = "test", auth_url = "https://example.invalid/authorize",
    token_url = "https://example.invalid/token", token_auth_style = "public",
    token_target_mode = if (is.null(target)) "none" else "rfc8707"
  )
  resource <- "https://example.invalid/api"
  declared <- if (is.null(target)) scopes else paste0(resource, "/", scopes)
  targets <- if (is.null(target)) list() else stats::setNames(
    list(list(resource = resource, scopes = declared, required_scopes = declared[[1L]])), target)
  primary_scope <- "https://example.invalid/primary/read"
  if (unacquired) targets <- c(list(primary = list(resource = "https://example.invalid/primary",
                                                   scopes = primary_scope)), targets)
  client <- shinyOAuth::oauth_client(provider, client_id = "test",
    redirect_uri = "http://localhost:8100", scopes = if (unacquired) c(primary_scope, declared) else declared,
    token_targets = targets, default_token_target = if (unacquired) "primary" else if (is.null(target)) character() else target)
  make_token <- function(value, permissions = declared) shinyOAuth::OAuthToken(
    access_token = value, token_type = "Bearer", expires_at = as.numeric(Sys.time()) + 3600,
    granted_scopes = permissions, granted_scopes_verified = TRUE
  )
  token <- shiny::reactiveVal(if (unacquired) NULL else make_token(paste0("fixture-", id)))
  primary <- if (unacquired) shinyOAuth::OAuthToken(access_token = "fixture-primary", token_type = "Bearer",
    refresh_token = "fixture-refresh", expires_at = as.numeric(Sys.time()) + 3600,
    granted_scopes = primary_scope, granted_scopes_verified = TRUE) else NULL
  current <- shiny::reactiveVal(TRUE)
  calls <- new.env(parent = emptyenv())
  calls$acquire <- 0L
  connection <- getFromNamespace("OAuthConnection", "shinyOAuth")$new(id = id, client = client,
    resolve = function() {
      domain <- shiny::getDefaultReactiveDomain()
      if (is.null(domain) || isTRUE(session$isClosed()) ||
          !identical(domain$rootScope(), session$rootScope()) || !current()) stop("Owner ended")
      list(client = client, token = if (unacquired) primary else token(), status = "active",
           targets = if (unacquired) list(tokens = stats::setNames(list(token()), target)) else NULL)
    },
    acquire = function(async = FALSE, ...) {
      calls$acquire <- calls$acquire + 1L
      token(make_token(paste0("fixture-", id, "-acquired")))
      if (async) promises::promise_resolve(TRUE) else TRUE
    },
    is_current = function() current()
  )
  list(connection = connection, token = token, current = current, calls = calls,
       make_token = make_token, scopes = declared)
}

odb_test_source <- function(target = NULL, scopes = "read", on_connect = NULL,
                            on_disconnect = NULL) {
  oauth_db_custom("fixture_sqlite", target = target, scopes = scopes,
    connect = function(config, token_provider) {
      token <- token_provider()
      if (!is.null(on_connect)) on_connect(token)
      DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    },
    disconnect = function(conn) {
      if (!is.null(on_disconnect)) on_disconnect()
      DBI::dbDisconnect(conn)
    })
}

odb_test_domain <- function(code) {
  session <- shiny::MockShinySession$new()
  on.exit(session$close(), add = TRUE)
  shiny::withReactiveDomain(session, shiny::isolate(code(session)))
}

odb_test_drain <- function(session, until, timeout = 5) {
  deadline <- Sys.time() + timeout
  repeat {
    later::run_now(0.01)
    session$flushReact()
    if (isTRUE(until())) break
    if (Sys.time() >= deadline) stop("Timed out waiting for the asynchronous result")
  }
}
