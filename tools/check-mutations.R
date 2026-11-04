# A small set of security/lifecycle mutations, always in disposable copies.
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) .libPaths(c(arguments, .libPaths()))
Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
  SHINYOAUTHDB_POSTGRES_OAUTH = "disabled")
source("tools/validation.R")
validation_check_dependencies(c(validation_dependencies(), callr = "3.7.0"))
root <- normalizePath(".", winslash = "/", mustWork = TRUE)
output <- file.path(root, ".validation", "mutations")
dir.create(output, recursive = TRUE, showWarnings = FALSE)
mutations <- list(
  list(id = "retired-provider", file = "R/session.R", filter = "lifecycle-cleanup",
    before = "!identical(epoch, captured)", after = "FALSE",
    test = "cleanup errors cannot revive a retired object or provider"),
  list(id = "tls-verification", file = "R/backend__trino.R", filter = "trino$",
    before = "RTrino::trino_ssl(verify = TRUE", after = "RTrino::trino_ssl(verify = FALSE",
    test = "Trino uses current user tokens for connection checks and result pages"),
  list(id = "pagination-origin", file = "R/backend__trino.R", filter = "trino$",
    before = '.odb_abort("Trino requests must remain within the configured HTTPS origin.", "invalid_audience")',
    after = "invisible(NULL)",
    test = "Trino rejects pagination outside its HTTPS origin before sending credentials"),
  list(id = "mutation-replay", file = "R/backend__postgrest.R", filter = "postgrest$",
    before = 'retry_401 = method %in% c("GET", "HEAD")', after = "retry_401 = TRUE",
    test = "PostgREST RPC and native writes preserve arguments and never retry mutations")
)

run_copy <- function(mutation = NULL, filter) {
  parent <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
  copy <- tempfile("oauthdb-mutation-", tmpdir = parent)
  dir.create(copy)
  # Never remove a user checkout, even if future path construction changes.
  stopifnot(identical(dirname(normalizePath(copy, winslash = "/")), parent))
  on.exit(unlink(copy, recursive = TRUE), add = TRUE)
  entries <- c("DESCRIPTION", "NAMESPACE", "LICENSE", "R", "man", "src",
    "configure", "cleanup", "tests")
  stopifnot(all(file.copy(file.path(root, entries), copy, recursive = TRUE)))
  # Build outputs in the working tree are never inputs to a mutation test.
  artifacts <- list.files(file.path(copy, "src"), pattern = "\\.(o|so|dll|gcda|gcno)$", full.names = TRUE)
  unlink(artifacts)
  if (!is.null(mutation)) {
    file <- file.path(copy, mutation$file)
    code <- paste(readLines(file, warn = FALSE), collapse = "\n")
    positions <- gregexpr(mutation$before, code, fixed = TRUE)[[1L]]
    if (identical(positions[[1L]], -1L) || length(positions) != 1L) {
      stop("Mutation anchor must match exactly once: ", mutation$id, call. = FALSE)
    }
    code <- sub(mutation$before, mutation$after, code, fixed = TRUE)
    parse(text = code) # Invalid syntax is an infrastructure error, never a kill.
    writeLines(code, file, useBytes = TRUE)
  }
  callr::r(function(path, filter) {
    results <- testthat::test_local(path, filter = filter, reporter = "silent",
      stop_on_failure = FALSE, stop_on_warning = FALSE)
    counts <- as.data.frame(results)
    counts[!vapply(counts, is.list, logical(1))]
  }, args = list(copy, filter), libpath = .libPaths(), timeout = 180)
}

baseline <- run_copy(filter = "^(lifecycle-cleanup|trino|postgrest)$")
if (!nrow(baseline) || !sum(baseline$passed) ||
    any(baseline$failed > 0 | baseline$error | baseline$warning > 0 | baseline$skipped)) {
  stop("Mutation baseline must pass without warnings or skips.", call. = FALSE)
}
report <- list()
for (mutation in mutations) {
  counts <- run_copy(mutation, mutation$filter)
  named <- counts[counts$test == mutation$test, , drop = FALSE]
  conclusive <- nrow(counts) > 0L && nrow(named) == 1L &&
    !any(counts$error | counts$skipped)
  killed <- conclusive && named$failed[[1L]] > 0L
  report[[mutation$id]] <- list(killed = killed, conclusive = conclusive,
    test = mutation$test, failed_assertions = sum(counts$failed),
    warnings = sum(counts$warning))
  utils::write.csv(counts, file.path(output, paste0(mutation$id, ".csv")), row.names = FALSE)
  jsonlite::write_json(report, file.path(output, "summary.json"), auto_unbox = TRUE, pretty = TRUE)
  cat(mutation$id, if (killed) "killed by named assertions\n" else "SURVIVED OR INCONCLUSIVE\n")
}
if (!all(vapply(report, function(x) isTRUE(x$killed), logical(1)))) {
  stop("Every selected mutation must fail its named regression test.", call. = FALSE)
}
