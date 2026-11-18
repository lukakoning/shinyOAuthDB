backend_dependency_cases <- list(
  list(
    package = "adbi",
    older = "0.1.1",
    minimum = "0.1.2",
    make = function(auth) oauth_db_dremio(auth, "dremio.example.org")
  ),
  list(
    package = "adbcdrivermanager",
    older = "0.24.0",
    minimum = "0.25.0",
    make = function(auth) oauth_db_dremio(auth, "dremio.example.org")
  ),
  list(
    package = "duckdb",
    older = "1.5.2",
    minimum = "1.5.3",
    make = function(auth) oauth_db_duckdb(auth, "duckdb.example.org")
  ),
  list(
    package = "brickster",
    older = "0.2.13",
    minimum = "0.2.14",
    make = function(auth) oauth_db_databricks_api(auth, "workspace.example")
  ),
  list(
    package = "fabricQueryR",
    older = "1.0.0",
    minimum = "1.0.1",
    make = function(auth) oauth_db_fabric_api(auth)
  ),
  list(
    package = "RTrino",
    older = "0.0.9",
    minimum = "0.1.0",
    make = function(auth) {
      oauth_db_trino(
        auth,
        "https://trino.example",
        "lake",
        "reports",
        user = "reader"
      )
    }
  )
)
for (case in backend_dependency_cases) {
  local({
    spec <- case
    test_that(
      paste(spec$package, "minimum is checked before acquiring credentials"),
      {
        skip_if_not_installed(spec$package, spec$minimum)
        if (spec$package %in% c("adbi", "adbcdrivermanager")) {
          skip_if_not_installed("adbi", "0.1.2")
          skip_if_not_installed("adbcdrivermanager", "0.25.0")
        }
        original <- .odb_package_version
        reported <- spec$older
        local_mocked_bindings(
          .odb_package_version = function(package) {
            if (identical(package, spec$package)) {
              package_version(reported)
            } else {
              original(package)
            }
          }
        )
        odb_test_domain(function(session) {
          auth <- odb_test_authorization(session)
          error <- tryCatch(spec$make(auth$connection), error = identity)
          expect_s3_class(error, "shinyOAuthDB_missing_dependency")
          expect_match(conditionMessage(error), spec$package, fixed = TRUE)
          expect_match(conditionMessage(error), spec$minimum, fixed = TRUE)
          expect_identical(auth$calls$acquire, 0L)
          reported <<- spec$minimum
          expect_false(inherits(
            tryCatch(spec$make(auth$connection), error = identity),
            "error"
          ))
          expect_identical(auth$calls$acquire, 0L)
        })
      }
    )
  })
}
