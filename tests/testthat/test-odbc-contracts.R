test_that("ODBC adapters reject alternate spellings of owned identity and authentication settings", {
  skip_if_not_installed("odbc")
  skip_if_not_installed("brickster")
  connected <- 0L
  local_mocked_bindings(dbConnect = function(...) {
    connected <<- connected + 1L
    stop("Invalid options must not open a native connection")
  }, .package = "DBI")
  cases <- list(
    list(helper = oauth_db_azure_sql, args = list(server = "sql.example", database = "reports"),
      options = c("DRIVER", "SERVER", "Integrated.Security")),
    list(helper = oauth_db_snowflake, args = list(server = "account.example", role = "READER"),
      options = c("SERVER", "OAuth.Client.Secret", "Token.File.Path")),
    list(helper = oauth_db_redshift, args = list(server = "redshift.example", database = "reports"),
      options = c("Token.Type", "AuthProfile", "AccessKeyId", "SecretAccessKey", "SessionToken")),
    list(helper = oauth_db_databricks, args = list(host = "workspace.example", warehouse_id = "warehouse"),
      options = c("HTTP.PATH", "Auth.Args", "Client.Secret")))
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    for (case in cases) for (name in case$options) {
      args <- c(list(authorization = auth$connection), case$args,
        stats::setNames(list("sensitive-fixture-value"), name))
      failure <- tryCatch(do.call(case$helper, args), error = identity)
      expect_s3_class(failure, "shinyOAuthDB_invalid_configuration")
      if (inherits(failure, "condition")) {
        expect_false(grepl("sensitive-fixture-value", conditionMessage(failure), fixed = TRUE))
      }
    }
    expect_identical(auth$calls$acquire, 0L)
    expect_identical(connected, 0L)
  })
})

test_that("ODBC adapters validate port shapes and preserve supported port boundaries", {
  skip_if_not_installed("odbc")
  local_mocked_bindings(.odb_bind = capture_backend)
  common_invalid <- list(NULL, integer(), NA_real_, Inf, -1, 0, 65536,
    c(1234L, 5678L), 5439.5, TRUE, "not-a-port")
  for (port in common_invalid) {
    expect_error(oauth_db_redshift(NULL, "redshift.example", "reports", port = port),
      class = "shinyOAuthDB_invalid_configuration")
    expect_error(oauth_db_azure_sql(NULL, "sql.example", "reports", port = port),
      class = "shinyOAuthDB_invalid_configuration")
    expect_error(oauth_db_starrocks(NULL, "starrocks.example", "reports", "reader", "MySQL driver", port = port),
      class = "shinyOAuthDB_invalid_configuration")
  }
  expect_error(oauth_db_starrocks(NULL, "starrocks.example", "reports", "reader", "MySQL driver", port = "1234"),
    class = "shinyOAuthDB_invalid_configuration")
  for (port in c(1L, 65535L)) {
    expect_identical(oauth_db_redshift(NULL, "redshift.example", "reports", port = port)$args$port, port)
    expect_identical(oauth_db_azure_sql(NULL, "sql.example", "reports", port = port)$args$port, port)
    expect_identical(oauth_db_starrocks(NULL, "starrocks.example", "reports", "reader", "MySQL driver",
      port = port)$args$port, port)
  }
  expect_identical(oauth_db_redshift(NULL, "redshift.example", "reports", port = "5439")$args$port, 5439L)
})

test_that("StarRocks forwards result timezone settings without replacing JWT authentication", {
  skip_if_not_installed("odbc")
  captured <- NULL
  token_path <- NULL
  local_mocked_bindings(dbConnect = function(drv, ...) {
    captured <<- list(...)
    token_path <<- captured[["openid-token-file"]]
    expect_true(file.exists(token_path))
    expect_identical(readLines(token_path, warn = FALSE), "e30.e30.fixture")
    "native-connection"
  }, .package = "DBI")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    auth$token(auth$make_token("e30.e30.fixture"))
    con <- oauth_db_starrocks(auth$connection, "starrocks.example", "reports", "reader", "MySQL driver",
      timezone = "UTC", timezone_out = "Europe/Amsterdam", readtimeout = 30L)
    expect_identical(con(), "native-connection")
    expect_identical(captured$timezone, "UTC")
    expect_identical(captured$timezone_out, "Europe/Amsterdam")
    expect_identical(captured$readtimeout, 30L)
    expect_identical(captured$UID, "reader")
    expect_identical(captured$SSLMODE, "VERIFY_IDENTITY")
    expect_false(file.exists(token_path))
    expect_false(dir.exists(dirname(token_path)))
  })
})
