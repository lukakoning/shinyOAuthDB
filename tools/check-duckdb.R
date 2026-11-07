# Real Quack transport with deterministic authorization references. The server
# accepts fixture tokens; this does not test an identity provider or quack_oauth.
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) {
  .libPaths(c(arguments, .libPaths()))
}
Sys.setenv(LC_ALL = "C", LANG = "C", LANGUAGE = "en")
pkgload::load_all(quiet = TRUE)
source("tests/testthat/helper-authorization.R")
library(testthat)

test_that("DuckDB Quack uses visitor tokens over a real connection", {
  server <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(server, shutdown = TRUE), add = TRUE)
  DBI::dbExecute(server, "INSTALL quack")
  DBI::dbExecute(server, "LOAD quack")
  DBI::dbExecute(server, "INSTALL httpfs")
  DBI::dbExecute(server, "CREATE TABLE orders AS SELECT 42 AS id")
  DBI::dbExecute(
    server,
    paste0(
      "CREATE MACRO fixture_auth(sid, client_token, server_token) AS ",
      "client_token IN ('fixture-A', 'rotated-A', 'fixture-A-acquired', 'fixture-B')"
    )
  )
  DBI::dbExecute(server, "SET quack_authentication_function = 'fixture_auth'")
  port <- as.integer(Sys.getenv("OAUTHDB_DUCKDB_TEST_PORT", "19494"))
  DBI::dbGetQuery(
    server,
    paste0(
      "CALL quack_serve('quack:127.0.0.1:",
      port,
      "', token = 'unused-fixture-server-token')"
    )
  )
  retained <- NULL
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session, refresh_token = "fixture-refresh")
    b <- odb_test_authorization(session, id = "B")
    selected <- shiny::reactiveVal(NULL)
    con <- oauth_db_duckdb(
      selected,
      "127.0.0.1",
      port = port,
      allow_local_http = TRUE,
      required_scopes = "read"
    )
    expect_error(con(), class = "shiny.silent.error")
    selected(a$connection)
    first <- con()
    expect_equal(DBI::dbGetQuery(first, "SELECT * FROM orders")$id, 42L)
    expect_equal(dplyr::collect(dplyr::tbl(first, "orders"))$id, 42L)
    expect_identical(con(), first)
    a$token(a$make_token("rotated-A"))
    rotated <- con()
    expect_false(DBI::dbIsValid(first))
    expect_equal(DBI::dbGetQuery(rotated, "SELECT * FROM orders")$id, 42L)
    a$token(a$make_token("expired", lifetime = 0))
    refreshed <- con()
    expect_false(DBI::dbIsValid(rotated))
    expect_identical(a$calls$acquire, 1L)
    expect_equal(DBI::dbGetQuery(refreshed, "SELECT * FROM orders")$id, 42L)
    selected(b$connection)
    account_b <- con()
    expect_false(DBI::dbIsValid(refreshed))
    DBI::dbExecute(account_b, "INSERT INTO orders VALUES (43)")
    expect_error(DBI::dbExecute(
      account_b,
      "INSERT INTO missing_table VALUES (1)"
    ))
    expect_equal(
      DBI::dbGetQuery(account_b, "SELECT count(*) AS n FROM orders")$n,
      2
    )
    b$token(b$make_token("server-rejected-token"))
    error <- tryCatch(con(), error = identity)
    expect_s3_class(error, "shinyOAuthDB_connection_failed")
    expect_false(grepl(
      "server-rejected-token",
      conditionMessage(error),
      fixed = TRUE
    ))
    expect_false(DBI::dbIsValid(account_b))
    b$token(b$make_token("fixture-B"))
    restored <- con()
    b$status("insufficient_scope")
    session$flushReact()
    expect_false(DBI::dbIsValid(restored))
    expect_error(con(), class = "shiny.silent.error")
    b$status("active")
    retained <<- con()
  })
  expect_false(DBI::dbIsValid(retained))

  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    tls <- oauth_db_duckdb(auth$connection, "127.0.0.1", port = port)
    expect_error(tls(), class = "shinyOAuthDB_connection_failed")
    missing_schema <- oauth_db_duckdb(
      auth$connection,
      "127.0.0.1",
      port = port,
      allow_local_http = TRUE,
      schema = "missing_schema"
    )
    expect_error(missing_schema(), class = "shinyOAuthDB_connection_failed")
  })
})
