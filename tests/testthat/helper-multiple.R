# Seed real shinyOAuth manager grants; only the OAuth exchange is synthetic.
multiple_session <- function(cookie) {
  context <- new.env(parent = asNamespace("shiny"))
  context$request_data <- list(
    HTTP_ORIGIN = "https://multiple.example",
    HTTP_COOKIE = cookie
  )
  R6::R6Class(
    inherit = shiny::MockShinySession,
    portable = FALSE,
    lock_objects = FALSE,
    parent_env = context,
    active = list(request = function(value) {
      if (!missing(value)) {
        request_data <<- value
      }
      request_data
    })
  )$new()
}

multiple_fixture <- function(
  second_database = FALSE,
  different_providers = FALSE,
  labels = c(login = "login", database = "database", warehouse = "warehouse")
) {
  provider <- shinyOAuth::oauth_provider(
    "fixture",
    auth_url = "https://multiple.invalid/authorize",
    token_url = "https://multiple.invalid/token",
    token_auth_style = "public"
  )
  redirects <- c(
    "https://multiple.example/callback/login",
    "https://multiple.example/callback/database"
  )
  if (second_database) {
    redirects <- c(redirects, "https://multiple.example/callback/warehouse")
  }
  warehouse_provider <- if (different_providers) {
    shinyOAuth::oauth_provider(
      "other",
      auth_url = "https://other.invalid/authorize",
      token_url = "https://other.invalid/token",
      token_auth_style = "public"
    )
  } else {
    provider
  }
  client <- function(kind, scope, redirect) {
    shinyOAuth::oauth_client(
      if (kind == "warehouse") warehouse_provider else provider,
      client_id = kind,
      redirect_uri = redirect,
      scopes = scope,
      required_scopes = scope,
      label = labels[[kind]],
      authorization_server_mode = "multi_redirect_uri",
      authorization_server_redirect_uris = redirects
    )
  }
  clients <- list(
    app_login = client("login", "openid", redirects[[1L]]),
    database = client("database", "demo.read", redirects[[2L]])
  )
  if (second_database) {
    clients$warehouse <- client("warehouse", "warehouse.read", redirects[[3L]])
  }
  manager <- shinyOAuth::oauth_connections(
    clients,
    app_origin = "https://multiple.example",
    retention = "browser",
    owner_policy = shinyOAuth::oauth_browser_owner(),
    store = shinyOAuth::oauth_connection_store_memory(),
    keys = list(
      credentials = openssl::rand_bytes(32L),
      owner = openssl::rand_bytes(32L)
    )
  )
  ui <- shinyOAuth::oauth_connections_ui(
    shiny::fluidPage(),
    "authorizations",
    manager
  )
  response <- ui(list(
    REQUEST_METHOD = "GET",
    PATH_INFO = "/",
    SCRIPT_NAME = "",
    QUERY_STRING = "",
    HTTP_HOST = "multiple.example",
    rook.url_scheme = "https"
  ))
  cookie <- sub(";.*$", "", response$headers[["Set-Cookie"]])
  seed <- multiple_session(cookie)
  on.exit(seed$close(), add = TRUE)
  ids <- shiny::withReactiveDomain(
    seed,
    shiny::isolate({
      # Only fixture seeding uses internals; the running app uses public APIs.
      controller <- getFromNamespace(
        "connection_manager_controller",
        "shinyOAuth"
      )(manager, seed)
      on.exit(controller$end(), add = TRUE)
      accept <- function(kind, user, scope) {
        before <- vapply(
          controller$records(),
          function(x) x$stored$id,
          character(1)
        )
        hooks <- controller$hooks(kind)
        context <- hooks$prepare()
        token <- shinyOAuth::OAuthToken(
          access_token = paste0("fixture-", user),
          token_type = "Bearer",
          expires_at = as.numeric(Sys.time()) + 3600,
          granted_scopes = scope,
          granted_scopes_verified = TRUE
        )
        hooks$accept(token, context, as.numeric(Sys.time()) - 1)
        after <- vapply(
          controller$records(),
          function(x) x$stored$id,
          character(1)
        )
        setdiff(after, before)[[1L]]
      }
      accepted <- list(
        login = accept("app_login", "LOGIN", "openid"),
        a = accept("database", "A", "demo.read"),
        b = accept("database", "B", "demo.read")
      )
      if (second_database) {
        accepted$warehouse <- accept("warehouse", "WAREHOUSE", "warehouse.read")
      }
      accepted
    })
  )
  list(manager = manager, clients = clients, cookie = cookie, ids = ids)
}

multiple_app <- function(fixture, env = parent.frame()) {
  withr::local_envvar(playground_env(), .local_envir = env)
  app <- playground_load_example("example-multiple-connections.R")
  app$manager <- fixture$manager
  app$oauth_db_azure_sql <- function(authorization, ...) {
    oauth_db_connect(
      authorization,
      required_scopes = "demo.read",
      connect = function(token) {
        con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
        DBI::dbWriteTable(
          con,
          "example",
          data.frame(database_user = sub("^fixture-", "", token))
        )
        con
      }
    )
  }
  native_query <- DBI::dbGetQuery
  local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      native_query(conn, "SELECT * FROM example")
    },
    .package = "DBI",
    .env = env
  )
  app
}
