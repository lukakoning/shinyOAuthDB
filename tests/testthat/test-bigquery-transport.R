test_that("BigQuery refuses redirects and enforces both ends of the HTTP success range", {
  for (status in c(199L, 200L, 299L, 300L, 302L)) {
    local({
      requests <- list()
      httr2::local_mocked_responses(function(req) {
        requests[[length(requests) + 1L]] <<- req
        value <- if (identical(req$method, "POST")) {
          bq_test_result()
        } else {
          list(kind = "bigquery#datasetList", datasets = list())
        }
        bq_test_response(value, status)
      })
      odb_test_domain(function(session) {
        auth <- odb_test_authorization(
          session,
          refresh_token = "fixture-refresh"
        )
        api <- oauth_db_bigquery_api(auth$connection, "billing")
        for (operation in list(
          function() api$query("SELECT value"),
          function() api$datasets()
        )) {
          if (status %in% c(200L, 299L)) {
            result <- tryCatch(operation(), error = identity)
            expect_false(
              inherits(result, "error"),
              info = if (inherits(result, "error")) conditionMessage(result)
            )
          } else {
            error <- tryCatch(operation(), error = identity)
            expect_s3_class(error, "shinyOAuthDB_request_failed")
            expect_identical(error$status, status)
          }
        }
        expect_length(requests, 2L)
        expect_true(all(vapply(
          requests,
          function(req) identical(req$options$followlocation, FALSE),
          logical(1)
        )))
        expect_identical(auth$calls$acquire, 0L)
      })
    })
  }
})

test_that("BigQuery submission retries respect the 15-minute request-ID window in long-lived apps", {
  for (elapsed in c(2, 899.9, 900)) {
    local({
      now <- 10000
      requests <- list()
      local_mocked_bindings(.odb_bigquery_time = function() now)
      httr2::local_mocked_responses(function(req) {
        requests[[length(requests) + 1L]] <<- req
        if (length(requests) == 1L) {
          now <<- 10000 + elapsed
          return(bq_test_response(list(), 401L))
        }
        bq_test_response(bq_test_result())
      })
      odb_test_domain(function(session) {
        auth <- odb_test_authorization(
          session,
          refresh_token = "fixture-refresh"
        )
        api <- oauth_db_bigquery_api(auth$connection, "billing", timeout = 1800)
        operation <- function() {
          api$query(
            "UPDATE reporting SET value = @value",
            parameters = list(value = "one")
          )
        }
        if (elapsed < 900) {
          expect_equal(nrow(operation()), 2L)
          expect_length(requests, 2L)
          expect_identical(requests[[1L]]$body$data, requests[[2L]]$body$data)
          expect_match(requests[[1L]]$body$data$requestId, "^[0-9a-f]{32}$")
        } else {
          error <- tryCatch(operation(), error = identity)
          expect_s3_class(error, "shinyOAuthDB_timeout")
          expect_length(requests, 1L)
        }
        expect_true(all(vapply(
          requests,
          function(req) identical(req$method, "POST"),
          logical(1)
        )))
        expect_identical(auth$calls$acquire, 1L)
      })
    })
  }
})
