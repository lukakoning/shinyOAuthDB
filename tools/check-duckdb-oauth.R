# End-to-end JWT validation with a Linux quack_oauth server and TLS proxy.
# Run from the repository root, with Docker running.
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) .libPaths(c(arguments, .libPaths()))
Sys.setenv(LC_ALL = "C", LANG = "C", LANGUAGE = "en")
pkgload::load_all(quiet = TRUE)
source("tests/testthat/helper-authorization.R")
library(testthat)

check_duckdb_oauth <- function() {
  docker <- function(args) {
    output <- suppressWarnings(system2("docker", shQuote(args), stdout = TRUE, stderr = TRUE))
    status <- attr(output, "status")
    if (!is.null(status) && status != 0L) stop(paste(output, collapse = "\n"), call. = FALSE)
    output
  }
  provision <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(if (DBI::dbIsValid(provision)) DBI::dbDisconnect(provision, shutdown = TRUE), add = TRUE)
  version <- sub("^v", "", DBI::dbGetQuery(provision, "SELECT version()")[[1L]])
  DBI::dbExecute(provision, "INSTALL quack")
  DBI::dbExecute(provision, "INSTALL httpfs")
  DBI::dbDisconnect(provision, shutdown = TRUE)
  image <- paste0("shinyoauthdb-duckdb-oauth-fixture:", version)
  docker(c("build", "--build-arg", paste0("DUCKDB_VERSION=", version),
    "-t", image, "integration/duckdb-oauth"))
  fixture <- tempfile("shinyOAuthDB-duckdb-oauth-")
  dir.create(fixture)
  fixture <- normalizePath(fixture, winslash = "/")
  stopifnot(startsWith(fixture, paste0(normalizePath(tempdir(), winslash = "/"), "/")))
  on.exit(unlink(fixture, recursive = TRUE), add = TRUE)
  port <- as.integer(Sys.getenv("OAUTHDB_DUCKDB_TLS_TEST_PORT", as.character(httpuv::randomPort())))
  container <- paste0("shinyoauthdb-duckdb-oauth-", Sys.getpid(), "-", sample.int(1e6, 1L))
  docker(c("run", "-d", "--name", container,
    "-p", paste0("127.0.0.1:", port, ":19496"),
    "--mount", paste0("type=bind,source=", fixture, ",target=/out"), image))
  on.exit(try(docker(c("rm", "-f", container)), silent = TRUE), add = TRUE, after = FALSE)
  for (attempt in seq_len(180L)) {
    if (file.exists(file.path(fixture, "ready"))) break
    Sys.sleep(0.5)
  }
  if (!file.exists(file.path(fixture, "ready"))) {
    stop("DuckDB OAuth fixture failed to start:\n", paste(docker(c("logs", container)), collapse = "\n"))
  }
  tokens <- jsonlite::read_json(file.path(fixture, "tokens.json"))
  ca_bundle <- file.path(fixture, "fixture-ca.pem")
  test_that("real quack_oauth validates JWT signatures, audiences and scopes over TLS", {
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session)
      auth$token(auth$make_token(tokens$a))
      tls <- oauth_db_duckdb(auth$connection, "localhost", port = port,
        ca_bundle = ca_bundle, required_scopes = "read")
      first <- tls()
      expect_equal(DBI::dbGetQuery(first, "SELECT * FROM orders")$id, 42L)
      expect_equal(dplyr::collect(dplyr::tbl(first, "orders"))$id, 42L)
      expect_error(DBI::dbExecute(first, "INSERT INTO orders VALUES (43)"))
      expect_equal(DBI::dbGetQuery(first, "SELECT count(*) AS n FROM orders")$n, 1)
      auth$token(auth$make_token(tokens$b))
      second <- tls()
      expect_false(DBI::dbIsValid(first))
      expect_equal(DBI::dbGetQuery(second, "SELECT * FROM orders")$id, 42L)
      for (bad in list(tokens$denied, tokens$audience, paste0(tokens$a, "invalid"))) {
        auth$token(auth$make_token(bad))
        error <- tryCatch(tls(), error = identity)
        expect_s3_class(error, "shinyOAuthDB_connection_failed")
        expect_false(grepl(bad, conditionMessage(error), fixed = TRUE))
      }
      auth$token(auth$make_token(tokens$a))
      expect_true(DBI::dbIsValid(tls()))
      untrusted <- oauth_db_duckdb(auth$connection, "localhost", port = port)
      expect_error(untrusted(), class = "shinyOAuthDB_connection_failed")
      wrong_hostname <- oauth_db_duckdb(auth$connection, "127.0.0.1", port = port,
        ca_bundle = ca_bundle)
      expect_error(wrong_hostname(), class = "shinyOAuthDB_connection_failed")
    })
  })
  cat("DuckDB", version, "OAuth and TLS checks passed.\n")
}

check_duckdb_oauth()
