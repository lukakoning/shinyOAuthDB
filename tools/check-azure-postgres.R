# Model Azure's password authentication with real PostgreSQL and synthetic tokens.
# No Azure account or Entra provider is used. Run from the repository root.
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) {
  .libPaths(c(arguments, .libPaths()))
}
Sys.setenv(LC_ALL = "C", LANG = "C", LANGUAGE = "en")
pkgload::load_all(quiet = TRUE)
source("tests/testthat/helper-authorization.R")
library(testthat)

check_azure_postgres <- function() {
  docker <- function(args) processx::run("docker", args)$stdout
  image <- "shinyoauthdb-azure-postgres-fixture:18.3"
  docker(c("build", "-t", image, "integration/azure-postgres-password"))
  directory <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
  fixture <- tempfile("azure-postgres-", tmpdir = directory)
  dir.create(fixture)
  fixture <- normalizePath(fixture, winslash = "/", mustWork = TRUE)
  stopifnot(identical(dirname(fixture), directory))
  on.exit(unlink(fixture, recursive = TRUE), add = TRUE)
  container <- paste0(
    "shinyoauthdb-azure-postgres-",
    Sys.getpid(),
    "-",
    sample.int(1e6, 1L)
  )
  docker(c(
    "run",
    "--detach",
    "--name",
    container,
    "--publish",
    "127.0.0.1::5432",
    "--env",
    "POSTGRES_PASSWORD=fixture-A",
    "--env",
    "POSTGRES_DB=oauth_audit",
    "--mount",
    paste0("type=bind,source=", fixture, ",target=/out"),
    image
  ))
  on.exit(
    try(docker(c("rm", "--force", "--volumes", container)), silent = TRUE),
    add = TRUE,
    after = FALSE
  )
  ready <- FALSE
  for (attempt in seq_len(120L)) {
    probe <- processx::run(
      "docker",
      c(
        "exec",
        container,
        "pg_isready",
        "-h",
        "127.0.0.1",
        "-U",
        "postgres",
        "-d",
        "oauth_audit"
      ),
      error_on_status = FALSE
    )
    if (probe$status == 0L && file.exists(file.path(fixture, "ca.pem"))) {
      ready <- TRUE
      break
    }
    Sys.sleep(0.5)
  }
  if (!ready) {
    stop(
      "PostgreSQL fixture did not become ready.\n",
      docker(c("logs", container))
    )
  }
  mapping <- trimws(docker(c("port", container, "5432/tcp")))
  stopifnot(grepl("^127[.]0[.]0[.]1:[0-9]+$", mapping))
  port <- as.integer(sub("^.*:", "", mapping))
  ca <- file.path(fixture, "ca.pem")
  admin <- DBI::dbConnect(
    RPostgres::Postgres(),
    host = "127.0.0.1",
    port = port,
    dbname = "oauth_audit",
    user = "postgres",
    password = "fixture-A",
    sslmode = "verify-full",
    sslrootcert = ca,
    require_auth = "password"
  )
  on.exit(DBI::dbDisconnect(admin), add = TRUE, after = FALSE)
  retained <- NULL
  test_that("Azure PostgreSQL recovers with the replacement password after session loss", {
    odb_test_domain(function(session) {
      auth <- suppressWarnings(odb_test_authorization(session))
      con <- oauth_db_azure_postgres(
        auth$connection,
        host = "127.0.0.1",
        dbname = "oauth_audit",
        user = "postgres",
        port = port,
        sslrootcert = ca,
        target = NULL
      )
      runs <- 0L
      rows <- shiny::reactive({
        runs <<- runs + 1L
        connection <- con()
        DBI::dbGetQuery(connection, "SELECT 1 AS value")
      })
      expect_identical(rows()$value, 1L)
      first <- con()
      pid <- DBI::dbGetQuery(first, "SELECT pg_backend_pid() AS pid")$pid
      expect_true(
        DBI::dbGetQuery(
          first,
          "SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()"
        )$ssl
      )
      DBI::dbExecute(admin, "ALTER ROLE postgres PASSWORD 'fixture-B'")
      auth$token(auth$make_token("fixture-B"))
      session$flushReact()
      expect_identical(rows()$value, 1L)
      expect_identical(runs, 1L)
      expect_true(
        DBI::dbGetQuery(
          admin,
          paste0("SELECT pg_terminate_backend(", pid, ") AS terminated")
        )$terminated
      )
      expect_error(DBI::dbGetQuery(first, "SELECT 1"))
      expect_true(DBI::dbIsValid(first))

      retained <<- con()
      expect_false(DBI::dbIsValid(first))
      expect_identical(DBI::dbGetQuery(retained, "SELECT 1 AS value")$value, 1L)
      expect_identical(con(), retained)
      expect_identical(runs, 1L)
    })
    expect_false(DBI::dbIsValid(retained))
  })
}

check_azure_postgres()
