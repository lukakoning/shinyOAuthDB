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
