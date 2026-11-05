test_that("Trino rejects malformed CA paths, credentials and native argument names before connecting", {
  skip_if_not_installed("RTrino", "0.1.0")
  connected <- 0L
  local_mocked_bindings(dbConnect = function(...) {
    connected <<- connected + 1L
    stop("Invalid options must not open a native connection")
  }, .package = "DBI")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    base <- list(auth$connection, "trino.example.org", "lake", "reports", "reader")
    for (ca in list("", NA_character_, character(), c("one.pem", "two.pem"), 1, TRUE)) {
      failure <- tryCatch(do.call(oauth_db_trino, c(base, list(ca_bundle = ca))), error = identity)
      expect_s3_class(failure, "shinyOAuthDB_invalid_configuration")
    }
    for (name in c("Authentication", "Access.Token", "Token.Provider", "Client.Secret")) {
      failure <- tryCatch(do.call(oauth_db_trino,
        c(base, stats::setNames(list("sensitive-fixture-value"), name))), error = identity)
      expect_s3_class(failure, "shinyOAuthDB_invalid_configuration")
      if (inherits(failure, "condition")) {
        expect_false(grepl("sensitive-fixture-value", conditionMessage(failure), fixed = TRUE))
      }
    }
    invalid_options <- list(list(20), stats::setNames(list(20), ""),
      stats::setNames(list(20, 30), c("timeout", "")),
      stats::setNames(list(20, 30), c("timeout", "TIME.OUT")))
    for (options in invalid_options) {
      failure <- tryCatch(do.call(oauth_db_trino, c(base, options)), error = identity)
      expect_s3_class(failure, "shinyOAuthDB_invalid_configuration")
    }
    expect_identical(auth$calls$acquire, 0L)
    expect_identical(connected, 0L)
  })
})

test_that("Trino passes verified TLS and the selected CA bundle to the native driver", {
  skip_if_not_installed("RTrino", "0.1.0")
  ca <- tempfile("trino-fixture-ca-", fileext = ".pem")
  writeLines("Fixture CA content; native network calls are mocked", ca)
  on.exit(unlink(ca), add = TRUE)
  captured <- NULL
  local_mocked_bindings(dbConnect = function(drv, ...) {
    captured <<- list(...)
    "native-connection"
  }, .package = "DBI")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    con <- oauth_db_trino(auth$connection, "https://TRINO.example.org:8443/", "lake", "reports", "reader",
      ca_bundle = ca, timeout = 20)
    expect_identical(con(), "native-connection")
    expect_true(captured$ssl_options$verify)
    expect_identical(captured$ssl_options$ca_bundle, ca)
    expect_false(captured$allow_http_auth)
    expect_identical(captured$port, 8443L)
    expect_identical(captured$catalog, "lake")
    expect_identical(captured$schema, "reports")
    expect_identical(captured$user, "reader")
    expect_identical(captured$timeout, 20)
    request <- captured$auth(httr2::request("https://trino.example.org:8443/v1/statement"))
    expect_identical(httr2::req_get_headers(request, redacted = "reveal")$Authorization, "Bearer fixture-A")
    expect_false(request$options$followlocation)
    expect_error(captured$auth(httr2::request("https://trino.example.org/v1/statement")),
      class = "shinyOAuthDB_invalid_audience")
  })
})

test_that("Trino rejects malformed header names and control characters before credentials or HTTP", {
  skip_if_not_installed("RTrino", "0.1.0")
  requests <- 0L
  httr2::local_mocked_responses(function(req) {
    requests <<- requests + 1L
    trino_test_response(req)
  })
  invalid <- list(
    list(Report = "ok\r\nX-Trino-Original-User: attacker"),
    list(Report = "ok\nAuthorization: Bearer other"),
    list(Report = "ok\rCookie: other"), list(Report = "ok\tother"),
    stats::setNames(list("value"), "Report\r\nX-Trino-User"),
    stats::setNames(list("value"), "Report: X-Trino-User"),
    stats::setNames(list("value"), "Report Name"),
    list(Report = c("one", "two")), list(Report = NA_character_), list(Report = list("nested")))
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    auth$token(auth$make_token("expired", lifetime = -1))
    for (option in c("extra.headers", "extra.h", "e")) for (headers in invalid) {
      args <- c(list(auth$connection, "trino.example.org", "lake", "reports", "reader"),
        stats::setNames(list(headers), option))
      expect_error(do.call(oauth_db_trino, args)(), class = "shinyOAuthDB_invalid_configuration")
    }
    expect_identical(auth$calls$acquire, 0L)
    expect_identical(requests, 0L)
  })
})

test_that("Trino preserves valid native headers through its request builder", {
  skip_if_not_installed("RTrino", "0.1.0")
  received <- NULL
  httr2::local_mocked_responses(function(req) {
    received <<- httr2::req_get_headers(req, redacted = "reveal")
    trino_test_response(req)
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    con <- oauth_db_trino(auth$connection, "trino.example.org", "lake", "reports", "reader",
      extra.headers = list("X-Report!" = "caf\u00e9 report", "X-Number" = 12L, "X-Empty" = ""))
    expect_s4_class(con(), "TrinoConnection")
    expect_identical(received[["X-Report!"]], "caf\u00e9 report")
    expect_identical(received[["X-Number"]], "12")
    expect_identical(received$Authorization, "Bearer fixture-A")
    expect_identical(received[["X-Trino-User"]], "reader")
  })
})
