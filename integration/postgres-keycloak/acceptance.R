local({
  source("integration/contracts.R", local = TRUE)
  fixture <- file.path(getwd(), "integration", "postgres-keycloak")
  withCallingHandlers(
    sys.source(
      file.path(fixture, "native", "tests", "regression.R"),
      envir = new.env(parent = globalenv())
    ),
    warning = function(w) {
      stop("The native regression emitted a warning.", call. = FALSE)
    }
  )

  browser_results <- testthat::test_dir(
    fixture,
    reporter = "summary",
    stop_on_failure = FALSE,
    load_helpers = TRUE
  )
  counts <- as.data.frame(browser_results)
  source("integration/provenance.R", local = TRUE)
  jsonlite::write_json(
    list(
      provenance = integration_provenance(
        packages = c(
          "shinyOAuth",
          "shinyOAuthDB",
          "RPostgres",
          "dbplyr",
          "dplyr"
        )
      ),
      scenarios = counts[!vapply(counts, is.list, logical(1))],
      package_version = as.character(utils::packageVersion("shinyOAuthDB")),
      runtime = getFromNamespace(".odb_postgres_runtime", "shinyOAuthDB")(),
      passed = sum(counts$passed),
      failed = sum(counts$failed),
      errors = sum(counts$error),
      warnings = sum(counts$warning),
      skipped = sum(counts$skipped)
    ),
    "/results/results.json",
    auto_unbox = TRUE,
    pretty = TRUE
  )
  message(
    "PostgreSQL/Keycloak integration: ",
    sum(counts$passed),
    " passing assertions; ",
    sum(counts$failed),
    " failures; ",
    sum(counts$error),
    " errors; ",
    sum(counts$warning),
    " warnings; ",
    sum(counts$skipped),
    " skips."
  )

  integration_validate_results(counts, integration_scenarios("postgres"))
})
