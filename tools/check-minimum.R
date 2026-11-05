# The core suite deliberately excludes optional platform SDKs. Their newer
# releases can require newer core dependencies than our own declared floor.
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) .libPaths(c(arguments, .libPaths()))
Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
  SHINYOAUTHDB_POSTGRES_OAUTH = "disabled")
source("tools/validation.R")
floor <- c(DBI = "1.2.0", httr2 = "1.2.0", curl = "6.4.0", shiny = "1.8.1")
expected_testthat <- Sys.getenv("OAUTHDB_EXPECTED_TESTTHAT", unset = "3.2.0")
if (expected_testthat != "release") floor <- c(floor, testthat = expected_testthat)
imports <- validation_dependencies()[names(validation_dependencies()) %in%
  trimws(sub("[[:space:]]*\\(.*$", "", strsplit(read.dcf("DESCRIPTION")[1L, "Imports"], ",")[[1L]]))]
packages <- c(imports, floor, testthat = "3.2.0", RSQLite = "0", pkgload = "0", jsonlite = "0", S7 = "0.2.0")
packages <- packages[!duplicated(names(packages))]
validation_check_dependencies(packages)
actual <- vapply(names(floor), function(x) as.character(utils::packageVersion(x)), "")
if (!identical(actual, floor)) stop("The minimum lane must use its exact dependency floors.", call. = FALSE)
expected_r <- Sys.getenv("OAUTHDB_EXPECTED_R")
if (nzchar(expected_r) && !identical(as.character(getRversion()), expected_r)) {
  stop("The minimum lane is using the wrong R runtime.", call. = FALSE)
}
filter <- paste0("^(", paste(c("auth", "authorization-protocol", "core", "http", "http-contracts", "http-diagnostics", "lifecycle", "lifecycle-cleanup",
  "operation-scopes", "credential-recovery", "postgrest", "bigquery", "bigquery-responses", "bigquery-contracts", "bigquery-transport", "bigquery-types", "clickhouse", "query-button",
  "multiple-connections", "two-authorizations"), collapse = "|"), ")$")
results <- testthat::test_local(".", filter = filter, reporter = "summary",
  stop_on_failure = FALSE, stop_on_warning = FALSE)
validation_check_results(as.data.frame(results), ".validation/minimum", packages = packages)
