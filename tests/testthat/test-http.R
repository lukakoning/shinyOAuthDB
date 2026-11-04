test_that("HTTP JSON decoding preserves authorization errors from deferred operations", {
  operation <- function() .odb_abort("Authorization ended.", "authorization_unavailable")
  expect_error(.odb_http_json(operation(), "test"), class = "shinyOAuthDB_authorization_unavailable")
})

test_that("HTTP requests account for credential acquisition in their deadline", {
  now <- 0
  requests <- list()
  local_mocked_bindings(.odb_http_time = function() now)
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    odb_http_response("[]")
  })
  token <- function(.check_only = FALSE, ...) {
    if (!.check_only) now <<- 20
    "fixture-token"
  }
  expect_error(.odb_http_request(token, httr2::request("https://data.example"), "test", 10),
    class = "shinyOAuthDB_timeout")
  expect_length(requests, 0L)
})

test_that("HTTP clients classify curl failures consistently without exposing their conditions", {
  for (backend in c("shared", "bigquery")) for (retry in c(FALSE, TRUE)) local({
    calls <- 0L
    failure <- NULL
    local_mocked_bindings(req_perform = function(req) {
      calls <<- calls + 1L
      if (retry && calls %% 2L == 1L) return(odb_http_response("[]", 401L))
      stop(failure)
    }, .package = "httr2")
    token <- function(...) "fixture-token"
    request <- function() {
      if (backend == "shared") {
        .odb_http_request(token, httr2::request("https://data.example"), "test", 10,
          retry_401 = TRUE)
      } else {
        .odb_bigquery_request(token, "GET", c("projects", "billing", "datasets"),
          .odb_bigquery_time() + 10)
      }
    }
    for (kind in c("operation_timedout", "couldnt_connect", "untyped")) {
      curl_class <- if (kind == "untyped") NULL else paste0("curl_error_", kind)
      cause <- errorCondition("private response fixture-token https://private.example", class = curl_class)
      failure <- rlang::error_cnd("httr2_failure", message = "private request details", parent = cause,
        request = list(headers = list(Authorization = "Bearer fixture-token")))
      calls <- 0L
      expected <- if (kind == "operation_timedout") "shinyOAuthDB_timeout" else "shinyOAuthDB_request_failed"
      error <- expect_error(request(), class = expected)
      expect_identical(error$transport_error, curl_class)
      expect_null(error$parent)
      expect_false(grepl("private|fixture-token", conditionMessage(error)))
      expect_identical(calls, if (retry) 2L else 1L)
    }
  })
})

test_that("HTTP transport handling preserves token acquisition errors", {
  token <- function(...) .odb_abort("Authorization ended.", "authorization_unavailable")
  expect_error(.odb_http_request(token, httr2::request("https://data.example"), "test", 10),
    class = "shinyOAuthDB_authorization_unavailable")
  expect_error(.odb_bigquery_request(token, "GET", c("projects", "billing", "datasets"),
    .odb_bigquery_time() + 10), class = "shinyOAuthDB_authorization_unavailable")
})
