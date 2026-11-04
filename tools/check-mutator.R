# Generate real AST mutations with mutator, without changing the checkout.
arguments <- commandArgs(trailingOnly = TRUE)
profile <- if (length(arguments)) arguments[[1L]] else "all"
if (length(arguments) > 1L) .libPaths(c(arguments[-1L], .libPaths()))
Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
  SHINYOAUTHDB_POSTGRES_OAUTH = "disabled")
source("tools/validation.R")
validation_check_dependencies(c(validation_dependencies(), mutator = "0.3.0", callr = "3.7.0"))
profiles <- list(
  transport = list(files = c("http.R", "api.R", "conditions.R"),
    tests = "^(http|http-contracts|postgrest|clickhouse|api|backend-dependencies)$"),
  lifecycle = list(files = c("session.R", "authorization.R"),
    tests = "^(authorization-protocol|api|core|lifecycle|lifecycle-cleanup|operation-scopes|module-setup|custom-clients|query-button|multiple-connections)$"),
  bigquery = list(files = "backend__bigquery.R",
    tests = "^(bigquery|bigquery-responses|bigquery-contracts|bigquery-transport|bigquery-types|http|http-contracts)$"),
  trino = list(files = c("backend__trino.R", "options.R"),
    tests = "^(trino|trino-contracts|native-options|backend-dependencies)$"),
  odbc = list(files = c("odbc.R", "options.R", "backend__sql_server.R", "backend__redshift.R",
    "backend__snowflake.R", "backend__starrocks.R", "backend__databricks.R"),
    tests = "^(auth|api|backends|native-options|odbc-contracts|redshift|starrocks|backend-dependencies)$"),
  all = list(files = list.files("R", pattern = "\\.R$"), tests = NULL)
)
if (!profile %in% names(profiles)) stop("Choose transport, lifecycle, bigquery, trino, odbc or all.", call. = FALSE)
integer_setting <- function(name, default) {
  text <- Sys.getenv(name, as.character(default))
  if (!grepl("^[0-9]+$", text) || !is.finite(as.numeric(text)) ||
      as.numeric(text) < 1 || as.numeric(text) > .Machine$integer.max) {
    stop(name, " must be a positive integer.", call. = FALSE)
  }
  as.integer(text)
}
limit <- integer_setting("OAUTHDB_MUTATOR_LIMIT", 100L)
cores <- integer_setting("OAUTHDB_MUTATOR_CORES", 2L)
seed <- integer_setting("OAUTHDB_MUTATOR_SEED", 20261104L)
timeout <- integer_setting("OAUTHDB_MUTATOR_TIMEOUT", 240L)
root <- normalizePath(".", winslash = "/", mustWork = TRUE)
output <- file.path(Sys.getenv("OAUTHDB_MUTATOR_OUTPUT", file.path(root, ".validation", "mutator")), profile)
dir.create(output, recursive = TRUE, showWarnings = FALSE)

local({
  revision <- processx::run("git", c("rev-parse", "HEAD"))$stdout
  parent <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
  stage <- tempfile("oauthdb-mutator-source-", tmpdir = parent)
  dir.create(stage)
  stopifnot(identical(dirname(normalizePath(stage, winslash = "/")), parent))
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)
  # Git's manifest preserves source fixtures but excludes local credentials,
  # compiled objects, generated reports and the repository's own index.
  entries <- c("DESCRIPTION", "NAMESPACE", "LICENSE", ".Rbuildignore", "R", "man", "src",
    "configure", "cleanup", "tests", "README.md", "playground", "vignettes", "inst", "docs")
  manifest <- processx::run("git", c("-c", "core.quotepath=false", "ls-files", "--cached",
    "--others", "--exclude-standard", "--", entries), error_on_status = TRUE)$stdout
  files <- strsplit(manifest, "\n", fixed = TRUE)[[1L]]
  files <- sub("\r$", "", files)
  files <- files[nzchar(files) & file.exists(files)]
  if (!length(files) || any(grepl("(^|/)\\.\\.(/|$)", files))) {
    stop("Cannot stage package sources for mutation testing.", call. = FALSE)
  }
  for (file in files) {
    target <- file.path(stage, file)
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(file, target)) stop("Copying a mutation input failed.", call. = FALSE)
  }
  selected <- profiles[[profile]]
  # Only the disposable harness is filtered. Production tests and R sources
  # retain their exact contents; mutator owns all generated source edits.
  if (!is.null(selected$tests)) writeLines(c("library(testthat)", "library(shinyOAuthDB)",
    sprintf('test_check("shinyOAuthDB", filter = %s)', deparse(selected$tests))),
    file.path(stage, "tests", "testthat.R"))
  baseline <- callr::r(function(path, filter) {
    results <- testthat::test_local(path, filter = filter, reporter = "summary",
      stop_on_failure = FALSE, stop_on_warning = FALSE)
    counts <- as.data.frame(results)
    counts[!vapply(counts, is.list, logical(1))]
  }, args = list(stage, selected$tests), libpath = .libPaths(), timeout = 600, show = TRUE)
  validation_check_results(baseline, file.path(output, "baseline"))
  configuration <- list(profile = profile, revision = trimws(revision),
    mutator = as.character(utils::packageVersion("mutator")), seed = seed,
    limit = limit, cores = cores, timeout_seconds = timeout,
    files = selected$files, tests = selected$tests, detect_equivalent_mutants = FALSE,
    source_md5 = as.list(stats::setNames(unname(tools::md5sum(file.path(stage, "R", selected$files))), selected$files)))
  jsonlite::write_json(configuration, file.path(output, "configuration.json"),
    auto_unbox = TRUE, pretty = TRUE, null = "null")
  set.seed(seed)
  result <- mutator::mutate_package(stage, cores = cores, max_mutants = limit,
    mutation_dir = file.path(output, "generated"), timeout_seconds = timeout,
    cran = FALSE, fail_fast = TRUE, isolate = TRUE, detectEqMutants = FALSE,
    exclude_files = setdiff(list.files(file.path(stage, "R")), selected$files),
    coverage_guided = TRUE, coverage_backend = "per_file", max_show = 0L)
  saveRDS(result, file.path(output, "result.rds"))
  jsonlite::write_json(result$summary, file.path(output, "summary.json"), auto_unbox = TRUE, pretty = TRUE)
  mutants <- result$package_mutants
  dir.create(file.path(output, "mutants"), showWarnings = FALSE)
  dir.create(file.path(output, "original"), showWarnings = FALSE)
  stopifnot(all(file.copy(file.path(stage, "R", selected$files), file.path(output, "original"), overwrite = TRUE)))
  details <- do.call(rbind, lapply(names(mutants), function(id) {
    mutant <- mutants[[id]]
    saved <- paste0(id, ".R")
    stopifnot(file.copy(mutant$mutant_file, file.path(output, "mutants", saved), overwrite = TRUE))
    data.frame(id = id, file = basename(mutant$src), status = mutant$status,
      mutation = paste(mutant$mutation_info, collapse = " "),
      source_mutant = paste0("mutants/", saved), stringsAsFactors = FALSE)
  }))
  utils::write.csv(details, file.path(output, "mutants.csv"), row.names = FALSE)
  # A missing/partial campaign is never a successful report. HANG stays
  # separate from KILLED, and no external service labels survivors equivalent.
  expected <- min(result$summary$generated, limit)
  if (!expected || nrow(details) != expected || result$summary$tested != expected ||
      any(!details$status %in% c("KILLED", "SURVIVED", "HANG"))) {
    stop("The mutation campaign did not produce complete results.", call. = FALSE)
  }
  cat("Mutation results:", file.path(output, "summary.json"), "\n")
})
