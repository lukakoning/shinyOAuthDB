local({
  library <- tempfile("cratedb-library-")
  stage <- tempfile("cratedb-source-")
  dir.create(library)
  dir.create(stage)
  on.exit(unlink(c(library, stage), recursive = TRUE), add = TRUE)
  files <- c(
    "DESCRIPTION",
    "NAMESPACE",
    "LICENSE",
    "R",
    "man",
    "src",
    "configure",
    "cleanup"
  )
  stopifnot(all(file.copy(files, stage, recursive = TRUE)))
  .libPaths(c(library, .libPaths()))
  Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  for (path in c("/workspace/shinyOAuth", stage)) {
    installed <- processx::run(
      file.path(R.home("bin"), "R"),
      c(
        "CMD",
        "INSTALL",
        "--preclean",
        "--no-byte-compile",
        paste0("--library=", library),
        path
      ),
      echo = TRUE,
      error_on_status = FALSE
    )
    stopifnot(installed$status == 0L)
  }
  results <- testthat::test_file(
    "integration/cratedb-oauth/test-api.R",
    reporter = "summary"
  )
  source("integration/contracts.R", local = TRUE)
  integration_validate_results(
    as.data.frame(results),
    "CrateDB authenticates real visitor JWTs and enforces user privileges"
  )
  counts <- as.data.frame(results)
  jsonlite::write_json(
    list(
      server = "CrateDB 6.4.3",
      scenarios = counts$test,
      passed = sum(counts$passed),
      failed = sum(counts$failed),
      warnings = sum(counts$warning)
    ),
    "/out/results.json",
    auto_unbox = TRUE,
    pretty = TRUE
  )
})
