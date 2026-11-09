# Exercise the Cloud SQL PostgreSQL transport with a local password fixture.
# Google IAM and browser sign-in require a separate live Cloud SQL deployment.
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) {
  .libPaths(c(arguments, .libPaths()))
}
Sys.setenv(LC_ALL = "C", LANG = "C", LANGUAGE = "en")
pkgload::load_all(quiet = TRUE)
source("tests/testthat/helper-authorization.R")
library(testthat)

check_cloud_sql <- function() {
  withr::local_envvar(c(PGSERVICE = NA, PGSERVICEFILE = NA))
  docker <- function(args) processx::run("docker", args)$stdout
  image <- "shinyoauthdb-azure-postgres-fixture:18.3"
  docker(c("build", "-t", image, "integration/azure-postgres-password"))
  directory <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
  fixture <- tempfile("cloud-sql-", tmpdir = directory)
  dir.create(fixture)
  fixture <- normalizePath(fixture, winslash = "/", mustWork = TRUE)
  stopifnot(identical(dirname(fixture), directory))
  on.exit(unlink(fixture, recursive = TRUE), add = TRUE)
  container <- paste0(
    "shinyoauthdb-cloud-sql-",
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
    "POSTGRES_DB=reporting",
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
        "reporting"
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
    dbname = "reporting",
    user = "postgres",
    password = "fixture-A",
    sslrootcert = ca,
    sslmode = "verify-full",
    require_auth = "password"
  )
  on.exit(DBI::dbDisconnect(admin), add = TRUE, after = FALSE)
  for (sql in c(
    "CREATE USER \"alice@example.org\" PASSWORD 'fixture-A'",
    "CREATE USER \"bob@example.org\" PASSWORD 'fixture-B'",
    "CREATE TABLE visible_rows (owner text, value text)",
    "INSERT INTO visible_rows VALUES ('alice@example.org', 'alice-only'), ('bob@example.org', 'bob-only')",
    "ALTER TABLE visible_rows ENABLE ROW LEVEL SECURITY",
    "CREATE POLICY visitor_rows ON visible_rows USING (owner = current_user)",
    "GRANT SELECT ON visible_rows TO \"alice@example.org\", \"bob@example.org\""
  )) {
    DBI::dbExecute(admin, sql)
  }
  scope <- "https://www.googleapis.com/auth/sqlservice.login"
  make <- function(auth, user, host = "localhost") {
    oauth_db_cloud_sql_postgres(
      auth$connection,
      host,
      "reporting",
      user,
      port = port,
      hostaddr = "127.0.0.1",
      sslrootcert = ca
    )
  }
  retained <- NULL
  test_that("Cloud SQL PostgreSQL enforces TLS, SQL permissions and visitor isolation", {
    odb_test_domain(function(session) {
      a <- odb_test_authorization(session, scopes = scope)
      b <- odb_test_authorization(session, id = "B", scopes = scope)
      alice <- make(a, "alice@example.org")
      bob <- make(b, "bob@example.org")
      first <- alice()
      second <- bob()
      expect_identical(
        DBI::dbGetQuery(first, "SELECT current_user AS username")$username,
        "alice@example.org"
      )
      expect_identical(
        DBI::dbGetQuery(second, "SELECT value FROM visible_rows")$value,
        "bob-only"
      )
      expect_identical(
        DBI::dbGetQuery(first, "SELECT value FROM visible_rows")$value,
        "alice-only"
      )
      expect_true(
        DBI::dbGetQuery(
          first,
          "SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()"
        )$ssl
      )
      expect_error(DBI::dbExecute(
        first,
        "INSERT INTO visible_rows VALUES ('alice@example.org', 'forbidden')"
      ))
      expect_error(make(a, "alice@example.org", "wrong.example")())
      expect_error(make(a, "bob@example.org")())

      runs <- 0L
      rows <- shiny::reactive({
        runs <<- runs + 1L
        connection <- alice()
        DBI::dbGetQuery(connection, "SELECT value FROM visible_rows")
      })
      expect_identical(rows()$value, "alice-only")
      DBI::dbExecute(
        admin,
        "ALTER ROLE \"alice@example.org\" PASSWORD 'renewed-A'"
      )
      a$token(a$make_token("renewed-A"))
      session$flushReact()
      expect_identical(rows()$value, "alice-only")
      expect_identical(runs, 1L)
      retained <<- alice()
      expect_false(DBI::dbIsValid(first))
      expect_identical(
        DBI::dbGetQuery(retained, "SELECT value FROM visible_rows")$value,
        "alice-only"
      )
      expect_true(DBI::dbIsValid(second))
      b$current(FALSE)
      session$flushReact()
      expect_false(DBI::dbIsValid(second))
    })
    expect_false(DBI::dbIsValid(retained))
  })
  test_that("Cloud SQL PostgreSQL rejects a server that skips token authentication", {
    docker(c(
      "exec",
      container,
      "sh",
      "-c",
      "printf '%s\n' 'local all all trust' 'hostssl all all all trust' > /tmp/azure-postgres-pg_hba.conf"
    ))
    DBI::dbGetQuery(admin, "SELECT pg_reload_conf()")
    # The signal only schedules reload; wait until the new rule is visible.
    for (attempt in seq_len(40L)) {
      rules <- DBI::dbGetQuery(
        admin,
        "SELECT auth_method FROM pg_hba_file_rules WHERE type = 'hostssl'"
      )
      if (identical(rules$auth_method, "trust")) {
        break
      }
      Sys.sleep(0.05)
    }
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session, scopes = scope)
      auth$token(auth$make_token("renewed-A"))
      expect_error(make(auth, "alice@example.org")(), "authentication")
    })
  })
}

check_cloud_sql()
