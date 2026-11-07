# Test one real backend SDK at its declared minimum, with the full source suite.
arguments <- commandArgs(trailingOnly = TRUE)
backends <- c("brickster", "fabricQueryR", "RTrino", "odbc")
if (!length(arguments) || !arguments[[1L]] %in% backends) {
  stop(
    "Usage: Rscript tools/check-backend-minimum.R <brickster|fabricQueryR|RTrino|odbc> [library ...]",
    call. = FALSE
  )
}
backend <- arguments[[1L]]
if (length(arguments) > 1L) {
  .libPaths(c(arguments[-1L], .libPaths()))
}
Sys.setenv(
  LC_ALL = "C",
  LANG = "C",
  LANGUAGE = "en",
  R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
  R_LIBS_USER = paste(.libPaths(), collapse = .Platform$path.sep),
  SHINYOAUTHDB_POSTGRES_OAUTH = "disabled"
)
source("tools/validation.R")
dependencies <- validation_dependencies()
validation_check_exact_dependencies(dependencies[backend])
validation_check_dependencies(dependencies)
cat(
  "Testing",
  backend,
  "at its declared minimum",
  dependencies[[backend]],
  "\n"
)
results <- testthat::test_local(
  ".",
  reporter = "summary",
  stop_on_failure = FALSE,
  stop_on_warning = FALSE
)
validation_check_results(
  as.data.frame(results),
  file.path(".validation", "minimum-backends", backend)
)
