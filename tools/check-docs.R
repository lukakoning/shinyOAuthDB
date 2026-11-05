# Read-only repository documentation check: Rscript tools/check-docs.R
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) .libPaths(c(arguments, .libPaths()))
source("tools/documentation.R")
result <- documentation_check(documentation_paths())
if (length(result$failures)) stop(paste(result$failures, collapse = "\n"), call. = FALSE)
cat(result$blocks, "R documentation blocks parsed;", result$links,
  "local links and", result$anchors, "section anchors resolve.\n")
