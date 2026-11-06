# Real CrateDB JWT authentication, privileges, HTTPS and uncertain write outcomes.
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) .libPaths(c(arguments, .libPaths()))
Sys.setenv(LC_ALL = "C", LANG = "C", LANGUAGE = "en")
pkgload::load_all(quiet = TRUE)
source("tests/testthat/helper-authorization.R")
library(testthat)

check_cratedb_oauth <- function() {
  docker <- function(args) {
    output <- suppressWarnings(system2("docker", shQuote(args), stdout = TRUE, stderr = TRUE))
    status <- attr(output, "status")
    if (!is.null(status) && status != 0L) {
      dir.create(".validation", showWarnings = FALSE)
      writeLines(output, ".validation/cratedb-docker.log")
      cat(tail(output, 90L), sep = "\n")
      stop("CrateDB fixture command failed; see .validation/cratedb-docker.log.", call. = FALSE)
    }
    output
  }
  fixture <- tempfile("shinyOAuthDB-cratedb-")
  dir.create(fixture)
  fixture <- normalizePath(fixture, winslash = "/")
  stopifnot(startsWith(fixture, paste0(normalizePath(tempdir(), winslash = "/"), "/")))
  on.exit(unlink(fixture, recursive = TRUE), add = TRUE)
  port <- as.integer(Sys.getenv("OAUTHDB_CRATEDB_TEST_PORT", as.character(httpuv::randomPort())))
  withr::local_envvar(c(OAUTHDB_CRATEDB_TEST_PORT = as.character(port), OAUTHDB_CRATEDB_FIXTURE_OUT = fixture))
  project <- paste0("oauthdb-cratedb-", Sys.getpid(), "-", sample.int(1e6, 1L))
  compose <- c("compose", "--project-name", project, "--file", "integration/cratedb-oauth/compose.yml")
  on.exit(try(docker(c(compose, "down", "--volumes", "--remove-orphans")), silent = TRUE), add = TRUE, after = FALSE)
  success <- FALSE
  on.exit(if (!success) cat(docker(c(compose, "logs", "--tail", "30")), sep = "\n"), add = TRUE, after = FALSE)
  docker(c(compose, "up", "--build", "--detach", "fixture"))
  for (attempt in seq_len(360L)) {
    if (file.exists(file.path(fixture, "ready"))) break
    if (attempt %% 10L == 0L && any(grepl("exited", docker(c(compose, "ps", "--all", "--format", "{{.State}}")), ignore.case = TRUE))) {
      stop("CrateDB fixture exited:\n", paste(docker(c(compose, "logs", "--tail", "40")), collapse = "\n"))
    }
    Sys.sleep(0.5)
  }
  if (!file.exists(file.path(fixture, "ready"))) {
    stop("CrateDB fixture failed to start:\n", paste(docker(c(compose, "logs", "--tail", "60")), collapse = "\n"))
  }
  if (.Platform$OS.type == "windows") {
    docker(c("build", "--target", "runner", "--tag", "shinyoauthdb-local-runner:1", "integration/local"))
    docker(c(compose, "run", "--rm", "--no-deps", "-T", "test-runner"))
  } else {
    withr::local_envvar(c(OAUTHDB_CRATEDB_ENDPOINT = paste0("https://localhost:", port, "/_sql")))
    results <- testthat::test_file("integration/cratedb-oauth/test-api.R", reporter = "summary")
    source("integration/contracts.R", local = TRUE)
    integration_validate_results(as.data.frame(results),
      "CrateDB authenticates real visitor JWTs and enforces user privileges")
    counts <- as.data.frame(results)
    jsonlite::write_json(list(server = "CrateDB 6.4.3", scenarios = counts$test,
      passed = sum(counts$passed), failed = sum(counts$failed), warnings = sum(counts$warning)),
      file.path(fixture, "results.json"), auto_unbox = TRUE, pretty = TRUE)
  }
  dir.create(".validation", showWarnings = FALSE)
  stopifnot(file.copy(file.path(fixture, "results.json"), ".validation/cratedb-results.json", overwrite = TRUE))
  report <- jsonlite::read_json(".validation/cratedb-results.json")
  cat("CrateDB JWT/TLS integration passed:", report$passed, "assertions.\n")
  success <- TRUE
}

check_cratedb_oauth()
