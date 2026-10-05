test_that("unsupported installed backend versions fail before opening a connection", {
  skip_if_not_installed("odbc")
  skip_if_not_installed("fabricQueryR")
  skip_if_not_installed("brickster")
  local_mocked_bindings(packageVersion = function(pkg, ...) package_version("0.0.1"),
    .package = "utils")
  expect_error(oauth_db_fabric_sql(NULL, "server", "db"),
    "fabricQueryR >= 1.0.1", fixed = TRUE, class = "shinyOAuthDB_missing_dependency")
  expect_error(oauth_db_databricks(NULL, "workspace.example", "warehouse"),
    "brickster >= 0.2.14", fixed = TRUE, class = "shinyOAuthDB_missing_dependency")
  expect_error(oauth_db_azure_sql(NULL, "server", "db"),
    "odbc >= 1.4.2", fixed = TRUE, class = "shinyOAuthDB_missing_dependency")
  expect_error(oauth_db_snowflake(NULL, "account", role = "READER"),
    "odbc >= 1.4.2", fixed = TRUE, class = "shinyOAuthDB_missing_dependency")
})

test_that("backend helpers bind OAuth resources without query operation mappings", {
  local_mocked_bindings(.odb_bind = capture_backend, .odb_require = function(...) TRUE,
    .package = "shinyOAuthDB")
  auth <- function() stop("Creating an accessor must not acquire authorization")
  sql <- oauth_db_azure_sql(auth, "server", "Sales", timeout = 12)
  expect_identical(sql$authorization, auth)
  expect_identical(sql$required_scopes, "https://database.windows.net//user_impersonation")
  expect_identical(sql$args$options, list(timeout = 12))
  postgres <- oauth_db_azure_postgres(auth, "server", "Sales", "user")
  expect_identical(postgres$required_scopes, character())
  fabric <- oauth_db_fabric(auth, "kql")
  expect_identical(fabric$target, "kusto")
  expect_identical(fabric$required_scopes, "https://api.kusto.windows.net/user_impersonation")
  expect_false(any(c("cluster", "database", "workspace", "operation") %in% names(fabric$args)))
  native <- oauth_db_databricks(auth, "workspace.example", "warehouse")
  entra <- oauth_db_databricks(auth, "workspace.example", "warehouse", auth_mode = "entra")
  expect_null(native$target)
  expect_identical(native$required_scopes, "all-apis")
  expect_identical(entra$target, "databricks")
  expect_identical(entra$required_scopes, "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d/user_impersonation")
  expect_error(oauth_db_databricks(auth, "workspace.example", catalog = "main"), "warehouse_id")
  expect_error(oauth_db_databricks(auth, warehouse_id = "warehouse"), "Supply host")
  expect_identical(oauth_db_sql_server(auth, "server", "Sales", timeout = 12), sql)
})

test_that("native options cannot substitute credentials or weaken TLS", {
  local_mocked_bindings(.odb_bind = capture_backend, .odb_require = function(...) TRUE,
    .package = "shinyOAuthDB")
  for (option in list(list(UID = "host-user"), list(PWD = "secret"),
    list(TrustServerCertificate = "yes"), list(dsn = "host-dsn"),
    list(attributes = list(azure_token = "other")), list(Authentication = "ActiveDirectoryDefault"),
    list(`Trusted Connection` = "yes"), list(`.connection_string` = "UID=user"))) {
    error <- expect_error(do.call(oauth_db_azure_sql, c(list(NULL, "server", "Sales"), option)),
      "cannot be overridden")
    expect_match(conditionMessage(error), names(option), fixed = TRUE)
    expect_false(grepl("secret", conditionMessage(error), fixed = TRUE))
  }
  expect_error(oauth_db_azure_postgres(NULL, "host", "db", "user", sslmode = "disable"), "cannot be overridden")
  expect_error(oauth_db_azure_postgres(NULL, "host", "db", "user", service = "ambient"), "cannot be overridden")
  expect_error(oauth_db_fabric_sql(NULL, "server", "db", sql_token = "other"), "cannot be overridden")
  expect_error(oauth_db_databricks(NULL, "host", "warehouse", token = "other"), "cannot be overridden")
  expect_error(oauth_db_snowflake(NULL, "host", "db", "schema", "wh", "role",
    required_scopes = "session:role:role", TOKEN_FILE_PATH = "host-token"), "cannot be overridden")
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

test_that("Snowflake derives native role scopes and honors explicit external OAuth scopes", {
  local_mocked_bindings(.odb_require = function(...) TRUE,
    .odb_backend_snowflake = function(token, server, database, schema, warehouse, role, driver, options) {
      list(token = token(), role = role)
    })
  odb_test_domain(function(session) {
    native <- odb_test_authorization(session, scopes = "session:role:READER")
    con <- oauth_db_snowflake(native$connection, "account", "db", "PUBLIC", "wh", "READER")
    expect_equal(con(), list(token = "fixture-A", role = "READER"))
    denied <- oauth_db_snowflake(native$connection, "account", "db", "PUBLIC", "wh", "OTHER")
    expect_error(denied(), class = "shiny.silent.error")

    external <- odb_test_authorization(session, "B", scopes = "read", target = "snowflake")
    custom <- oauth_db_snowflake(external$connection, "account", "db", "PUBLIC", "wh", "READER",
      required_scopes = external$scopes, target = "snowflake")
    expect_equal(custom(), list(token = "fixture-B", role = "READER"))
    external$current(FALSE)
    expect_error(custom(), class = "shiny.silent.error")
    expect_equal(con(), list(token = "fixture-A", role = "READER"))
  })
})

test_that("Snowflake can use native context defaults while keeping the role explicit", {
  skip_if_not_installed("odbc")
  captured <- NULL
  local_mocked_bindings(dbConnect = function(drv, ...) {
    captured <<- list(...)
    "native"
  }, .package = "DBI")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = "session:role:READER")
    con <- oauth_db_snowflake(auth$connection, "account", role = "READER")
    expect_identical(con(), "native")
    expect_false(any(c("database", "schema", "warehouse") %in% names(captured)))
    expect_identical(captured$role, "READER")
    expect_identical(captured$authenticator, "oauth")
    expect_identical(captured$token, "fixture-A")
    partial <- oauth_db_snowflake(auth$connection, "account", role = "READER",
      warehouse = "COMPUTE_WH")
    expect_identical(partial(), "native")
    expect_identical(captured$warehouse, "COMPUTE_WH")
    expect_false(any(c("database", "schema") %in% names(captured)))
    expect_error(oauth_db_snowflake(auth$connection, "account"), "role")
    expect_error(oauth_db_snowflake(auth$connection, "account", role = NULL), "role")
  })
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

test_that("plain Fabric callbacks enforce service routing and forward refresh failures", {
  state <- new.env(parent = emptyenv())
  state$calls <- 0L
  provider <- .odb_backend_fabric(function(force_refresh = FALSE) {
    state$calls <- state$calls + 1L
    if (force_refresh) stop("refresh unavailable")
    "visitor-token"
  }, "kql", .odb_fabric_profile("kql")$scopes)
  expect_identical(provider("https://api.kusto.windows.net/.default"), "visitor-token")
  expect_error(provider("https://database.windows.net//.default"), class = "shinyOAuthDB_invalid_audience")
  expect_identical(state$calls, 1L)
  expect_error(provider("https://api.kusto.windows.net/.default", TRUE), "refresh unavailable")
  expect_identical(class(provider), "function")
  expect_null(attr(provider, "fabric_endpoint_policy"))
})

test_that("Fabric accepts an authorization without named targets when target is NULL", {
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = .odb_fabric_profile("kql")$scopes)
    token <- oauth_db_fabric(auth$connection, "kql", target = NULL)
    provider <- token()
    expect_identical(provider("https://api.kusto.windows.net/.default"), "fixture-A")
    auth$token(auth$make_token("refreshed-A"))
    expect_identical(provider("https://api.kusto.windows.net/.default"), "refreshed-A")
  })
})

test_that("Fabric SQL uses native connection options and its checked provider", {
  skip_if_not_installed("fabricQueryR")
  state <- new.env(parent = emptyenv())
  local_mocked_bindings(fabric_sql_connect = function(...) {
    state$args <- list(...)
    "native"
  }, .package = "fabricQueryR")
  expect_identical(.odb_backend_fabric_sql(function(force_refresh = FALSE) "visitor-token",
    "server", "Sales", .odb_fabric_profile("sql")$scopes,
    list(backend = "adbc", read_only = TRUE)), "native")
  expect_identical(state$args$backend, "adbc")
  expect_true(state$args$read_only)
  expect_identical(state$args$encrypt, "yes")
  expect_identical(state$args$trust_server_certificate, "no")
  expect_identical(state$args$token("https://database.windows.net//.default"), "visitor-token")
})

test_that("Databricks passes a bearer string to upstream brickster DBI", {
  skip_if_not_installed("brickster")
  token <- function(force_refresh = FALSE) {
    if (force_refresh) stop("refresh unavailable")
    "visitor-token"
  }
  state <- new.env(parent = emptyenv())
  local_mocked_bindings(dbConnect = function(drv, ...) {
    state$args <- list(...)
    "native"
  }, .package = "DBI")
  expect_identical(.odb_backend_databricks(token, "workspace.example", "wh", NULL,
                                         list(catalog = "main")), "native")
  expect_identical(state$args$token, "visitor-token")
  expect_identical(state$args$catalog, "main")
})

test_that("upstream brickster connections rotate their fixed token and isolate grants", {
  skip_if_not_installed("brickster")
  state <- new.env(parent = emptyenv())
  state$tokens <- character()
  local_mocked_bindings(db_sql_query = function(..., token) {
    state$tokens <- c(state$tokens, token)
    data.frame(test_connection = 1L)
  }, .package = "brickster")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = "all-apis")
    con <- oauth_db_databricks(auth$connection, "https://workspace.example/", "wh")
    token <- oauth_db_token(auth$connection, required_scopes = "all-apis")
    first <- con()
    expect_s4_class(first, "DatabricksConnection")
    expect_identical(first@token, "fixture-A")
    expect_identical(first@host, "workspace.example")
    expect_identical(con(), first)
    expect_length(state$tokens, 1L)
    expect_identical(token(), "fixture-A")
    auth$token(auth$make_token("refreshed-A"))
    refreshed <- con()
    expect_identical(refreshed@token, "refreshed-A")
    expect_identical(token(), "refreshed-A")
    expect_identical(state$tokens, c("fixture-A", "refreshed-A"))
    auth$current(FALSE)
    expect_error(con(), class = "shiny.silent.error")
    expect_error(token(), class = "shiny.silent.error")
  })
})

test_that("Databricks preserves native HTTP paths and query results", {
  skip_if_not_installed("brickster")
  calls <- list()
  local_mocked_bindings(db_sql_query = function(warehouse_id, statement, token, ...) {
    calls[[length(calls) + 1L]] <<- list(warehouse_id = warehouse_id, statement = statement, token = token)
    data.frame(value = 42L)
  }, .package = "brickster")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = "all-apis")
    con <- oauth_db_databricks(auth$connection, "workspace.example",
      http_path = "/sql/1.0/warehouses/path-warehouse", catalog = "main", schema = "reporting")
    native <- con()
    expect_s4_class(native, "DatabricksConnection")
    expect_identical(native@warehouse_id, "path-warehouse")
    expect_identical(native@catalog, "main")
    expect_identical(native@schema, "reporting")
    expect_identical(DBI::dbGetQuery(native, "SELECT 42 AS value"), data.frame(value = 42L))
    expect_identical(calls[[2L]], list(warehouse_id = "path-warehouse",
      statement = "SELECT 42 AS value", token = "fixture-A"))
    expect_error(oauth_db_databricks(auth$connection, "workspace.example"), "warehouse_id or http_path")
    expect_error(oauth_db_databricks(auth$connection, "workspace.example", "wh",
      http_path = "/sql/1.0/warehouses/other"), "only one")
    expect_error(oauth_db_databricks(auth$connection), "oauth_db_token")
  })
})
