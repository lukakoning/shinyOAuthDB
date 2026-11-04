validation_dependencies <- function(path = "DESCRIPTION") {
  description <- read.dcf(path)
  fields <- intersect(c("Imports", "Suggests"), colnames(description))
  declarations <- trimws(unlist(strsplit(paste(description[1L, fields], collapse = ","), ",")))
  packages <- sub("[[:space:]]*\\(.*$", "", declarations)
  minimum <- ifelse(grepl("\\(", declarations),
    sub("^.*\\(>= *([^ )]+)\\)$", "\\1", declarations), "0")
  if (any(grepl("[()]", minimum))) stop("Unsupported dependency version constraint.", call. = FALSE)
  stats::setNames(minimum, packages)
}

validation_check_dependencies <- function(packages = validation_dependencies()) {
  missing <- vapply(names(packages), function(package) {
    !requireNamespace(package, quietly = TRUE) ||
      utils::compareVersion(as.character(utils::packageVersion(package)), packages[[package]]) < 0L
  }, logical(1))
  if (any(missing)) {
    stop("Full validation requires installed dependencies at their declared minimum versions: ",
      paste(paste0(names(packages)[missing], " (>= ", packages[missing], ")"), collapse = ", "), call. = FALSE)
  }
  invisible(TRUE)
}

validation_check_results <- function(counts, output) {
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  details <- counts[!vapply(counts, is.list, logical(1))]
  utils::write.csv(details, file.path(output, "test-results.csv"), row.names = FALSE)
  summary <- list(revision = Sys.getenv("GITHUB_SHA", unset = NA_character_),
    R = as.character(getRversion()), platform = R.version$platform,
    scenarios = nrow(counts), passed = sum(counts$passed), failed = sum(counts$failed),
    errors = sum(counts$error), warnings = sum(counts$warning), skipped = sum(counts$skipped))
  jsonlite::write_json(summary, file.path(output, "test-summary.json"), auto_unbox = TRUE, pretty = TRUE)
  versions <- vapply(names(validation_dependencies()), function(package)
    as.character(utils::packageVersion(package)), "")
  jsonlite::write_json(as.list(versions), file.path(output, "dependency-versions.json"),
    auto_unbox = TRUE, pretty = TRUE)
  cat("\nPassing assertions:", summary$passed, "; skipped scenarios:", summary$skipped, "\n")
  if (!nrow(counts) || !summary$passed || anyNA(unlist(summary[c("passed", "failed", "errors", "warnings", "skipped")])) ||
      any(counts$failed > 0L | counts$error | counts$warning > 0L | counts$skipped)) {
    stop("Full source tests require passing assertions and zero failures, errors, warnings or skips.", call. = FALSE)
  }
  invisible(summary)
}
