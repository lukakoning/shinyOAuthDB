# Exercise MariaDB Connector/ODBC against a TLS protocol fixture, without Azure.
arguments <- commandArgs(trailingOnly = TRUE)
if (!length(arguments)) {
  stop(
    "Supply the MariaDB Connector/ODBC driver name or full library path.",
    call. = FALSE
  )
}
mysql_driver <- arguments[[1L]]
if (length(arguments) > 1L) {
  .libPaths(c(arguments[-1L], .libPaths()))
}
Sys.setenv(LC_ALL = "C", LANG = "C", LANGUAGE = "en")
pkgload::load_all(quiet = TRUE)
source("tests/testthat/helper-authorization.R")
library(testthat)

check_azure_mysql <- function() {
  existing <- Sys.getenv("OAUTHDB_MYSQL_TEST_FIXTURE", "")
  if (nzchar(existing)) {
    fixture <- existing
    port <- as.integer(Sys.getenv("OAUTHDB_MYSQL_TEST_PORT", "3306"))
  } else {
    docker <- function(args) processx::run("docker", args)$stdout
    image <- "shinyoauthdb-azure-mysql-protocol:1"
    docker(c("build", "-t", image, "integration/azure-mysql-password"))
    parent <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
    fixture <- tempfile("azure-mysql-", tmpdir = parent)
    dir.create(fixture)
    fixture <- normalizePath(fixture, winslash = "/", mustWork = TRUE)
    stopifnot(identical(dirname(fixture), parent))
    on.exit(unlink(fixture, recursive = TRUE), add = TRUE)
    container <- paste0(
      "shinyoauthdb-azure-mysql-",
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
      "127.0.0.1::3306",
      "--mount",
      paste0("type=bind,source=", fixture, ",target=/out"),
      image
    ))
    on.exit(
      try(docker(c("rm", "--force", "--volumes", container)), silent = TRUE),
      add = TRUE,
      after = FALSE
    )
    for (attempt in seq_len(120L)) {
      if (file.exists(file.path(fixture, "ready"))) {
        break
      }
      Sys.sleep(0.25)
    }
    if (!file.exists(file.path(fixture, "ready"))) {
      stop(
        "MySQL fixture did not become ready.\n",
        docker(c("logs", container))
      )
    }
    mapping <- trimws(docker(c("port", container, "3306/tcp")))
    stopifnot(grepl("^127[.]0[.]0[.]1:[0-9]+$", mapping))
    port <- as.integer(sub("^.*:", "", mapping))
  }
  ca <- file.path(fixture, "ca.pem")
  helper <- function(auth, user = "alice", server = "127.0.0.1", ssl_ca = ca) {
    oauth_db_azure_mysql(
      auth,
      server,
      "reporting",
      user,
      mysql_driver,
      port = port,
      ssl_ca = ssl_ca,
      target = NULL,
      timeout = 5
    )
  }
  read_audit <- function() {
    lines <- readLines(file.path(fixture, "audit.jsonl"), warn = FALSE)
    lapply(lines, jsonlite::fromJSON)
  }
  test_that("the real driver authenticates visitors and rotates tokens", {
    odb_test_domain(function(session) {
      alice <- odb_test_authorization(session)
      bob <- odb_test_authorization(session, id = "B")
      selected <- shiny::reactiveVal(alice$connection)
      user <- shiny::reactiveVal("alice")
      con <- helper(selected, user)
      first <- con()
      expect_identical(
        DBI::dbGetQuery(first, "SELECT value FROM visible_rows")$value,
        "alice-visible"
      )
      expect_error(DBI::dbGetQuery(first, "SELECT secret FROM admin_only"))
      alice$token(alice$make_token("renewed-A"))
      second <- con()
      expect_false(DBI::dbIsValid(first))
      expect_identical(
        DBI::dbGetQuery(second, "SELECT CURRENT_USER() AS visitor")$visitor,
        "alice"
      )
      alice$token(alice$make_token(paste0("long-", strrep("x", 12000L))))
      long <- con()
      expect_false(DBI::dbIsValid(second))
      expect_true(DBI::dbIsValid(long))
      selected(bob$connection)
      user("bob")
      other <- con()
      expect_false(DBI::dbIsValid(long))
      expect_identical(
        DBI::dbGetQuery(other, "SELECT value FROM visible_rows")$value,
        "bob-visible"
      )
      selected(NULL)
      session$flushReact()
      expect_false(DBI::dbIsValid(other))
      expect_error(con(), class = "shiny.silent.error")
    })
  })
  test_that("wrong tokens and identities fail without falling back", {
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session)
      mismatch <- helper(auth$connection, user = "bob")
      expect_error(mismatch())
      auth$token(auth$make_token("invalid-token"))
      invalid <- helper(auth$connection)
      expect_error(invalid())
    })
  })
  test_that("untrusted and mismatched certificates fail before password authentication", {
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session)
      before <- length(read_audit())
      wrong_host <- helper(auth$connection, server = "localhost")
      failure <- expect_error(wrong_host())
      expect_match(
        conditionMessage(failure),
        "certificate|hostname|SSL|TLS",
        ignore.case = TRUE
      )
      no_trust <- helper(
        auth$connection,
        ssl_ca = file.path(fixture, "missing-ca.pem")
      )
      failure <- expect_error(no_trust())
      expect_match(
        conditionMessage(failure),
        "certificate|SSL|TLS",
        ignore.case = TRUE
      )
      expect_length(read_audit(), before)
    })
  })
  records <- read_audit()
  authentications <- Filter(
    function(x) identical(x$event, "authentication"),
    records
  )
  connections <- Filter(function(x) identical(x$event, "connection"), records)
  stopifnot(
    length(connections) >= 4L,
    all(vapply(connections, function(x) isTRUE(x$tls), logical(1))),
    any(vapply(
      authentications,
      function(x) identical(x$length, 12005L) && x$accepted,
      logical(1)
    )),
    any(vapply(authentications, function(x) !x$accepted, logical(1)))
  )
  cat(
    "Azure MySQL driver protocol checks passed; live Azure authentication was not tested.\n"
  )
}

check_azure_mysql()
