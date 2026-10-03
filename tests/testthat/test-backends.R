capture_backend <- function(authorization, connect, ..., target = NULL,
                            scopes = character(), min_valid_for = 60, session = NULL) {
  list(authorization = authorization, connect = connect, args = list(...),
    target = target, scopes = scopes)
}

test_that("backend helpers bind OAuth resources without query operation mappings", {
  local_mocked_bindings(.odb_bind = capture_backend, .odb_require = function(...) TRUE,
    .odb_backend_require_hook = function(...) TRUE, .package = "shinyOAuthDB")
  auth <- function() stop("Creating an accessor must not acquire authorization")
  sql <- oauth_db_azure_sql(auth, "server", "Sales", timeout = 12)
  expect_identical(sql$authorization, auth)
  expect_identical(sql$scopes, "https://database.windows.net//user_impersonation")
  expect_identical(sql$args$options, list(timeout = 12))
  postgres <- oauth_db_azure_postgres(auth, "server", "Sales", "user")
  expect_identical(postgres$scopes, "https://ossrdbms-aad.database.windows.net/.default")
  fabric <- oauth_db_fabric(auth, "kql")
  expect_identical(fabric$target, "kusto")
  expect_identical(fabric$scopes, "https://api.kusto.windows.net/user_impersonation")
  expect_false(any(c("cluster", "database", "workspace", "operation") %in% names(fabric$args)))
  native <- oauth_db_databricks(auth, "workspace.example")
  entra <- oauth_db_databricks(auth, "workspace.example", auth_mode = "entra")
  expect_null(native$target)
  expect_identical(native$scopes, "all-apis")
  expect_identical(entra$target, "databricks")
  expect_identical(entra$scopes, "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d/user_impersonation")
  expect_error(oauth_db_databricks(auth, "workspace.example", catalog = "main"), "warehouse_id")
  expect_error(oauth_db_sql_server(auth, "server", "Sales"), "Entra")
  expect_identical(oauth_db_sql_server(auth, "server", "Sales", entra_enabled = TRUE)$connect,
    sql$connect)
})

test_that("native options cannot substitute credentials or weaken TLS", {
  local_mocked_bindings(.odb_bind = capture_backend, .odb_require = function(...) TRUE,
    .odb_backend_require_hook = function(...) TRUE, .package = "shinyOAuthDB")
  for (option in list(list(UID = "host-user"), list(PWD = "secret"),
    list(TrustServerCertificate = "yes"), list(dsn = "host-dsn"),
    list(attributes = list(azure_token = "other")), list(Authentication = "ActiveDirectoryDefault"),
    list(`Trusted Connection` = "yes"), list(`.connection_string` = "UID=user"))) {
    expect_error(do.call(oauth_db_azure_sql, c(list(NULL, "server", "Sales"), option)),
      "cannot be overridden")
  }
  expect_error(oauth_db_azure_postgres(NULL, "host", "db", "user", sslmode = "disable"), "cannot be overridden")
  expect_error(oauth_db_azure_postgres(NULL, "host", "db", "user", service = "ambient"), "cannot be overridden")
  expect_error(oauth_db_fabric_sql(NULL, "server", "db", sql_token = "other"), "cannot be overridden")
  expect_error(oauth_db_databricks(NULL, "host", "warehouse", token = "other"), "cannot be overridden")
  expect_error(oauth_db_snowflake(NULL, "host", "db", "schema", "wh", "role",
    scopes = "session:role:role", TOKEN_FILE_PATH = "host-token"), "cannot be overridden")
  expect_error(oauth_db_azure_sql(NULL, "server", "db;UID=host-user"), "delimiters")
  expect_error(oauth_db_azure_sql(NULL, "server", "db", ApplicationIntent = "ReadOnly;UID=user"), "delimiters")
  expect_error(oauth_db_azure_sql(NULL, "server", "db", timeout = 1, TIMEOUT = 2), "unique names")
  expect_error(oauth_db_azure_sql(NULL, "server", "db", 42), "unique names")
})

test_that("SQL and Snowflake use only the supplied delegated token", {
  skip_if_not_installed("odbc")
  state <- new.env(parent = emptyenv())
  local_mocked_bindings(dbConnect = function(drv, ...) {
    state$args <- list(...)
    "native"
  }, .package = "DBI")
  expect_identical(.odb_backend_sql(function() "visitor-token", "server", "Sales",
    "ODBC Driver 18 for SQL Server", 1433L, list(timeout = 12)), "native")
  expect_identical(state$args$attributes, list(azure_token = "visitor-token"))
  expect_identical(state$args$server, "server,1433")
  expect_identical(state$args$Encrypt, "yes")
  expect_identical(state$args$TrustServerCertificate, "no")
  expect_identical(state$args$timeout, 12)
  expect_false(any(c("uid", "pwd", "authentication", "dsn") %in% tolower(names(state$args))))
  expect_identical(.odb_backend_snowflake(function() "visitor-token", "account", "db",
    "schema", "wh", "role", "SnowflakeDSIIDriver", list()), "native")
  expect_identical(state$args$authenticator, "oauth")
  expect_identical(state$args$token, "visitor-token")
  expect_identical(state$args$role, "role")
  expect_error(.odb_backend_sql(function() stop("authorization unavailable"), "server", "db",
    "driver", 1433L, list()), "authorization unavailable")
})

test_that("Azure PostgreSQL uses the provisioned role with certificate verification", {
  skip_if_not_installed("RPostgres")
  state <- new.env(parent = emptyenv())
  local_mocked_bindings(dbConnect = function(drv, ...) {
    state$args <- list(...)
    "native"
  }, .package = "DBI")
  expect_identical(.odb_backend_postgres(function() "visitor-token", "host", "db",
    "approved-role", 5432L, "ca.pem", list(connect_timeout = 8)), "native")
  expect_identical(state$args$user, "approved-role")
  expect_identical(state$args$password, "visitor-token")
  expect_identical(state$args$sslmode, "verify-full")
  expect_identical(state$args$sslrootcert, "ca.pem")
  expect_identical(state$args$connect_timeout, 8)
})

test_that("Fabric retains audience routing and forwards refresh failures", {
  skip_if_not_installed("fabricQueryR")
  skip_if_not("fabric_token_provider" %in% getNamespaceExports("fabricQueryR"))
  state <- new.env(parent = emptyenv())
  state$calls <- 0L
  provider <- .odb_backend_fabric(function(force_refresh = FALSE) {
    state$calls <- state$calls + 1L
    if (force_refresh) stop("refresh unavailable")
    "visitor-token"
  }, "kql", .odb_backend_profile("kql")$scopes, character())
  expect_identical(provider("https://api.kusto.windows.net/.default"), "visitor-token")
  expect_error(provider("https://database.windows.net//.default"), class = "fabric_shiny_error")
  expect_identical(state$calls, 1L)
  expect_error(provider("https://api.kusto.windows.net/.default", TRUE), "refresh unavailable")
  expect_false(is.null(attr(provider, "fabric_endpoint_policy")))
})

test_that("Fabric accepts an authorization without named targets when target is NULL", {
  skip_if_not_installed("fabricQueryR")
  skip_if_not("fabric_token_provider" %in% getNamespaceExports("fabricQueryR"))
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = .odb_backend_profile("kql")$scopes)
    token <- oauth_db_fabric(auth$connection, "kql", target = NULL)
    provider <- token()
    expect_identical(provider("https://api.kusto.windows.net/.default"), "fixture-A")
    auth$token(auth$make_token("refreshed-A"))
    expect_identical(provider("https://api.kusto.windows.net/.default"), "refreshed-A")
  })
})

test_that("Fabric SQL uses native connection options and its checked provider", {
  skip_if_not_installed("fabricQueryR")
  skip_if_not("fabric_token_provider" %in% getNamespaceExports("fabricQueryR"))
  state <- new.env(parent = emptyenv())
  local_mocked_bindings(fabric_sql_connect = function(...) {
    state$args <- list(...)
    "native"
  }, .package = "fabricQueryR")
  expect_identical(.odb_backend_fabric_sql(function(force_refresh = FALSE) "visitor-token",
    "server", "Sales", .odb_backend_profile("sql")$scopes, character(),
    list(backend = "adbc", read_only = TRUE)), "native")
  expect_identical(state$args$backend, "adbc")
  expect_true(state$args$read_only)
  expect_identical(state$args$encrypt, "yes")
  expect_identical(state$args$trust_server_certificate, "no")
  expect_identical(state$args$token("https://database.windows.net//.default"), "visitor-token")
})

test_that("Databricks uses a workspace-bound provider in REST and DBI modes", {
  skip_if_not_installed("brickster")
  skip_if_not("db_token_provider" %in% getNamespaceExports("brickster"))
  token <- function(force_refresh = FALSE) {
    if (force_refresh) stop("refresh unavailable")
    "visitor-token"
  }
  provider <- .odb_backend_databricks(token, "https://workspace.example", NULL, list())
  expect_s3_class(provider, "db_token_provider")
  expect_identical(provider$host, "workspace.example")
  expect_identical(provider$token(), "visitor-token")
  expect_error(provider$token(TRUE), "refresh unavailable")
  state <- new.env(parent = emptyenv())
  local_mocked_bindings(dbConnect = function(drv, ...) {
    state$args <- list(...)
    "native"
  }, .package = "DBI")
  expect_identical(.odb_backend_databricks(token, "workspace.example", "wh", list(catalog = "main")), "native")
  expect_s3_class(state$args$token, "db_token_provider")
  expect_identical(state$args$token$token(), "visitor-token")
  expect_identical(state$args$catalog, "main")
})
