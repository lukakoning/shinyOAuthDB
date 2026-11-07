arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) {
  .libPaths(c(arguments, .libPaths()))
}
Sys.setenv(
  R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
  LC_ALL = "C"
)
testthat::test_file(
  "tools/tests/test-live.R",
  reporter = "summary",
  stop_on_failure = TRUE
)
