source(file.path("..", "validation.R"), local = TRUE)

testthat::test_that("full validation refuses missing and outdated dependencies", {
  testthat::expect_error(validation_check_dependencies(c(oauthdb_absent_backend = "1.0.0")),
    "oauthdb_absent_backend")
  testthat::expect_error(validation_check_dependencies(c(stats = "9999.0.0")), "stats")
  testthat::expect_true(validation_check_dependencies(c(stats = "0")))
})

testthat::test_that("dependency requirements include optional backends and their minimum versions", {
  path <- tempfile()
  on.exit(unlink(path), add = TRUE)
  writeLines(c("Package: fixture", "Imports: DBI (>= 1.2.0)",
    "Suggests: odbc (>= 1.4.2),", "    RSQLite"), path)
  testthat::expect_identical(validation_dependencies(path), c(DBI = "1.2.0", odbc = "1.4.2", RSQLite = "0"))
})

testthat::test_that("exact compatibility validation rejects silently upgraded SDKs", {
  actual <- c(stats = as.character(utils::packageVersion("stats")))
  testthat::expect_identical(validation_check_exact_dependencies(actual), actual)
  testthat::expect_error(validation_check_exact_dependencies(c(stats = "0")), "exact dependency versions")
  testthat::expect_error(validation_check_exact_dependencies(c(stats = "9999.0.0")), "declared minimum")
  testthat::expect_error(validation_check_exact_dependencies(c(oauthdb_absent_backend = "1.0.0")),
    "oauthdb_absent_backend")
})

testthat::test_that("skips, warnings, failures and empty runs cannot pass full validation", {
  # Keep metadata lookup independent of the caller's working directory.
  validation_dependencies <- function(...) c(stats = "0")
  environment(validation_check_results) <- environment()
  output <- tempfile()
  on.exit(unlink(output, recursive = TRUE), add = TRUE)
  passing <- data.frame(test = "fixture", passed = 1L, failed = 0L,
    error = FALSE, warning = 0L, skipped = FALSE)
  passing$result <- I(list(list(list(message = "expectation details"))))
  testthat::expect_identical(validation_check_results(passing, output)$passed, 1L)
  for (field in c("failed", "error", "warning", "skipped")) {
    counts <- passing
    counts[[field]] <- 1L
    testthat::expect_error(validation_check_results(counts, output), "zero failures")
    report <- jsonlite::read_json(file.path(output, "test-summary.json"))
    name <- switch(field, error = "errors", warning = "warnings", field)
    testthat::expect_equal(report[[name]], 1L)
  }
  testthat::expect_error(validation_check_results(passing[FALSE, ], output), "passing assertions")
  testthat::expect_true(file.exists(file.path(output, "test-results.csv")))
})
