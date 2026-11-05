test_that("DSN abbreviations cannot reach the ODBC driver boundary", {
  skip_if_not_installed("odbc")
  strings <- character()
  local_mocked_bindings(odbc_connect = function(connection_string, ...) {
    strings <<- c(strings, connection_string)
    stop(errorCondition("Native boundary reached", class = "native_boundary"))
  }, .package = "odbc")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    helpers <- list(
      function(...) oauth_db_azure_sql(auth$connection, server = "fixed.example", database = "reports", target = NULL, ...),
      function(...) oauth_db_snowflake(auth$connection, server = "fixed.example", database = "reports", role = "READER", required_scopes = "read", ...),
      function(...) oauth_db_redshift(auth$connection, server = "fixed.example", database = "reports", ...))
    for (helper in helpers) {
      for (name in c("d", "ds", "dsn")) {
        expect_error(do.call(helper, stats::setNames(list("ambient-dsn"), name))(),
          class = "shinyOAuthDB_invalid_configuration")
      }
      expect_error(helper(timeout = 12, dbms.name = "review")(), class = "native_boundary")
    }
    expect_length(strings, length(helpers))
    expect_false(any(grepl("(^|;)dsn=", strings, ignore.case = TRUE)))
    expect_true(all(grepl("server=fixed.example", strings, fixed = TRUE)))
  })
})

test_that("PostgreSQL service abbreviations cannot reach libpq", {
  skip_if_not_installed("RPostgres")
  captured <- NULL
  local_mocked_bindings(connection_create = function(keys, values, ...) {
    captured <<- stats::setNames(values, keys)
    stop(errorCondition("Native boundary reached", class = "native_boundary"))
  }, .package = "RPostgres")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    helper <- function(...) oauth_db_azure_postgres(auth$connection, host = "fixed.example",
      dbname = "reports", user = "reader", target = NULL, ...)
    for (name in c("s", "se", "ser", "serv", "servi", "servic", "service")) {
      expect_error(do.call(helper, stats::setNames(list("ambient-service"), name))(),
        class = "shinyOAuthDB_invalid_configuration")
    }
    expect_null(captured)
    expect_error(helper(connect_timeout = 12)(), class = "native_boundary")
    expect_false("service" %in% names(captured))
    expect_identical(captured[["host"]], "fixed.example")
    expect_identical(captured[["connect_timeout"]], "12")
    expect_identical(captured[["sslmode"]], "verify-full")
  })
})

test_that("Fabric rejects abbreviations of its owned native formals", {
  local_mocked_bindings(.odb_require = function(...) TRUE)
  for (name in c("ds", "tenant", "client", "auth_a")) {
    expect_error(do.call(oauth_db_fabric_sql, c(list(NULL, server = "fixed.example", database = "reports"),
      stats::setNames(list("ambient-setting"), name))), class = "shinyOAuthDB_invalid_configuration")
  }
})
