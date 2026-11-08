test_that("ADBC cleanup closes outstanding DBI and Arrow results", {
  skip_if_not_installed("adbi")
  skip_if_not_installed("duckdb")
  withr::local_options(adbi.force_close_results = FALSE)

  for (send in list(DBI::dbSendQuery, DBI::dbSendQueryArrow)) {
    for (transition in c("replace", "logout", "permissions", "session_end")) {
      odb_test_domain(function(session) {
        a <- odb_test_authorization(session)
        b <- odb_test_authorization(session, "B")
        selected <- shiny::reactiveVal(a$connection)
        con <- oauth_db_connect(
          selected,
          required_scopes = "read",
          connect = function(token) {
            DBI::dbConnect(adbi::adbi(duckdb::duckdb_adbc()))
          }
        )
        native <- con()
        on.exit({
          if (DBI::dbIsValid(native)) {
            suppressWarnings(DBI::dbDisconnect(native, force = TRUE))
          }
        }, add = TRUE)
        result <- send(native, "SELECT 42 AS answer")
        expect_true(DBI::dbIsValid(result))

        switch(
          transition,
          replace = selected(b$connection),
          logout = selected(NULL),
          permissions = a$token(a$make_token("denied", "write")),
          session_end = session$close()
        )
        if (transition != "session_end") {
          session$flushReact()
        }
        expect_false(DBI::dbIsValid(native), info = transition)
        expect_false(DBI::dbIsValid(result), info = transition)
      })
    }
  }
})

test_that("custom cleanup still owns ADBC connections", {
  skip_if_not_installed("adbi")
  skip_if_not_installed("duckdb")
  native <- DBI::dbConnect(adbi::adbi(duckdb::duckdb_adbc()))
  on.exit(DBI::dbDisconnect(native, force = TRUE), add = TRUE)
  cleaned <- NULL
  .odb_disconnect(native, function(value) cleaned <<- value)
  expect_identical(cleaned, native)
  expect_true(DBI::dbIsValid(native))
})

test_that("Fabric validates native options for the selected SQL backend", {
  local_mocked_bindings(
    .odb_bind = capture_backend,
    .odb_require = function(...) TRUE,
    .package = "shinyOAuthDB"
  )
  auth <- function() stop("Configuration must not acquire credentials")
  path <- "C:/drivers/{team}/mssql.dll"
  adbc <- oauth_db_fabric_sql(
    auth,
    "example.datawarehouse.fabric.microsoft.com",
    "Reporting",
    backend = "adbc",
    adbc_driver = path,
    bigint = "integer64"
  )
  expect_identical(adbc$args$options$adbc_driver, path)
  expect_identical(adbc$args$options$bigint, "integer64")
  expect_identical(adbc$args$options$backend, "adbc")
  expect_error(
    oauth_db_fabric_sql(auth, "server", app_name = "app;Encrypt=no"),
    "Quote ODBC values"
  )
  for (backend in c("odbc", "adbc")) {
    for (option in list(
      list(uri = "sqlserver://other-host"),
      list(TrustServerCertificate = "yes"),
      list(token = "another-user")
    )) {
      expect_error(
        do.call(
          oauth_db_fabric_sql,
          c(list(auth, "server", backend = backend), option)
        ),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
  }
})

test_that("Fabric ADBC renews fixed credentials without replaying reactive queries", {
  skip_if_not_installed("adbi")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("fabricQueryR", "1.0.1")
  tokens <- character()
  local_mocked_bindings(
    fabric_sql_connect = function(token, backend = "odbc", ...) {
      tokens <<- c(tokens, token("https://database.windows.net//.default"))
      if (backend == "adbc") {
        DBI::dbConnect(adbi::adbi(duckdb::duckdb_adbc()))
      } else {
        DBI::dbConnect(RSQLite::SQLite(), ":memory:")
      }
    },
    .package = "fabricQueryR"
  )

  for (backend in c("adbc", "odbc")) {
    tokens <- character()
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session, refresh_token = "fixture-refresh")
      con <- oauth_db_fabric_sql(
        auth$connection,
        server = "example.datawarehouse.fabric.microsoft.com",
        database = "Reporting",
        backend = backend,
        target = NULL
      )
      queried <- 0L
      rows <- shiny::reactive({
        connection <- con()
        queried <<- queried + 1L
        DBI::dbGetQuery(connection, "SELECT 42 AS answer")
      })
      expect_equal(rows()$answer, 42)
      first <- con()
      expect_identical(tokens, "fixture-A")
      auth$token(auth$make_token("renewed-A"))
      session$flushReact()
      expect_equal(rows()$answer, 42)
      expect_identical(queried, 1L)

      second <- con()
      if (backend == "adbc") {
        expect_false(DBI::dbIsValid(first))
        expect_false(identical(first, second))
        expect_identical(tokens, c("fixture-A", "renewed-A"))
        expect_identical(con(), second)
        auth$token(auth$make_token("expiring-A", lifetime = 30))
        renewed <- con()
        expect_false(DBI::dbIsValid(second))
        expect_true(DBI::dbIsValid(renewed))
        expect_identical(tail(tokens, 1L), "fixture-A-acquired")
      } else {
        expect_identical(second, first)
        expect_identical(tokens, "fixture-A")
      }
    })
  }
})
