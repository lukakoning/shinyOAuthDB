test_that("HTTP deadlines below the transport resolution use the package timeout", {
  local_mocked_bindings(
    .odb_http_time = function() 0,
    .odb_bigquery_time = function() 0,
    .odb_http_perform = function(...) {
      stop("An exhausted request must not be sent")
    }
  )
  for (remaining in c(0.0005, 0.001)) {
    for (service in c("http", "bigquery")) {
      token <- function(...) "fixture"
      operation <- if (service == "http") {
        function() {
          .odb_http_request(
            token,
            httr2::request("https://example.invalid"),
            "Test",
            remaining
          )
        }
      } else {
        function() {
          .odb_bigquery_request(
            token,
            "GET",
            c("projects", "billing", "datasets"),
            remaining
          )
        }
      }
      error <- expect_error(operation(), class = "shinyOAuthDB_timeout")
      expect_null(error$parent)
    }
  }
})

test_that("credential acquisition and retry cannot send sub-millisecond requests", {
  for (service in c("http", "bigquery")) {
    for (retry in c(FALSE, TRUE)) {
      local({
        time <- 0
        requests <- 0L
        local_mocked_bindings(
          .odb_http_time = function() time,
          .odb_bigquery_time = function() time,
          .odb_http_perform = function(...) {
            requests <<- requests + 1L
            odb_http_response("{}", if (retry) 401L else 200L)
          }
        )
        token <- function(force_refresh = FALSE, .check_only = FALSE) {
          if (.check_only) {
            return(invisible(NULL))
          }
          if (force_refresh || !retry) {
            time <<- 0.9995
          }
          "fixture"
        }
        operation <- if (service == "http") {
          function() {
            .odb_http_request(
              token,
              httr2::request("https://example.invalid"),
              "Test",
              1,
              retry_401 = TRUE
            )
          }
        } else {
          function() {
            .odb_bigquery_request(
              token,
              "GET",
              c("projects", "billing", "datasets"),
              1
            )
          }
        }
        error <- expect_error(operation(), class = "shinyOAuthDB_timeout")
        expect_null(error$parent)
        expect_identical(requests, if (retry) 1L else 0L)
      })
    }
  }
})
