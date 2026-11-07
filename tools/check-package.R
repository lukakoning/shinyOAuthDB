# Repository validation without installing into the user's normal library.
# Run from the repository root: Rscript --vanilla tools/check-package.R
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) {
  .libPaths(c(arguments, .libPaths()))
}
Sys.setenv(LC_ALL = "C", LANG = "C", LANGUAGE = "en")
needed <- c("pkgbuild", "pkgload", "testthat", "rcmdcheck", "jsonlite")
missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  stop(
    "Install validation dependencies: ",
    paste(missing, collapse = ", "),
    call. = FALSE
  )
}

root <- normalizePath(".", winslash = "/", mustWork = TRUE)
if (!file.exists(file.path(root, "DESCRIPTION"))) {
  stop("Run this from the package repository root.", call. = FALSE)
}
source(file.path(root, "tools", "validation.R"))
validation_check_dependencies()
output <- file.path(root, ".validation")
dir.create(output, showWarnings = FALSE)

validation_library <- tempfile("shinyOAuthDB-validation-library-")
dir.create(validation_library)
.libPaths(c(validation_library, .libPaths()))
Sys.setenv(
  R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
  R_LIBS_USER = paste(.libPaths(), collapse = .Platform$path.sep),
  `_R_CHECK_FORCE_SUGGESTS_` = "false"
)
pkgbuild::rcmd_build_tools(
  "INSTALL",
  c("--no-byte-compile", paste0("--library=", validation_library), root),
  env = c(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
)
results <- testthat::test_local(
  root,
  reporter = "summary",
  stop_on_failure = FALSE,
  stop_on_warning = FALSE
)
counts <- as.data.frame(results)
validation_check_results(counts, output)
check <- rcmdcheck::rcmdcheck(
  root,
  args = "--no-manual",
  error_on = "never"
)
jsonlite::write_json(
  list(errors = check$errors, warnings = check$warnings, notes = check$notes),
  file.path(output, "package-check.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)
cat(
  "\nR CMD check:",
  length(check$errors),
  "errors,",
  length(check$warnings),
  "warnings,",
  length(check$notes),
  "notes\n"
)

if (length(check$errors) || length(check$warnings) || length(check$notes)) {
  quit(status = 1L)
}
