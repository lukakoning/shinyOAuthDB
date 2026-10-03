playground_test_helpers <- function(envir = parent.frame()) {
  shared <- testthat::test_path("..", "..", "playground", "shared.R")
  offline <- testthat::test_path("..", "..", "playground", "offline.R")
  if (!file.exists(shared) || !file.exists(offline)) {
    testthat::skip("Source-checkout playground smoke; run Rscript tools/check-playground.R --test in the repository.")
  }
  sys.source(shared, envir = envir)
  sys.source(offline, envir = envir)
}

test_that("the offline playground exercises connection reuse and A/B isolation", {
  skip_if_not_installed("RSQLite")
  playground_test_helpers()
  app <- playground_offline_app()
  shiny::testServer(app, {
    session$setInputs(select_a = 1L, value = 7L)
    session$setInputs(run_sync = 1L)
    rows_a <- sync_result()
    expect_identical(rows_a$user, c("A", "A"))
    expect_identical(rows_a$requested_value, c(7L, 7L))
    connection_a <- db$connection()
    session$setInputs(value = 8L, run_sync = 2L)
    expect_identical(db$connection(), connection_a)
    expect_identical(sync_result()$requested_value, c(8L, 8L))

    # The same browser replaces its authorization. A's native connection must
    # be retired, and A's already-fetched rows must disappear before B queries.
    session$setInputs(select_b = 1L)
    expect_false(DBI::dbIsValid(connection_a))
    expect_error(sync_result(), class = "shiny.silent.error")
    session$setInputs(run_sync = 3L)
    expect_identical(sync_result()$user, c("B", "B"))
    expect_false(identical(db$connection(), connection_a))

    connection_b <- db$connection()
    session$setInputs(logout = 1L)
    expect_false(DBI::dbIsValid(connection_b))
    expect_error(sync_result(), class = "shiny.silent.error")
    expect_identical(db$status()$status, "waiting_for_authorization")
  })
})

test_that("the offline playground validates bound browser values", {
  skip_if_not_installed("RSQLite")
  playground_test_helpers()
  shiny::testServer(playground_offline_app(), {
    session$setInputs(select_a = 1L, value = -1L, run_sync = 1L)
    expect_error(sync_result(), class = "shiny.silent.error")
    session$setInputs(value = 1.25, run_sync = 2L)
    expect_error(sync_result(), class = "shiny.silent.error")
    session$setInputs(value = 17L, run_sync = 3L)
    expect_identical(sync_result()$requested_value, c(17L, 17L))
  })
})

test_that("separate playground sessions cannot reuse another user's rows", {
  skip_if_not_installed("RSQLite")
  playground_test_helpers()
  app <- playground_offline_app()
  first_connection <- NULL
  shiny::testServer(app, {
    session$setInputs(select_a = 1L, value = 5L, run_sync = 1L)
    expect_identical(sync_result()$user, c("A", "A"))
    first_connection <<- db$connection()
  })
  expect_false(DBI::dbIsValid(first_connection))
  shiny::testServer(app, {
    expect_error(sync_result(), class = "shiny.silent.error")
    session$setInputs(select_b = 1L, value = 9L, run_sync = 1L)
    expect_identical(sync_result()$user, c("B", "B"))
    expect_false(identical(db$connection(), first_connection))
  })
})

test_that("each named playground and live runner is valid R", {
  root <- testthat::test_path("..", "..")
  if (!dir.exists(file.path(root, "playground"))) {
    skip("Source-checkout script smoke; playground scripts are not installed package assets.")
  }
  paths <- list.files(file.path(root, "playground"), pattern = "\\.R$", full.names = TRUE)
  expect_gte(length(paths), 14L)
  for (path in paths) expect_error(parse(path), NA, info = basename(path))
  paths <- list.files(file.path(root, "tests", "integration"), pattern = "\\.R$", full.names = TRUE)
  for (path in paths) expect_error(parse(path), NA, info = basename(path))
})

test_that("live transport tests require an explicit opt-in before configuration", {
  playground_test_helpers()
  sys.source(testthat::test_path("..", "integration", "live-transport.R"), envir = environment())
  withr::local_envvar(c(OAUTHDB_LIVE_TESTS = "false", OAUTHDB_CLIENT_ID = NA_character_))
  expect_error(run_live_transport(list()), "disabled")
})

test_that("live playground configurations match native adapter operation arguments", {
  playground_test_helpers()
  # These are synthetic static configuration values. No client signs in and
  # no driver connection/network request is opened by this scenario.
  withr::local_envvar(c(
    OAUTHDB_SERVER = "fixture.database.windows.net", OAUTHDB_DATABASE = "fixture",
    OAUTHDB_SQL_SERVER_ENTRA_ENABLED = "true",
    OAUTHDB_POSTGRES_HOST = "fixture.postgres.database.azure.com",
    OAUTHDB_POSTGRES_USER = "fixture-role", OAUTHDB_POSTGRES_SSLROOTCERT = "fixture-ca.pem",
    OAUTHDB_SNOWFLAKE_SERVER = "fixture.snowflakecomputing.com",
    OAUTHDB_SNOWFLAKE_SCHEMA = "PUBLIC", OAUTHDB_SNOWFLAKE_WAREHOUSE = "FIXTURE_WH",
    OAUTHDB_SNOWFLAKE_ROLE = "READER", OAUTHDB_SNOWFLAKE_RESOURCE = "api://fixture",
    OAUTHDB_SNOWFLAKE_SCOPES = "api://fixture/session:role:READER",
    OAUTHDB_DATABRICKS_HOST = "https://fixture.azuredatabricks.net",
    OAUTHDB_DATABRICKS_WAREHOUSE = "fixture-warehouse",
    OAUTHDB_KQL_CLUSTER = "https://fixture.kusto.fabric.microsoft.com",
    OAUTHDB_KQL_DATABASE = "fixture-kql", OAUTHDB_FABRIC_WORKSPACE = "fixture-workspace",
    OAUTHDB_FABRIC_MODEL = "fixture-model", OAUTHDB_GRAPHQL_API = "fixture-api",
    OAUTHDB_GRAPHQL_ENDPOINT_HOSTS = "api.fabric.microsoft.com",
    OAUTHDB_ONELAKE_ITEM = "Fixture.Lakehouse"
  ))
  # Configuration can be tested even when a native driver is not installed.
  playground_require <- function(package) invisible(NULL)
  backends <- c("azure-sql", "sql-server", "azure-postgres", "snowflake")
  if (requireNamespace("brickster", quietly = TRUE)) backends <- c(backends, "databricks")
  if (requireNamespace("fabricQueryR", quietly = TRUE)) {
    backends <- c(backends, "fabric-sql", "fabric-kql", "fabric-dax",
                  "fabric-graphql", "fabric-onelake", "fabric-discovery")
  }
  for (backend in backends) {
    spec <- playground_spec(backend)
    operation <- getExportedValue(spec$package, spec$fun)
    descriptor <- .odb_operation_spec(spec$source, operation)
    expect_error(.odb_task_check_args(spec$native_args(7L), descriptor), NA, info = backend)
    if (backend == "fabric-graphql") {
      expect_identical(spec$source$config$endpoint_hosts, "api.fabric.microsoft.com")
      expect_false("endpoint_hosts" %in% names(spec$native_args(7L)))
    }
    if (isTRUE(spec$source$capabilities$native_dbi) && spec$package == "DBI") {
      expect_identical(spec$native_args(7L)$statement, spec$native_args(9L)$statement)
      expect_identical(spec$native_args(7L)$params, list(7L))
    }
  }
})
