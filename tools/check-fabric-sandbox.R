# Read-only cloud check using the same queries as playground/fabric.
# Start the existing sandbox workflow first. Rscript reads the usual .Renviron.
# Optional arguments prepend isolated dependency libraries.
libraries <- commandArgs(trailingOnly = TRUE)
if (length(libraries)) .libPaths(c(libraries, .libPaths()))
source("playground/fabric/queries.R")
token <- fabric_demo_shared_token()
sandbox <- fabric_demo_discover(token,
  Sys.getenv("FABRIC_SHINY_WORKSPACE", "fabricqueryr-shiny-dhrkoning"))
results <- lapply(unname(fabric_demo_sources), function(source) {
  message("Reading ", source, "...")
  tryCatch({
    data <- fabric_demo_read(source, sandbox, token, shared = TRUE)
    if (source != "discovery") {
      expected <- if (source %in% c("dax", "dax_arrow")) 2L else 3L
      stopifnot(nrow(data) == expected)
    }
    data.frame(source = source, rows = nrow(data), status = "pass", detail = "")
  }, error = function(e) {
    data.frame(source = source, rows = NA_integer_, status = "fail", detail = conditionMessage(e))
  })
})
results <- do.call(rbind, results)
print(results[c("source", "rows", "status")], row.names = FALSE)
for (i in which(results$status != "pass")) {
  message(results$source[[i]], ": ", strsplit(results$detail[[i]], "\n", fixed = TRUE)[[1L]][[1L]])
}
dir.create("tests/integration/results", recursive = TRUE, showWarnings = FALSE)
write.csv(results, "tests/integration/results/fabric-sandbox.csv", row.names = FALSE)
if (any(results$status != "pass")) quit(status = 1L)
