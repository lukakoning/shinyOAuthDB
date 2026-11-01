test_that("Redshift supplies explicit tokens through the plain ODBC driver", {
  skip_if_not_installed("odbc")
  native <- list()
  local_mocked_bindings(dbConnect = function(drv, ...) {
    native <<- c(list(drv = drv), list(...))
    structure(list(), class = "redshift_fixture")
  }, .package = "DBI")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    con <- oauth_db_redshift(auth$connection, "cluster.example", "reporting",
      driver = "AWS Redshift driver", CaFile = "ca.pem", LoginTimeout = 20L)
    con()
    expect_s4_class(native$drv, "OdbcDriver")
    expect_false(inherits(native$drv, "RedshiftOdbcDriver"))
    expect_identical(native$plugin_name, "IdpTokenAuthPlugin")
    expect_identical(native$token, "fixture-A")
    expect_identical(native$token_type, "EXT_JWT")
    expect_identical(native$SSLMode, "verify-full")
    expect_identical(native$ssl_insecure, 0L)
    expect_identical(native$server, "cluster.example")
    expect_identical(native$database, "reporting")
    expect_identical(native$port, 5439L)
    expect_identical(native$CaFile, "ca.pem")
    expect_identical(native$LoginTimeout, 20L)
  })
})

test_that("Redshift reuses SQL sessions and retires connections on account changes", {
  skip_if_not_installed("odbc")
  skip_if_not_installed("RSQLite")
  opened <- list()
  local_mocked_bindings(.odb_backend_redshift = function(token, ...) {
    con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    attr(con, "opening_token") <- token()
    opened[[length(opened) + 1L]] <<- con
    con
  })
  retained <- NULL
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session, id = "A")
    b <- odb_test_authorization(session, id = "B")
    selected <- shiny::reactiveVal(NULL)
    con <- oauth_db_redshift(selected, "cluster.example", "reporting")
    expect_error(con(), class = "shiny.silent.error")
    expect_length(opened, 0L)
    selected(a$connection)
    first <- con()
    expect_identical(attr(first, "opening_token"), "fixture-A")
    a$token(a$make_token("rotated-A"))
    expect_identical(con(), first)
    selected(b$connection)
    second <- con()
    expect_false(DBI::dbIsValid(first))
    expect_identical(attr(second, "opening_token"), "fixture-B")
    b$status("insufficient_scope")
    expect_error(con(), class = "shiny.silent.error")
    expect_false(DBI::dbIsValid(second))
    b$status("active")
    third <- con()
    selected(NULL)
    expect_error(con(), class = "shiny.silent.error")
    expect_false(DBI::dbIsValid(third))
    selected(a$connection)
    retained <<- con()
  })
  expect_false(DBI::dbIsValid(retained))
})

test_that("Redshift accepts configured targets and Identity Center access tokens", {
  skip_if_not_installed("odbc")
  saved <- NULL
  local_mocked_bindings(.odb_backend_redshift = function(token, ...) {
    saved <<- c(list(token = token()), list(...))
    structure(list(), class = "redshift_fixture")
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = "read", target = "redshift")
    con <- oauth_db_redshift(auth$connection, "cluster.example", "reporting",
      target = "redshift", required_scopes = auth$scopes, token_type = "ACCESS_TOKEN", port = 5440)
    con()
    expect_identical(saved$token, "fixture-A")
    expect_identical(saved$token_type, "ACCESS_TOKEN")
    expect_identical(saved$port, 5440L)
  })
})

test_that("Redshift rejects credential, identity, and TLS overrides", {
  skip_if_not_installed("odbc")
  blocked <- c("DSN", "FileDSN", "Host", "PortNumber", "Plugin_Name", "token", "tokenType",
    "AccessKeyID", "secretAccessKey", "SessionToken", "IAM", "Profile", "AuthProfile",
    "InstanceProfile", "uid", "dbUser", "Password", "CLIENT_SECRET", "Web_Identity_Token",
    "SSLMode", "ssl.insecure", "TrustServerCertificate", ".connection_string")
  for (name in blocked) {
    args <- c(list(authorization = function() NULL, server = "cluster.example", database = "reporting"),
      stats::setNames(list("sensitive-fixture-value"), name))
    error <- tryCatch(do.call(oauth_db_redshift, args), error = identity)
    expect_s3_class(error, "shinyOAuthDB_invalid_configuration")
    expect_false(grepl("sensitive-fixture-value", conditionMessage(error), fixed = TRUE))
  }
  expect_error(oauth_db_redshift(function() NULL, "cluster;pwd=bad", "reporting"), "Quote ODBC")
  expect_error(oauth_db_redshift(function() NULL, "cluster", "reporting", port = "5439;UID=bad"), "port")
  expect_error(oauth_db_redshift(function() NULL, "cluster", "reporting", token_type = "SUBJECT_TOKEN"), "arg")
  expect_error(oauth_db_redshift(function() NULL, "cluster", "reporting", 1), "nonempty")
})
