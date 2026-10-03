multiple_playground_helpers <- function(envir = parent.frame()) {
  paths <- testthat::test_path("..", "..", "playground", c("shared.R", "multiple-connections.R"))
  if (!all(file.exists(paths))) skip("Source-checkout multiple-connections playground smoke.")
  for (path in paths) sys.source(path, envir = envir)
}

multiple_playground_session <- function(cookie) {
  context <- new.env(parent = asNamespace("shiny"))
  context$request_data <- list(HTTP_ORIGIN = "https://multiple.example", HTTP_COOKIE = cookie)
  R6::R6Class(inherit = shiny::MockShinySession, portable = FALSE, lock_objects = FALSE,
    parent_env = context,
    active = list(request = function(value) {
      if (!missing(value)) request_data <<- value
      request_data
    }))$new()
}

multiple_playground_fixture <- function(helper_env = parent.frame(), login_expires = 3600) {
  skip_if_not_installed("RSQLite")
  callbacks <- c("https://multiple.example/callback/login", "https://multiple.example/callback/database")
  provider <- shinyOAuth::oauth_provider(
    "multiple-fixture", auth_url = "https://multiple.invalid/authorize",
    token_url = "https://multiple.invalid/token", token_auth_style = "public"
  )
  client <- function(kind, scope, redirect) shinyOAuth::oauth_client(
    provider, client_id = paste0("fixture-", kind), client_secret = "",
    redirect_uri = redirect, scopes = scope, required_scopes = scope,
    label = helper_env$playground_multiple_labels[[kind]],
    authorization_server_mode = "multi_redirect_uri", authorization_server_redirect_uris = callbacks
  )
  source <- oauth_db_custom("multiple_sqlite", target = NULL, scopes = "demo.read",
    connect = function(config, token_provider) {
      user <- sub("^multiple-fixture-", "", token_provider())
      con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
      DBI::dbWriteTable(con, "visible_rows", data.frame(user = user, marker = paste0(user, "-visible")))
      con
    })
  spec <- list(title = "multiple fixture", source = source, package = "DBI", fun = "dbGetQuery",
    native_args = function(value) list(statement = "SELECT user, marker, ? AS requested_value FROM visible_rows", params = list(value)),
    sync = function(db, args) do.call(DBI::dbGetQuery, c(list(conn = db$connection()), args)),
    note = "Synthetic grant acceptance tests the real manager and local DBI lifecycle, not browser OAuth or remote policy.")
  manager <- shinyOAuth::oauth_connections(
    list(app_login = client("app_login", "openid", callbacks[[1L]]),
         database = client("database", "demo.read", callbacks[[2L]])),
    app_origin = "https://multiple.example", retention = "browser",
    owner_policy = shinyOAuth::oauth_browser_owner(),
    store = shinyOAuth::oauth_connection_store_memory(),
    keys = list(credentials = openssl::rand_bytes(32L), owner = openssl::rand_bytes(32L))
  )
  ui <- shinyOAuth::oauth_connections_ui(helper_env$playground_multiple_ui(spec), "authorizations", manager)
  response <- ui(list(REQUEST_METHOD = "GET", PATH_INFO = "/", SCRIPT_NAME = "",
                      QUERY_STRING = "", HTTP_HOST = "multiple.example", "rook.url_scheme" = "https"))
  cookie <- sub(";.*$", "", response$headers[["Set-Cookie"]])
  seed <- multiple_playground_session(cookie)
  on.exit(seed$close(), add = TRUE)
  ids <- shiny::withReactiveDomain(seed, shiny::isolate({
    # Fixture-only grant acceptance: the public store takes encrypted envelopes,
    # so no public API can import synthetic OAuth grants. The app itself uses
    # only oauth_connections_ui/server and the manager's public returned methods.
    controller <- getFromNamespace("connection_manager_controller", "shinyOAuth")(manager, seed)
    on.exit(controller$end(), add = TRUE)
    accept <- function(kind, user, scope) {
      before <- vapply(controller$records(), function(record) record$stored$id, character(1))
      hooks <- controller$hooks(kind)
      context <- hooks$prepare()
      token <- shinyOAuth::OAuthToken(access_token = paste0("multiple-fixture-", user),
        token_type = "Bearer", expires_at = as.numeric(Sys.time()) +
          if (kind == "app_login") login_expires else 3600,
        refresh_token = paste0("multiple-refresh-", user),
        granted_scopes = scope, granted_scopes_verified = TRUE)
      hooks$accept(token, context, as.numeric(Sys.time()) - 1)
      records <- controller$records()
      all_ids <- vapply(records, function(record) record$stored$id, character(1))
      setdiff(all_ids, before)[[1L]]
    }
    list(login_a = accept("app_login", "LOGIN-A", "openid"),
         login_b = accept("app_login", "LOGIN-B", "openid"),
         database_a = accept("database", "A", "demo.read"),
         database_b = accept("database", "B", "demo.read"))
  }))
  list(manager = manager, spec = spec, cookie = cookie, ids = ids)
}

test_that("the real multi-connection manager never selects a grant implicitly", {
  multiple_playground_helpers()
  fixture <- multiple_playground_fixture(environment())
  server <- playground_multiple_server(fixture$spec, fixture$manager,
    manager_factory = function(id, manager) shinyOAuth::oauth_connections_server(id, manager))
  shiny::testServer(server, session = multiple_playground_session(fixture$cookie), {
    expect_length(auth$connections(), 4L)
    expect_null(database_authorization())
    expect_identical(db$status()$status, "waiting_for_authorization")
    expect_error(auth$connection(), class = "shinyOAuth_access_error")
    expect_error(db$connection(), class = "shinyOAuthDB_authorization_unavailable")

    session$setInputs(app_login_id = fixture$ids$login_a, value = 7L)
    expect_identical(login_id(), fixture$ids$login_a)
    expect_null(database_authorization())
    session$setInputs(database_id = fixture$ids$login_a)
    expect_null(database_authorization())
    session$setInputs(database_id = "foreign-authorization-id")
    expect_null(database_authorization())
    session$setInputs(database_id = fixture$ids$database_a)
    expect_identical(database_authorization()$id, fixture$ids$database_a)
    session$setInputs(run_sync = 1L)
    expect_identical(sync_result()$user, "A")
    expect_identical(sync_result()$requested_value, 7L)
    connection_a <- db$connection()
    session$setInputs(run_sync = 2L)
    expect_identical(db$connection(), connection_a)

    session$setInputs(database_id = fixture$ids$database_b)
    expect_false(DBI::dbIsValid(connection_a))
    expect_error(sync_result(), class = "shiny.silent.error")
    session$setInputs(run_sync = 3L)
    expect_identical(sync_result()$user, "B")

    # A different application login must not carry the active database selection.
    connection_b <- db$connection()
    session$setInputs(app_login_id = fixture$ids$login_b)
    expect_null(database_authorization())
    expect_false(DBI::dbIsValid(connection_b))
    expect_error(sync_result(), class = "shiny.silent.error")
    session$setInputs(database_id = "")
    session$setInputs(database_id = fixture$ids$database_a, run_sync = 4L)
    expect_identical(sync_result()$user, "A")

    provider_a <- db$token_provider()
    session$setInputs(disconnect_database = 1L)
    expect_null(database_authorization())
    expect_error(provider_a(), class = "shinyOAuthDB_authorization_unavailable")
    session$setInputs(logout = 1L)
    expect_length(auth$connections(), 0L)
    expect_null(login_id())
    expect_identical(db$status()$status, "waiting_for_authorization")
  })
})

test_that("retained multi grants restore through a new session without restoring selection", {
  multiple_playground_helpers()
  fixture <- multiple_playground_fixture(environment())
  server <- playground_multiple_server(fixture$spec, fixture$manager,
    manager_factory = function(id, manager) shinyOAuth::oauth_connections_server(id, manager))
  previous_provider <- NULL
  previous_connection <- NULL
  shiny::testServer(server, session = multiple_playground_session(fixture$cookie), {
    session$setInputs(app_login_id = fixture$ids$login_a, value = 5L)
    session$setInputs(database_id = fixture$ids$database_a)
    session$setInputs(run_sync = 1L)
    expect_identical(sync_result()$user, "A")
    previous_provider <<- db$token_provider()
    previous_connection <<- db$connection()
  })
  expect_false(DBI::dbIsValid(previous_connection))
  shiny::testServer(server, session = multiple_playground_session(fixture$cookie), {
    expect_length(auth$connections(), 4L)
    expect_null(database_authorization())
    expect_error(sync_result(), class = "shiny.silent.error")
    expect_error(previous_provider(), class = "shinyOAuthDB_authorization_unavailable")
    session$setInputs(app_login_id = fixture$ids$login_b, value = 9L)
    session$setInputs(database_id = fixture$ids$database_b)
    session$setInputs(run_sync = 1L)
    expect_identical(sync_result()$user, "B")
    expect_false(identical(db$connection(), previous_connection))
  })
})

test_that("same-login pending refresh does not switch DB selection or rerun queries", {
  multiple_playground_helpers()
  skip_if_not_installed("promises")
  fixture <- multiple_playground_fixture(environment())
  refreshes <- 0L
  resolve_refresh <- NULL
  local_mocked_bindings(refresh_token = function(client, token, ...) {
    refreshes <<- refreshes + 1L
    promises::promise(function(resolve, reject) resolve_refresh <<- resolve)
  }, .package = "shinyOAuth")
  reads <- 0L
  native_sync <- fixture$spec$sync
  fixture$spec$sync <- function(db, args) {
    reads <<- reads + 1L
    native_sync(db, args)
  }
  touches <- 0L
  server <- playground_multiple_server(fixture$spec, fixture$manager,
    manager_factory = function(id, manager) {
      auth <- shinyOAuth::oauth_connections_server(id, manager, refresh_proactively = FALSE)
      native_touch <- auth$touch
      auth$touch <- function() {
        touches <<- touches + 1L
        native_touch()
      }
      auth
    })
  shiny::testServer(server, session = multiple_playground_session(fixture$cookie), {
    session$setInputs(app_login_id = fixture$ids$login_a, value = 5L)
    expect_true(selected_login()$has_scopes("openid"))
    expect_identical(login_id(), fixture$ids$login_a)
    session$setInputs(database_id = fixture$ids$database_a)
    session$setInputs(run_sync = 1L)
    expect_identical(sync_result()$user, "A")
    before_connection <- db$connection()
    before_generation <- db$generation()
    expect_identical(reads, 1L)
    before_touches <- touches
    expect_gt(before_touches, 0L)

    pending_refresh <- selected_login()$refresh()
    expect_s3_class(pending_refresh, "promise")
    session$flushReact()
    expect_identical(refreshes, 1L)
    expect_false(selected_login()$is_usable())
    expect_true(selected_login()$has_scopes("openid"))
    expect_identical(login_id(), fixture$ids$login_a)
    expect_identical(database_authorization()$id, fixture$ids$database_a)
    expect_identical(sync_result()$user, "A")
    expect_identical(reads, 1L)
    expect_identical(touches, before_touches)

    resolve_refresh(shinyOAuth::OAuthToken(access_token = "multiple-login-rotated",
      refresh_token = "multiple-refresh-rotated", token_type = "Bearer",
      expires_at = as.numeric(Sys.time()) + 7200, granted_scopes = "openid",
      granted_scopes_verified = TRUE))
    for (i in seq_len(10)) later::run_now(0)
    session$flushReact()
    expect_true(selected_login()$is_usable())
    expect_identical(login_id(), fixture$ids$login_a)
    expect_identical(database_authorization()$id, fixture$ids$database_a)
    expect_identical(db$connection(), before_connection)
    expect_identical(db$generation(), before_generation)
    expect_identical(sync_result()$user, "A")
    expect_identical(reads, 1L)
    expect_identical(touches, before_touches)
  })
})

test_that("multi playground defines separate login and DB consent profiles", {
  multiple_playground_helpers()
  withr::local_envvar(c(OAUTHDB_MULTIPLE_BACKEND = "azure-sql", OAUTHDB_APP_ORIGIN = "http://localhost:8100",
    OAUTHDB_SERVER = "fixture.database.windows.net", OAUTHDB_DATABASE = "fixture",
    OAUTHDB_TENANT_ID = "00000000-0000-0000-0000-000000000001", OAUTHDB_CLIENT_ID = "database-client",
    OAUTHDB_CLIENT_SECRET = "", OAUTHDB_LOGIN_CLIENT_ID = "login-client", OAUTHDB_LOGIN_CLIENT_SECRET = ""))
  playground_require <- function(package) invisible(NULL)
  config <- playground_multiple_config()
  expect_s3_class(config$manager, "OAuthConnections")
  login <- config$manager$clients$app_login
  database <- config$manager$clients$database
  expect_identical(login@client_id, "login-client")
  expect_identical(database@client_id, "database-client")
  expect_identical(login@token_targets, list())
  expect_identical(names(database@token_targets), "sql")
  expect_false(any(grepl("database.windows.net", login@scopes)))
  expect_identical(login@authorization_server_redirect_uris, database@authorization_server_redirect_uris)
})
