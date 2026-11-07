# Real libSQL JWT authorization, TLS and lost-write-response checks.
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) {
  .libPaths(c(arguments, .libPaths()))
}
Sys.setenv(LC_ALL = "C", LANG = "C", LANGUAGE = "en")
if (.Platform$OS.type == "windows" && !nzchar(Sys.getenv("CURL_SSL_BACKEND"))) {
  Sys.setenv(CURL_SSL_BACKEND = "openssl")
}
pkgload::load_all(quiet = TRUE)
source("tests/testthat/helper-authorization.R")
library(testthat)

check_libsql_oauth <- function() {
  docker <- function(args) {
    output <- suppressWarnings(system2(
      "docker",
      shQuote(args),
      stdout = TRUE,
      stderr = TRUE
    ))
    status <- attr(output, "status")
    if (!is.null(status) && status != 0L) {
      stop(paste(output, collapse = "\n"), call. = FALSE)
    }
    output
  }
  image <- "shinyoauthdb-libsql-oauth-fixture:1"
  docker(c("build", "-t", image, "integration/libsql-oauth"))
  fixture <- tempfile("shinyOAuthDB-libsql-oauth-")
  dir.create(fixture)
  fixture <- normalizePath(fixture, winslash = "/")
  stopifnot(startsWith(
    fixture,
    paste0(normalizePath(tempdir(), winslash = "/"), "/")
  ))
  on.exit(unlink(fixture, recursive = TRUE), add = TRUE)
  port <- as.integer(Sys.getenv(
    "OAUTHDB_LIBSQL_TEST_PORT",
    as.character(httpuv::randomPort())
  ))
  container <- paste0(
    "shinyoauthdb-libsql-oauth-",
    Sys.getpid(),
    "-",
    sample.int(1e6, 1L)
  )
  docker(c(
    "run",
    "-d",
    "--name",
    container,
    "-p",
    paste0("127.0.0.1:", port, ":19498"),
    "--mount",
    paste0("type=bind,source=", fixture, ",target=/out"),
    image
  ))
  on.exit(
    try(docker(c("rm", "-f", container)), silent = TRUE),
    add = TRUE,
    after = FALSE
  )
  completed <- FALSE
  on.exit(
    if (!completed) {
      cat(paste(docker(c("logs", container)), collapse = "\n"), "\n")
    },
    add = TRUE,
    after = FALSE
  )
  for (attempt in seq_len(180L)) {
    if (file.exists(file.path(fixture, "ready"))) {
      break
    }
    Sys.sleep(0.5)
  }
  if (!file.exists(file.path(fixture, "ready"))) {
    stop(
      "libSQL fixture failed to start:\n",
      paste(docker(c("logs", container)), collapse = "\n")
    )
  }
  tokens <- jsonlite::read_json(file.path(fixture, "tokens.json"))
  ca_bundle <- file.path(fixture, "fixture-ca.pem")
  url <- paste0("https://localhost:", port)
  test_that("libSQL validates Ed25519 tokens and permissions through real TLS", {
    retained <- NULL
    odb_test_domain(function(session) {
      a <- odb_test_authorization(session)
      b <- odb_test_authorization(session, id = "B")
      a$token(a$make_token(tokens$a))
      b$token(b$make_token(tokens$b))
      selected <- shiny::reactiveVal(NULL)
      api <- oauth_db_libsql_api(selected, url, ca_bundle = ca_bundle)
      expect_error(api$query("SELECT 1"), class = "shiny.silent.error")
      selected(a$connection)
      rows <- api$query(
        "SELECT * FROM orders WHERE country = :country",
        list(country = "NL")
      )
      expect_identical(rows$id, "9223372036854775807")
      expect_identical(rows$amount, 1.25)
      expect_identical(rows$payload, list(as.raw(c(0, 255))))
      expect_error(
        api$execute("INSERT INTO events(value) VALUES ('denied')"),
        class = "shinyOAuthDB_error"
      )
      a$token(a$make_token(tokens$rotated))
      expect_identical(api$query("SELECT count(*) AS n FROM orders")$n, "1")
      selected(b$connection)
      changed <- api$execute(
        "INSERT INTO events(value) VALUES (?)",
        list("writer")
      )
      expect_equal(changed$affected_row_count, 1)
      expect_identical(changed$last_insert_rowid, "1")
      typed <- api$query(
        "SELECT ? AS id, ? AS flag, ? AS text, ? AS blob, ? AS missing",
        list(
          I("-9223372036854775808"),
          TRUE,
          "quote'; --",
          as.raw(c(0, 255)),
          NULL
        )
      )
      expect_identical(typed$id, "-9223372036854775808")
      expect_identical(typed$flag, "1")
      expect_identical(typed$text, "quote'; --")
      expect_identical(typed$blob, list(as.raw(c(0, 255))))
      expect_identical(
        api$query("SELECT ? AS blob", list(raw()))$blob,
        list(raw())
      )
      expect_true(is.na(typed$missing))
      empty <- api$query("SELECT country, amount FROM orders WHERE 0")
      expect_identical(dim(empty), c(0L, 2L))
      for (name in c("wrong_key", "expired", "other_namespace", "audience")) {
        b$token(b$make_token(tokens[[name]]))
        error <- expect_error(
          api$query("SELECT * FROM orders"),
          class = "shinyOAuthDB_error"
        )
        expect_false(grepl(
          tokens[[name]],
          conditionMessage(error),
          fixed = TRUE
        ))
      }
      b$token(b$make_token(tokens$b))
      for (fault in c("drop", "delay")) {
        faulty <- oauth_db_libsql_api(
          selected,
          paste0(url, "/", fault),
          ca_bundle = ca_bundle,
          timeout = if (fault == "delay") 0.75 else 5
        )
        expect_error(
          faulty$execute("INSERT INTO events(value) VALUES (?)", list(fault)),
          class = if (fault == "delay") {
            "shinyOAuthDB_timeout"
          } else {
            "shinyOAuthDB_request_failed"
          }
        )
        expect_identical(
          api$query(
            "SELECT count(*) AS n FROM events WHERE value = ?",
            list(fault)
          )$n,
          "1"
        )
      }
      redirect <- oauth_db_libsql_api(
        selected,
        paste0(url, "/redirect"),
        ca_bundle = ca_bundle
      )
      error <- expect_error(
        redirect$query("SELECT 1"),
        class = "shinyOAuthDB_request_failed"
      )
      expect_identical(error$status, 302L)
      untrusted <- oauth_db_libsql_api(selected, url)
      expect_error(
        untrusted$query("SELECT 1"),
        class = "shinyOAuthDB_request_failed"
      )
      wrong_host <- oauth_db_libsql_api(
        selected,
        paste0("https://127.0.0.1:", port),
        ca_bundle = ca_bundle
      )
      expect_error(
        wrong_host$query("SELECT 1"),
        class = "shinyOAuthDB_request_failed"
      )
      selected(NULL)
      expect_error(api$query("SELECT 1"), class = "shiny.silent.error")
      retained <<- api
    })
    odb_test_domain(function(session) {
      expect_error(
        retained$query("SELECT 1"),
        class = "shinyOAuthDB_authorization_unavailable"
      )
    })
  })
  cat("libSQL JWT, TLS and lost-response checks passed.\n")
  completed <- TRUE
}

check_libsql_oauth()
