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
