arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) .libPaths(c(arguments, .libPaths()))
Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
source("tools/validation.R")
validation_check_dependencies(c(validation_dependencies(), covr = "3.6.0"))
output <- ".validation"
dir.create(output, showWarnings = FALSE)
coverage <- covr::package_coverage(type = "tests", quiet = FALSE)
saveRDS(coverage, file.path(output, "coverage.rds"))
lines <- covr::tally_coverage(coverage)
utils::write.csv(lines, file.path(output, "coverage-lines.csv"), row.names = FALSE)
summarize <- function(pattern) {
  selected <- lines[grepl(pattern, lines$filename), , drop = FALSE]
  # Multiple expressions on one source line count as one line.
  hits <- aggregate(selected$value, selected[c("filename", "line")], sum)
  list(covered = sum(hits$x > 0), total = nrow(hits), percent = 100 * mean(hits$x > 0))
}
summary <- list(revision = Sys.getenv("GITHUB_SHA", unset = NA_character_),
  R = as.character(getRversion()), platform = R.version$platform,
  R_lines = summarize("^R/"), C_lines = summarize("^src/"),
  native_postgres = "This package-check lane does not validate the Linux libpq OAuth hook; use its Docker integration.")
jsonlite::write_json(summary, file.path(output, "coverage-summary.json"), auto_unbox = TRUE, pretty = TRUE)
print(summary)
