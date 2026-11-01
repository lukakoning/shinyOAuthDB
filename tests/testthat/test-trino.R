test_that("Trino uses current user tokens for connection checks and result pages", {
  skip_if_not_installed("RTrino", "0.1.0")
  requests <- list()
  auth <- NULL
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    if (identical(req$method, "POST")) auth$token(auth$make_token("rotated-A"))
    trino_test_response(req, paginate = TRUE)
  })
  odb_test_domain(function(session) {
    auth <<- odb_test_authorization(session)
    con <- oauth_db_trino(auth$connection, "https://trino.example.org",
      catalog = "lakehouse", schema = "reports", user = "reader-A", timeout = 20)
    native <- con()
    expect_s4_class(native, "TrinoConnection")
    expect_identical(native@port, 443L)
    expect_true(native@ssl_options$verify)
    expect_equal(native@timeout, 20)
    expect_identical(DBI::dbGetQuery(native, "SELECT current_user")$database_user, "reader-A")
    expect_identical(con(), native)
  })
  headers <- lapply(requests, function(req) httr2::req_get_headers(req, redacted = "reveal"))
  expect_identical(vapply(headers, function(h) h$Authorization, ""),
    c("Bearer fixture-A", "Bearer fixture-A", "Bearer rotated-A"))
  expect_true(all(vapply(headers, function(h) identical(h[["X-Trino-User"]], "reader-A"), logical(1))))
})

test_that("Trino follows selected accounts and usernames and revokes retained callbacks", {
  skip_if_not_installed("RTrino", "0.1.0")
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    trino_test_response(req)
  })
  retained <- NULL
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session, id = "A")
    b <- odb_test_authorization(session, id = "B")
    selected <- shiny::reactiveVal(NULL)
    username <- shiny::reactiveVal("reader-A")
    con <- oauth_db_trino(selected, "trino.example.org:8443", "lakehouse", "reports", user = username)
    expect_error(con(), class = "shiny.silent.error")
    expect_length(requests, 0L)
    selected(a$connection)
    first <- con()
    expect_identical(first@port, 8443L)
    a$token(a$make_token("rotated-A"))
    expect_identical(con(), first)
    username("reader-A-alias")
    renamed <- con()
    expect_false(DBI::dbIsValid(first))
    expect_identical(renamed@user, "reader-A-alias")
    selected(b$connection)
    username("reader-B")
    second <- con()
    expect_false(DBI::dbIsValid(renamed))
    expect_identical(DBI::dbGetQuery(second, "SELECT current_user")$database_user, "reader-B")
    expect_error(renamed@auth(httr2::request("https://trino.example.org:8443")), class = "shinyOAuthDB_authorization_unavailable")
    b$status("insufficient_scope")
    expect_error(con(), class = "shiny.silent.error")
    expect_false(DBI::dbIsValid(second))
    b$status("active")
    selected(NULL)
    expect_error(con(), class = "shiny.silent.error")
    expect_error(second@auth(httr2::request("https://trino.example.org:8443")), class = "shinyOAuthDB_authorization_unavailable")
    selected(a$connection)
    retained <<- con()
  })
  expect_false(DBI::dbIsValid(retained))
  odb_test_domain(function(session) {
    expect_error(retained@auth(httr2::request("https://trino.example.org:8443")), class = "shinyOAuthDB_authorization_unavailable")
  })
})

test_that("Trino refreshes expired tokens and supports configured targets", {
  skip_if_not_installed("RTrino", "0.1.0")
  tokens <- character()
  httr2::local_mocked_responses(function(req) {
    tokens <<- c(tokens, httr2::req_get_headers(req, redacted = "reveal")$Authorization)
    trino_test_response(req)
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, target = "analytics", scopes = "read",
      refresh_token = "fixture-refresh")
    con <- oauth_db_trino(auth$connection, "trino.example.org", "lakehouse", "reports",
      user = "reader-A", target = "analytics", required_scopes = auth$scopes)
    first <- con()
    auth$token(auth$make_token("expired", lifetime = 0))
    expect_identical(con(), first)
    expect_equal(auth$calls$acquire, 1L)
    DBI::dbGetQuery(first, "SELECT current_user")
    expect_identical(tail(tokens, 1L), "Bearer fixture-A-acquired")
  })
})

test_that("Trino rejects insecure origins and conflicting connection credentials", {
  skip_if_not_installed("RTrino", "0.1.0")
  for (host in c("http://trino.example.org", "https://user:password@trino.example.org",
      "https://trino.example.org/path", "https://trino.example.org?token=x",
      "https://trino.example.org/#fragment", "https://trino.example.org bad")) {
    expect_error(oauth_db_trino(function() NULL, host, "lakehouse", "reports", user = "reader"), "HTTPS cluster origin")
  }
  expect_error(oauth_db_trino(function() NULL, "https://trino.example.org:8443",
    "lakehouse", "reports", user = "reader", port = 443), "conflicts")
  for (name in c("auth", "SSL.Options", "allow_http_auth", "Authorization", "password", "token", "drv")) {
    args <- c(list(authorization = function() NULL, host = "trino.example.org",
      catalog = "lakehouse", schema = "reports", user = "reader"),
      stats::setNames(list("sensitive-fixture-value"), name))
    error <- tryCatch(do.call(oauth_db_trino, args), error = identity)
    expect_s3_class(error, "shinyOAuthDB_invalid_configuration")
    expect_false(grepl("sensitive-fixture-value", conditionMessage(error), fixed = TRUE))
  }
  for (header in c("Authorization", "X-Trino-User", "x-presto-user", "X-Trino-Original-User", "Cookie", "Host")) {
    expect_error(oauth_db_trino(function() NULL, "trino.example.org",
      "lakehouse", "reports", user = "reader", extra.headers = stats::setNames(list("override"), header)),
      class = "shinyOAuthDB_invalid_configuration")
  }
  expect_error(oauth_db_trino(function() NULL, "trino.example.org", "lakehouse", "reports", user = "reader"),
    class = "shinyOAuthDB_authorization_unavailable")
})

test_that("Trino native errors do not trigger query replay by the bridge", {
  skip_if_not_installed("RTrino", "0.1.0")
  submissions <- 0L
  httr2::local_mocked_responses(function(req) {
    if (identical(req$method, "POST")) {
      submissions <<- submissions + 1L
      return(httr2::response(status_code = 401, url = req$url))
    }
    trino_test_response(req)
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, refresh_token = "fixture-refresh")
    con <- oauth_db_trino(auth$connection, "trino.example.org",
      "lakehouse", "reports", user = "reader")
    native <- con()
    expect_error(DBI::dbGetQuery(native, "DELETE FROM orders"), class = "httr2_http_401")
    expect_identical(submissions, 1L)
    expect_identical(auth$calls$acquire, 0L)
  })
})

test_that("Trino rejects pagination outside its HTTPS origin before sending credentials", {
  skip_if_not_installed("RTrino", "0.1.0")
  for (next_uri in c(
    "http://trino.example.org/v1/statement/query/1",
    "https://other.example.org/v1/statement/query/1",
    "https://trino.example.org:8443/v1/statement/query/1",
    "https://trino.example.org.evil.example/v1/statement/query/1",
    "https://user:password@trino.example.org/v1/statement/query/1"
  )) local({
    requests <- list()
    httr2::local_mocked_responses(function(req) {
      requests[[length(requests) + 1L]] <<- req
      response <- trino_test_response(req, paginate = TRUE)
      if (identical(req$method, "POST")) {
        payload <- httr2::resp_body_json(response, simplifyVector = FALSE)
        payload$nextUri <- next_uri
        response$body <- charToRaw(jsonlite::toJSON(payload, auto_unbox = TRUE))
      }
      response
    })
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session)
      con <- oauth_db_trino(auth$connection, "https://trino.example.org", "lake", "reports", "reader")
      expect_error(DBI::dbGetQuery(con(), "SELECT current_user"), class = "shinyOAuthDB_invalid_audience")
    })
    expect_length(requests, 2L)
    expect_true(all(vapply(requests, function(req) identical(req$options$followlocation, FALSE), logical(1))))
  })
})

test_that("Trino tracks resolved usernames without replaying SQL on profile token rotation", {
  skip_if_not_installed("RTrino", "0.1.0")
  submissions <- 0L
  httr2::local_mocked_responses(function(req) {
    if (identical(req$method, "POST")) submissions <<- submissions + 1L
    trino_test_response(req)
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    select_user <- function(token, email) {
      value <- auth$make_token(token)
      value@userinfo <- list(email = email)
      auth$token(value)
    }
    select_user("initial", "reader-A")
    con <- oauth_db_trino(auth$connection, "https://trino.example.org", "lake", "reports",
      user = function() shiny::req(auth$token()@userinfo$email))
    rows <- shiny::reactive(DBI::dbGetQuery(con(), "SELECT current_user"))
    session$flushReact()
    first <- con()
    expect_identical(rows()$database_user, "reader-A")
    select_user("rotated", "reader-A")
    session$flushReact()
    expect_identical(rows()$database_user, "reader-A")
    expect_identical(submissions, 1L)
    expect_identical(con(), first)
    select_user("renamed", "reader-B")
    session$flushReact()
    expect_false(DBI::dbIsValid(first))
    expect_identical(rows()$database_user, "reader-B")
    expect_identical(submissions, 2L)
  })
})
