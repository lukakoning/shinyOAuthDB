stopifnot(identical(Sys.getenv("OAUTHDB_CLICKHOUSE_HTTP_TEST"), "1"))
local({
  library <- tempfile("clickhouse-http-library-")
  stage <- tempfile("clickhouse-http-source-")
  dir.create(library)
  dir.create(stage)
  on.exit(unlink(c(library, stage), recursive = TRUE), add = TRUE)
  files <- c("DESCRIPTION", "NAMESPACE", "LICENSE", "R", "man", "src", "configure", "cleanup")
  stopifnot(all(file.copy(files, stage, recursive = TRUE)))
  .libPaths(c(library, .libPaths()))
  Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  for (path in c("/workspace/shinyOAuth", stage)) {
    installed <- processx::run(file.path(R.home("bin"), "R"),
      c("CMD", "INSTALL", "--preclean", "--no-byte-compile", paste0("--library=", library), path),
      echo = TRUE, error_on_status = FALSE)
    stopifnot(installed$status == 0L)
  }
  source("integration/contracts.R", local = TRUE)
  results <- testthat::test_file("integration/clickhouse-http/test-http.R", reporter = "summary")
  counts <- as.data.frame(results)
  source("integration/provenance.R", local = TRUE)
  provenance <- integration_provenance()
  jsonlite::write_json(provenance, "/results/provenance.json", auto_unbox = TRUE, pretty = TRUE)
  saveRDS(results, "/results/test-results.rds")
  utils::write.csv(counts[!vapply(counts, is.list, logical(1))], "/results/test-results.csv", row.names = FALSE)
  integration_validate_results(counts, c("ClickHouse public HTTPS queries round-trip native values and enforce local user grants",
    "ClickHouse public writes execute once after dropped or delayed responses"))
  jsonlite::write_json(list(scope = "Local engine/HTTP compatibility with synthetic gateway identities; not Cloud JWT",
    server = "ClickHouse 26.1.2.11", scenarios = counts$test, passed = sum(counts$passed)),
    "/results/results.json", auto_unbox = TRUE, pretty = TRUE)
})
