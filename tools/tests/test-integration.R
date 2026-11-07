source(file.path("..", "..", "integration", "contracts.R"), local = TRUE)

testthat::test_that("omitted, empty and malformed integration checks cannot pass", {
  expected <- c("certificate", "hostname")
  testthat::expect_true(integration_require_checks(
    list(certificate = TRUE, hostname = TRUE),
    expected,
    "TLS"
  ))
  for (value in list(
    list(),
    list(certificate = TRUE),
    list(certificate = TRUE, hostname = TRUE, extra = TRUE),
    list(TRUE, TRUE),
    list(certificate = TRUE, hostname = FALSE),
    list(certificate = TRUE, hostname = NA),
    list(certificate = TRUE, hostname = 1),
    stats::setNames(list(TRUE, TRUE), c("certificate", "certificate"))
  )) {
    testthat::expect_error(
      integration_require_checks(value, expected, "TLS"),
      "TLS"
    )
  }
  for (backend in c("postgrest", "trino", "starrocks", "minilake")) {
    names <- integration_check_names(backend, "data")
    testthat::expect_true(length(names) > 0L)
    testthat::expect_error(
      integration_require_checks(list(), names, backend),
      backend
    )
  }
})

testthat::test_that("each required browser scenario must execute passing assertions", {
  for (backend in c(
    "postgres",
    "postgrest",
    "trino",
    "starrocks",
    "minilake"
  )) {
    expected <- integration_scenarios(backend)
    counts <- data.frame(
      test = expected,
      passed = 1L,
      failed = 0L,
      error = FALSE,
      warning = 0L,
      skipped = FALSE
    )
    testthat::expect_true(integration_validate_results(counts, expected))
    testthat::expect_error(
      integration_validate_results(counts[FALSE, ], expected),
      "named scenarios"
    )
    testthat::expect_error(
      integration_validate_results(counts[-1L, ], expected),
      "named scenarios"
    )
    testthat::expect_error(
      integration_validate_results(rbind(counts, counts[1L, ]), expected),
      "named scenarios"
    )
    for (field in c("passed", "failed", "error", "warning", "skipped")) {
      bad <- counts
      bad[[field]][[1L]] <- if (field == "passed") 0L else 1L
      testthat::expect_error(
        integration_validate_results(bad, expected),
        "passing assertions"
      )
    }
  }
})
