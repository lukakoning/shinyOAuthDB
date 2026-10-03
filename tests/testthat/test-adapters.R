test_that("source profiles keep exact resources and contain no credentials", {
  source <- oauth_db_azure_sql("example.database.windows.net", "Sales")
  same <- oauth_db_azure_sql("example.database.windows.net", "Sales")
  other <- oauth_db_azure_sql("example.database.windows.net", "Finance")
  expect_identical(source$id, same$id)
  expect_false(identical(source$id, other$id))
  expect_identical(source$auth$resource, "https://database.windows.net/")
  expect_identical(source$auth$scopes, "https://database.windows.net//user_impersonation")
  expect_false(any(c("token", "password", "client_secret") %in% names(source$config)))
  expect_output(print(source), "oauth_db_source:azure_sql")
  expect_false(grepl("Sales", paste(capture.output(print(source)), collapse = "")))
})

test_that("constructors reject alternate credentials, endpoints and unsafe TLS", {
  for (options in list(list(UID = "host-user"), list(PWD = "host-password"),
    list(TrustServerCertificate = "yes"), list(dsn = "ambient"),
    list(attributes = list(azure_token = "other-token")))) {
    expect_error(oauth_db_azure_sql("example.database.windows.net", "Sales", options = options),
                 class = "shinyOAuthDB_invalid_configuration")
  }
  expect_error(oauth_db_azure_sql("example.database.windows.net;UID=host-user", "Sales"), "hostname")
  expect_error(oauth_db_sql_server("sql.internal", "Sales"),
               class = "shinyOAuthDB_unsupported_authentication")
  expect_identical(oauth_db_sql_server("sql.internal", "Sales", entra_enabled = TRUE)$backend, "sql_server")
  expect_error(oauth_db_azure_sql("server", "Sales", scopes = "https://graph.microsoft.com/User.Read"), "exact resource")
})

test_that("ODBC values cannot inject additional connection keywords", {
  expect_error(oauth_db_azure_sql("server", "Sales;Server=other.example"), "connection-string delimiters")
  expect_error(oauth_db_azure_sql("server", "Sales", driver = "Driver;UID=other"), "connection-string delimiters")
  expect_error(oauth_db_azure_sql("server", "Sales", options = list(ApplicationIntent = "ReadOnly;Server=other")), "connection-string delimiters")
  expect_error(oauth_db_fabric_sql("server", "Sales;Server=other.example"), "connection-string delimiters")
  expect_error(oauth_db_fabric_sql("server", "Sales", options = list(adbc_driver = "mssql;Server=other")), "connection-string delimiters")
  expect_error(oauth_db_snowflake("account", "DB", "SCHEMA", "WH", "ROLE;TOKEN=other",
    auth_mode = "snowflake_oauth", scopes = "session:role:READER"), "connection-string delimiters")
  expect_error(oauth_db_azure_sql("server", "Sales\n"), "control characters")
  expect_identical(oauth_db_azure_sql("server", "Sales reporting")$config$database, "Sales reporting")
})

test_that("SQL adapter injects the delegated token only through the native token attribute", {
  skip_if_not_installed("odbc")
  state <- new.env(parent = emptyenv())
  state$requests <- 0L
  local_mocked_bindings(dbConnect = function(drv, ...) {
    state$args <- list(...)
    structure(list(), class = "native_connection_fixture")
  }, .package = "DBI")
  source <- oauth_db_azure_sql("example.database.windows.net", "Sales", options = list(timeout = 12))
  provider <- function(force_refresh = FALSE, async = FALSE) {
    state$requests <- state$requests + 1L
    expect_false(force_refresh)
    expect_false(async)
    "visitor-token"
  }
  connection <- .odb_adapter_connect(source, .odb_adapter_token_provider(source, provider))
  expect_s3_class(connection, "native_connection_fixture")
  expect_identical(state$args$attributes, list(azure_token = "visitor-token"))
  expect_identical(state$args$server, "example.database.windows.net,1433")
  expect_identical(state$args$database, "Sales")
  expect_identical(state$args$Encrypt, "yes")
  expect_identical(state$args$TrustServerCertificate, "no")
  expect_identical(state$args$timeout, 12)
  expect_false(any(c("uid", "pwd", "dsn", "authentication") %in% names(state$args)))
  expect_identical(state$requests, 1L)
})

test_that("PostgreSQL profiles expose native role and consent distinctions", {
  source <- oauth_db_azure_postgres("example.postgres.database.azure.com", "Sales", "approved-group")
  expect_identical(source$auth$scopes, "https://ossrdbms-aad.database.windows.net/.default")
  expect_identical(source$auth$required_scopes, character())
  expect_identical(source$config$user, "approved-group")
  expect_identical(source$capabilities$connector_package, "RPostgres")
  expect_match(source$capabilities$native_reconnect, "original token")
  expect_error(oauth_db_azure_postgres("server", "db", "group", options = list(service = "ambient")), "cannot be overridden")
})

test_that("PostgreSQL uses the provisioned role and user token with certificate verification", {
  skip_if_not_installed("RPostgres")
  state <- new.env(parent = emptyenv())
  local_mocked_bindings(dbConnect = function(drv, ...) { state$args <- list(...); "native" }, .package = "DBI")
  source <- oauth_db_azure_postgres("example.postgres.database.azure.com", "Sales", "approved-group",
    sslrootcert = "configured-ca.pem", options = list(connect_timeout = 8))
  expect_identical(.odb_adapter_connect(source, function(force_refresh = FALSE, async = FALSE) "visitor-token"), "native")
  expect_identical(state$args$user, "approved-group")
  expect_identical(state$args$password, "visitor-token")
  expect_identical(state$args$sslmode, "verify-full")
  expect_identical(state$args$sslrootcert, "configured-ca.pem")
  expect_identical(state$args$connect_timeout, 8)
  expect_false(any(c("service", "passfile") %in% names(state$args)))
})

test_that("Snowflake passes OAuth with explicit role and prevents token-file override", {
  skip_if_not_installed("odbc")
  state <- new.env(parent = emptyenv())
  local_mocked_bindings(dbConnect = function(drv, ...) { state$args <- list(...); "native" }, .package = "DBI")
  source <- oauth_db_snowflake("account.snowflakecomputing.com", "DB", "SCHEMA", "WH", "READER",
    provider_family = "microsoft", resource = "api://snowflake",
    scopes = "api://snowflake/session:role:READER")
  expect_identical(.odb_adapter_connect(source, function(force_refresh = FALSE, async = FALSE) "visitor-token"), "native")
  expect_identical(state$args$authenticator, "oauth")
  expect_identical(state$args$token, "visitor-token")
  expect_identical(state$args$role, "READER")
  expect_false(any(c("pwd", "uid", "token_file_path") %in% names(state$args)))
  expect_error(oauth_db_snowflake("account", "DB", "SCHEMA", "WH", "READER",
    provider_family = "microsoft", resource = "api://snowflake",
    scopes = "api://snowflake/session:role:READER", options = list(TOKEN_FILE_PATH = "host-token")), "cannot be overridden")
  native <- oauth_db_snowflake("account", "DB", "SCHEMA", "WH", "READER",
    auth_mode = "snowflake_oauth", scopes = "session:role:READER")
  expect_null(native$auth$target)
  expect_error(.odb_adapter_connect(source,
    function(force_refresh = FALSE, async = FALSE) "token;Server=other.example"),
    class = "shinyOAuthDB_invalid_credential")
  expect_error(.odb_adapter_connect(source,
    function(force_refresh = FALSE, async = FALSE) "token\n"),
    class = "shinyOAuthDB_invalid_credential")
})

test_that("native Databricks and Entra profiles have independent target contracts", {
  native <- oauth_db_databricks("workspace.azuredatabricks.net", "warehouse")
  entra <- oauth_db_databricks("https://workspace.azuredatabricks.net/", "warehouse", auth_mode = "entra")
  expect_identical(native$config$host, "https://workspace.azuredatabricks.net")
  expect_null(native$auth$target)
  expect_identical(native$auth$scopes, "all-apis")
  expect_identical(entra$auth$target, "databricks")
  expect_identical(entra$auth$resource, "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d")
  expect_false(native$capabilities$transactions)
  expect_false(oauth_db_databricks("workspace.example")$capabilities$native_dbi)
  expect_error(oauth_db_databricks("https://workspace.example/other"), "origin")
})

test_that("Databricks keeps workspace-bound refreshable providers for native callers", {
  skip_if_not_installed("brickster")
  state <- new.env(parent = emptyenv())
  state$refresh <- NULL
  source <- oauth_db_databricks("workspace.azuredatabricks.net", "warehouse")
  provider <- .odb_adapter_token_provider(source, function(force_refresh = FALSE, async = FALSE) {
    expect_false(async)
    state$refresh <- force_refresh
    "visitor-token"
  })
  expect_s3_class(provider, "db_token_provider")
  expect_identical(provider$host, "workspace.azuredatabricks.net")
  expect_identical(provider$token(force_refresh = TRUE), "visitor-token")
  expect_true(state$refresh)
  expect_identical(.odb_operation_spec(source, brickster::db_sql_query)$bindings,
                   list(host = "https://workspace.azuredatabricks.net", warehouse_id = "warehouse"))
})

test_that("DBI operation maps preserve native connection arguments and unknown SQL effects", {
  source <- oauth_db_azure_sql("server", "Sales")
  spec <- .odb_operation_spec(source, DBI::dbGetQuery)
  expect_identical(spec$package, "DBI")
  expect_identical(spec$fun, "dbGetQuery")
  expect_identical(spec$credential_arg, "conn")
  expect_identical(spec$connection_arg, "conn")
  expect_identical(spec$effect, "unknown")
  expect_true(all(c("conn", "password", "server") %in% spec$protected_args))
  expect_error(.odb_operation_spec(source, function(...) NULL), class = "shinyOAuthDB_unsupported_operation")
  expect_error(.odb_operation_spec(oauth_db_fabric("fabric"), DBI::dbGetQuery), class = "shinyOAuthDB_unsupported_operation")
})

test_that("Fabric operation maps inject the service's native arguments", {
  skip_if_not_installed("fabricQueryR")
  source <- oauth_db_fabric("kql", cluster = "https://cluster.kusto.fabric.microsoft.com", database = "Events")
  spec <- .odb_operation_spec(source, fabricQueryR::fabric_kql_query)
  expect_identical(spec$bindings, list(cluster = "https://cluster.kusto.fabric.microsoft.com", database = "Events"))
  expect_identical(spec$credential_arg, "token")
  expect_identical(spec$required_scopes, "https://api.kusto.windows.net/user_impersonation")
  expect_error(.odb_operation_spec(source, fabricQueryR::fabric_graphql_query), class = "shinyOAuthDB_unsupported_operation")
  discovery <- .odb_operation_spec(oauth_db_fabric("fabric"), fabricQueryR::fabric_workspaces)
  expect_identical(discovery$bindings$output, "list")
  dax <- oauth_db_fabric("dax", workspace_id = "workspace", dataset_id = "model")
  expect_identical(.odb_operation_spec(dax, fabricQueryR::fabric_pbi_dax_query)$bindings$dataset_id, "model")
  onelake <- oauth_db_fabric("onelake", workspace = "workspace", item = "lakehouse")
  delta <- .odb_operation_spec(onelake, fabricQueryR::fabric_onelake_read_delta_table)
  expect_identical(delta$bindings$workspace_name, "workspace")
  expect_identical(delta$bindings$lakehouse_name, "lakehouse")
})

test_that("Fabric credentials preserve policy via the public upstream seam", {
  skip_if_not_installed("fabricQueryR")
  skip_if_not("fabric_token_provider" %in% getNamespaceExports("fabricQueryR"))
  state <- new.env(parent = emptyenv())
  state$calls <- 0L
  source <- oauth_db_fabric("kql", cluster = "https://cluster.kusto.fabric.microsoft.com", database = "Events")
  provider <- .odb_adapter_token_provider(source, function(force_refresh = FALSE, async = FALSE) {
    state$calls <- state$calls + 1L
    expect_false(async)
    if (force_refresh) stop("worker cannot refresh")
    "delegated-worker-token"
  })
  expect_identical(provider("https://api.kusto.windows.net/.default"), "delegated-worker-token")
  expect_error(provider("https://database.windows.net//.default"), class = "fabric_shiny_error")
  expect_identical(state$calls, 1L)
  expect_error(provider("https://api.kusto.windows.net/.default", TRUE), "worker cannot refresh")
})

test_that("custom portable descriptors delegate to actual DBI engines", {
  skip_if_not_installed("RSQLite")
  source <- oauth_db_custom("sqlite_fixture",
    connect = list(package = "DBI", fun = "dbConnect", driver = list(package = "RSQLite", fun = "SQLite")),
    config = list(dbname = ":memory:"), capabilities = list(connector_package = "RSQLite"))
  expect_false(is.function(source$adapter$connect))
  expect_false(is.function(source$adapter$disconnect))
  expect_false(source$capabilities$delegated_user)
  expect_identical(source$capabilities$credential_transport, "credential_free_fixture")
  con <- .odb_adapter_connect(source, function(...) stop("SQLite fixture should not need tokens"))
  on.exit(.odb_adapter_disconnect(source, con), add = TRUE)
  expect_equal(DBI::dbGetQuery(con, "SELECT 42 AS n")$n, 42L)
  expect_null(source$auth$target)
})

test_that("custom configuration rejects credentials and runtime state recursively", {
  connector <- list(package = "DBI", fun = "dbConnect", driver = list(package = "RSQLite", fun = "SQLite"))
  for (config in list(list(password = "raw-secret"), list(extra = list(access_token = "raw-token")),
    list(raw = new.env(parent = emptyenv())), list(raw = function() "captured-state"),
    list(raw = structure("ordinary", runtime = new.env(parent = emptyenv()))))) {
    expect_error(oauth_db_custom("custom_fixture", connector, config = config),
                 class = "shinyOAuthDB_invalid_configuration")
  }
  expect_error(oauth_db_custom("custom_fixture", connector,
    bindings = list(extra = list(client_secret = "raw-secret"))), "cannot contain credentials")
})

test_that("portable custom connectors inject broker credentials after reading non-secret config", {
  skip_if_not_installed("RSQLite")
  state <- new.env(parent = emptyenv())
  local_mocked_bindings(dbConnect = function(drv, ...) { state$args <- list(...); "native" }, .package = "DBI")
  connector <- list(package = "DBI", fun = "dbConnect",
    driver = list(package = "RSQLite", fun = "SQLite"), credential_arg = "password")
  source <- oauth_db_custom("native_fixture", connector, config = list(dbname = ":memory:"),
    capabilities = list(connector_package = "RSQLite"))
  expect_true(source$capabilities$delegated_user)
  expect_false("password" %in% names(source$config))
  expect_identical(.odb_adapter_connect(source,
    function(force_refresh = FALSE, async = FALSE) "delegated-user-token"), "native")
  expect_identical(state$args$password, "delegated-user-token")
  expect_identical(state$args$dbname, ":memory:")
  expect_no_error(.odb_source_bearer("opaque-bearer-token=="))
})

test_that("source IDs do not serialize closure-captured credentials or session environments", {
  make_hook <- function(secret) {
    force(secret)
    function(config, token_provider) {
      if (identical(secret, "unused")) NULL else token_provider()
    }
  }
  first_hook <- make_hook(new.env(parent = emptyenv()))
  second_hook <- make_hook(new.env(parent = emptyenv()))
  expect_no_warning(first <- oauth_db_custom("custom_fixture", first_hook))
  same <- oauth_db_custom("custom_fixture", first_hook)
  second <- oauth_db_custom("custom_fixture", second_hook)
  expect_identical(first$id, same$id)
  expect_false(identical(first$id, second$id))
  identity <- .odb_source_identity(first_hook)
  expect_type(identity$environment, "character")
  expect_false(any(vapply(identity, is.environment, logical(1))))
})
