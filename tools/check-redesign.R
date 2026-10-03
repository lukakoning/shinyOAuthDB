# Focused development checks; full release validation is tools/check-package.R.
mode <- commandArgs(trailingOnly = TRUE)
if (!length(mode)) mode <- "all"
if (length(mode) > 1L) {
  .libPaths(c(mode[[2L]], .libPaths()))
  Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
}
if (mode[[1L]] == "document") {
  roxygen2::roxygenise(".")
} else {
  filter <- if (mode[[1L]] == "all") NULL else mode[[1L]]
  testthat::test_local(".", filter = filter, reporter = "summary", stop_on_failure = TRUE)
}
