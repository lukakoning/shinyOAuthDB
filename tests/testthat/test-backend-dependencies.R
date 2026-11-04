test_that("public helpers reject outdated SDKs before acquiring credentials", {
  cases <- list(
    list(package = "brickster", older = "0.2.13", minimum = "0.2.14",
      make = function(auth) oauth_db_databricks_api(auth, "workspace.example")),
    list(package = "fabricQueryR", older = "1.0.0", minimum = "1.0.1",
      make = function(auth) oauth_db_fabric_api(auth)),
    list(package = "RTrino", older = "0.0.9", minimum = "0.1.0",
      make = function(auth) oauth_db_trino(auth, "https://trino.example", "lake", "reports", user = "reader")))
  for (case in cases) local({
    skip_if_not_installed(case$package, case$minimum)
    original <- utils::packageVersion
    reported <- case$older
    local_mocked_bindings(packageVersion = function(package) {
      if (identical(package, case$package)) package_version(reported) else original(package)
    }, .package = "utils")
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session)
      error <- tryCatch(case$make(auth$connection), error = identity)
      expect_s3_class(error, "shinyOAuthDB_missing_dependency")
      expect_match(conditionMessage(error), case$package, fixed = TRUE)
      expect_match(conditionMessage(error), case$minimum, fixed = TRUE)
      expect_identical(auth$calls$acquire, 0L)
      reported <<- case$minimum
      expect_false(inherits(tryCatch(case$make(auth$connection), error = identity), "error"))
      expect_identical(auth$calls$acquire, 0L)
    })
  })
})
