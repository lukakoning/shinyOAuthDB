test_that("a native connector can use its own scopes argument", {
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    native_scopes <- structure(c("query", "metadata"), class = "native_scopes")
    con <- oauth_db_connect(auth$connection,
      connect = function(password, scopes) list(password = password, scopes = scopes),
      token_arg = "password", scopes = native_scopes, required_scopes = "read")
    expect_identical(con(), list(password = "fixture-A", scopes = native_scopes))
    auth$token(auth$make_token("denied", "write"))
    expect_error(con(), class = "shiny.silent.error")
  })
})

test_that("quoted ODBC values reach the native connector unchanged", {
  skip_if_not_installed("odbc")
  captured <- NULL
  local_mocked_bindings(dbConnect = function(drv, ...) {
    captured <<- list(...)
    "native"
  }, .package = "DBI")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    for (name in c("Sales;Archive", "Sales{Archive}", 'Sales "Archive";2026',
                   "Reader's;reports", " padded = name ")) {
      database <- odbc::quote_value(name)
      con <- oauth_db_azure_sql(auth$connection, "server", database,
        APP = database, target = NULL, required_scopes = "read")
      expect_identical(con(), "native")
      expect_identical(captured$database, database)
      expect_identical(captured$APP, database)
      expect_identical(captured$Encrypt, "yes")
      expect_identical(captured$TrustServerCertificate, "no")
      expect_identical(captured$attributes, list(azure_token = "fixture-A"))

      snow <- oauth_db_snowflake(auth$connection, "account", database,
        "PUBLIC", "WH", "READER", target = NULL, required_scopes = "read")
      expect_identical(snow(), "native")
      expect_identical(captured$database, database)
      expect_identical(captured$authenticator, "oauth")
      expect_identical(captured$token, "fixture-A")
    }
    con <- oauth_db_azure_sql(auth$connection, odbc::quote_value("server"), "db",
      port = 1443L, target = NULL, required_scopes = "read")
    con()
    expect_identical(as.character(captured$server), '"server,1443"')
  })
})

test_that("ODBC delimiters cannot escape the quoted value", {
  local_mocked_bindings(.odb_require = function(...) TRUE, .odb_bind = capture_backend)
  for (value in c('"Sales";UID=other;"x"', "'Sales';PWD=secret;'x'",
                  '"Sales";TrustServerCertificate=yes;"x"',
                  '"Sales;UID=other', "Sales;UID=other", "{Sales};UID=other",
                  '"Sales\nArchive"', "Sales\rArchive", "Sales\tArchive")) {
    expect_error(oauth_db_azure_sql(NULL, "server", value), "odbc::quote_value", fixed = TRUE)
    expect_error(oauth_db_snowflake(NULL, "account", value, "PUBLIC", "WH", "READER"),
      "odbc::quote_value", fixed = TRUE)
  }
  # SQL Server combines server and port into one ODBC value: a quoted port
  # must not introduce a delimiter in the middle of that value.
  expect_error(oauth_db_azure_sql(NULL, "server", "db", port = '"1433;UID=other"'), "port")
  expect_error(oauth_db_azure_sql(NULL, "server", "db", `APP=x;UID` = "other"), "option names")
  expect_error(oauth_db_snowflake(NULL, "account", "db", "PUBLIC", "WH", "READER",
    `APP=x;TOKEN_FILE_PATH` = "path"), "option names")
})
