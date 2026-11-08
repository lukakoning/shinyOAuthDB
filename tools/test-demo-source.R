arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) {
  .libPaths(c(arguments, .libPaths()))
}
testthat::test_file("tools/tests/test-demo-source.R", stop_on_failure = TRUE)
