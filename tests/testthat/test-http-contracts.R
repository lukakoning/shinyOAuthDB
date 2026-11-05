test_that("HTTP clients accept the complete 2xx range and reject its adjacent statuses", {
  canary <- "PRIVATE_HTTP_BODY"
  for (status in c(199L, 200L, 299L, 300L)) local({
    calls <- acquired <- 0L
    httr2::local_mocked_responses(function(req) {
      calls <<- calls + 1L
      odb_http_response(canary, status)
    })
    token <- function(.check_only = FALSE, ...) {
      if (!.check_only) acquired <<- acquired + 1L
      "fixture-token"
    }
    perform <- function() .odb_http_request(token, httr2::request("https://data.example"),
      "fixture", timeout = 10, retry_401 = TRUE)
    if (status %in% c(200L, 299L)) {
      expect_identical(httr2::resp_status(perform()), status)
    } else {
      error <- expect_error(perform(), class = "shinyOAuthDB_request_failed")
      expect_identical(error$status, status)
      expect_false(grepl(canary, conditionMessage(error), fixed = TRUE))
      expect_null(error$parent)
    }
    expect_identical(calls, 1L)
    expect_identical(acquired, 1L)
  })
})

test_that("HTTP clients discard responses arriving exactly at the deadline", {
  for (finished in c(9.99, 10)) local({
    now <- 0
    checked <- requests <- 0L
    local_mocked_bindings(.odb_http_time = function() now)
    httr2::local_mocked_responses(function(req) {
      requests <<- requests + 1L
      now <<- finished
      odb_http_response("[]")
    })
    token <- function(.check_only = FALSE, ...) {
      if (.check_only) checked <<- checked + 1L
      "fixture-token"
    }
    perform <- function() .odb_http_request(token, httr2::request("https://data.example"), "fixture", timeout = 10)
    if (finished < 10) expect_identical(httr2::resp_status(perform()), 200L) else {
      expect_error(perform(), class = "shinyOAuthDB_timeout")
    }
    expect_identical(requests, 1L)
    expect_identical(checked, 1L)
  })
})

test_that("a refresh finishing at the deadline cannot send another HTTP request", {
  now <- 0
  requests <- forced <- 0L
  local_mocked_bindings(.odb_http_time = function() now)
  httr2::local_mocked_responses(function(req) {
    requests <<- requests + 1L
    now <<- 4
    odb_http_response("[]", 401L)
  })
  token <- function(force_refresh = FALSE, .check_only = FALSE) {
    if (force_refresh) {
      forced <<- forced + 1L
      now <<- 10
    }
    "fixture-token"
  }
  expect_error(.odb_http_request(token, httr2::request("https://data.example"),
    "fixture", timeout = 10, retry_401 = TRUE), class = "shinyOAuthDB_timeout")
  expect_identical(requests, 1L)
  expect_identical(forced, 1L)
})

test_that("HTTP operation timeouts reject zero before authorization or network work", {
  for (factory in list(oauth_db_postgrest_api, oauth_db_clickhouse_api)) {
    failure <- tryCatch(factory(stop("Authorization must stay lazy"), "https://data.example", timeout = 0), error = identity)
    expect_s3_class(failure, "shinyOAuthDB_invalid_configuration")
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session)
      failure <- tryCatch(factory(auth$connection, "https://data.example", timeout = 0), error = identity)
      expect_s3_class(failure, "shinyOAuthDB_invalid_configuration")
      # A small positive request budget and a zero token-lifetime requirement
      # are both valid, and constructing the client must not request a token.
      client <- factory(auth$connection, "https://data.example", timeout = 0.001, min_valid_for = 0)
      expect_s3_class(client, "R6")
      expect_identical(auth$calls$acquire, 0L)
    })
  }
})

test_that("completed HTTP responses do not renew newly short-lived tokens", {
  for (backend in c("postgrest", "clickhouse")) local({
    auth <- NULL
    requests <- 0L
    httr2::local_mocked_responses(function(req) {
      requests <<- requests + 1L
      auth$token(auth$make_token("still-live", lifetime = 30))
      body <- if (backend == "postgrest") '[{"value":"ok"}]' else
        '{"meta":[{"name":"value","type":"String"}],"data":[["ok"]],"rows":1}'
      odb_http_response(body)
    })
    odb_test_domain(function(session) {
      auth <<- odb_test_authorization(session, refresh_token = "fixture-refresh")
      auth$token(auth$make_token("initial", lifetime = 120))
      if (backend == "postgrest") {
        api <- oauth_db_postgrest_api(auth$connection, "https://data.example", min_valid_for = 60)
        result <- api$select("rows")
      } else {
        api <- oauth_db_clickhouse_api(auth$connection, "https://data.example", min_valid_for = 60)
        result <- api$query("SELECT 'ok' AS value")
      }
      expect_identical(result$value, "ok")
      expect_identical(requests, 1L)
      expect_identical(auth$calls$acquire, 0L)
    })
  })
})

test_that("HTTP responses are discarded when postflight refresh ends authorization", {
  for (backend in c("postgrest", "clickhouse", "bigquery")) for (target in list(NULL, "data")) local({
    requests <- 0L
    auth <- NULL
    httr2::local_mocked_responses(function(req) {
      requests <<- requests + 1L
      auth$token(auth$make_token("expired", lifetime = -1))
      odb_http_response("[]")
    })
    odb_test_domain(function(session) {
      auth <<- odb_test_authorization(session, target = target, refresh_token = "fixture-refresh",
        acquire = function(...) {
          auth$current(FALSE)
          stop("Fixture refresh rejection")
        })
      api <- switch(backend,
        postgrest = oauth_db_postgrest_api(auth$connection, "https://data.example", target = target),
        clickhouse = oauth_db_clickhouse_api(auth$connection, "https://data.example", target = target),
        bigquery = oauth_db_bigquery_api(auth$connection, "billing", target = target))
      operation <- if (backend == "postgrest") function() api$select("rows") else function() api$query("SELECT 1")
      expect_error(operation(), class = "shinyOAuthDB_authorization_unavailable")
      expect_false(auth$current())
      expect_identical(auth$calls$acquire, 1L)
      expect_identical(requests, 1L)
    })
  })
})

test_that("PostgREST rejects reserved and malformed query options before HTTP", {
  invalid <- list(NULL, c(id = "eq.1"), list(id = c("eq.1", "eq.2")),
    list(id = NA_character_), list(.req = "another-request"),
    list(.multi = "explode"), list(.space = "%20"))
  for (query in invalid) local({
    requests <- 0L
    httr2::local_mocked_responses(function(req) {
      requests <<- requests + 1L
      odb_http_response('[{"id":1}]')
    })
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session)
      api <- oauth_db_postgrest_api(auth$connection, "https://data.example")
      failure <- tryCatch(api$request("rows", query = query), error = identity)
      expect_s3_class(failure, "shinyOAuthDB_invalid_configuration")
      expect_identical(requests, 0L)
      expect_identical(auth$calls$acquire, 0L)
    })
  })
})
