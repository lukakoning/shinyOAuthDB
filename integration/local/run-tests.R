local({
  stopifnot(identical(Sys.getenv("OAUTHDB_LOCAL_INTEGRATION"), "1"))
  backend <- Sys.getenv("OAUTHDB_FIXTURE")
  stopifnot(backend %in% c("postgrest", "trino", "starrocks", "minilake"))
  repository <- normalizePath(".", mustWork = TRUE)
  library <- tempfile("oauthdb-local-library-")
  stage <- tempfile("oauthdb-local-source-")
  dir.create(library)
  dir.create(stage)
  on.exit(unlink(c(library, stage), recursive = TRUE), add = TRUE)
  files <- c("DESCRIPTION", "NAMESPACE", "LICENSE", "R", "man", "src", "configure", "cleanup")
  stopifnot(all(file.copy(file.path(repository, files), stage, recursive = TRUE)))
  .libPaths(c(library, .libPaths()))
  Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  for (source in c("/workspace/shinyOAuth", stage)) {
    installed <- processx::run(file.path(R.home("bin"), "R"),
      c("CMD", "INSTALL", "--preclean", "--no-byte-compile", paste0("--library=", library), source),
      echo = TRUE, error_on_status = FALSE)
    stopifnot(installed$status == 0L)
  }
  for (package in c("shinyOAuth", "shinyOAuthDB")) {
    stopifnot(identical(normalizePath(find.package(package)), normalizePath(file.path(library, package))))
  }
  source("integration/local/browser.R", local = FALSE)
  source("integration/local/dbplyr.R", local = FALSE)
  source(file.path("integration", paste0(backend, "-keycloak"), "backend.R"), local = FALSE)
  fixture_backend$prepare()
  deadline <- Sys.time() + 20
  repeat {
    ready <- tryCatch(httr2::req_perform(httr2::request("https://localhost:18447")), error = function(e) NULL)
    if (!is.null(ready) && httr2::resp_status(ready) == 200L) break
    if (Sys.time() > deadline) stop("TLS probe readiness failed.", call. = FALSE)
    Sys.sleep(0.1)
  }
  test_file <- if (is.null(fixture_backend$test_file)) "integration/local/test-browser.R" else fixture_backend$test_file
  results <- testthat::test_file(test_file, reporter = "summary")
  counts <- as.data.frame(results)
  source("integration/provenance.R", local = TRUE)
  jsonlite::write_json(list(backend = backend,
    provenance = integration_provenance(packages = c("shinyOAuth", "shinyOAuthDB", "DBI", "httr2", "dbplyr", "dplyr", "RTrino", "odbc", "brickster")),
    scenarios = counts[!vapply(counts, is.list, logical(1))],
    package_version = as.character(packageVersion("shinyOAuthDB")),
    shinyOAuth_version = as.character(packageVersion("shinyOAuth")),
    platform = fixture_backend$version(),
    passed = sum(counts$passed), failed = sum(counts$failed), errors = sum(counts$error),
    warnings = sum(counts$warning), skipped = sum(counts$skipped)),
    "/results/results.json", auto_unbox = TRUE, pretty = TRUE)
  integration_validate_results(counts, integration_scenarios(backend))
})
