test_that("native ODBC connection errors retain diagnostics without bearer tokens", {
  skip_if_not_installed("odbc")
  token <- paste(
    "synthetic",
    paste(format(openssl::rand_bytes(24)), collapse = ""),
    "signature",
    sep = "."
  )
  driver <- paste0("shinyOAuthDB_missing_driver_", Sys.getpid())
  reference <- tryCatch(
    DBI::dbConnect(odbc::odbc(), driver = driver),
    error = identity
  )
  expect_s3_class(reference, "error")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    auth$token(auth$make_token(token))
    factories <- list(
      function() {
        oauth_db_singlestore(
          auth$connection,
          "sql.example",
          ssl_ca = "ca.pem",
          driver = driver
        )
      },
      function() {
        oauth_db_hana(auth$connection, "hana.example", driver = driver)
      },
      function() {
        oauth_db_snowflake(
          auth$connection,
          "account.example",
          role = "reader",
          required_scopes = "read",
          driver = driver
        )
      },
      function() {
        oauth_db_redshift(
          auth$connection,
          "redshift.example",
          "reporting",
          driver = driver
        )
      }
    )
    for (factory in factories) {
      con <- factory()
      error <- tryCatch(con(), error = identity)
      expect_identical(class(error), class(reference))
      expect_identical(conditionMessage(error), conditionMessage(reference))
      expect_false(any(grepl(token, capture.output(dput(error)), fixed = TRUE)))
      expect_false(grepl(
        token,
        rawToChar(serialize(error, NULL, ascii = TRUE)),
        fixed = TRUE
      ))
    }
  })
})
