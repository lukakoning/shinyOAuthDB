test_that("BigQuery rejects invalid job identities before polling another job", {
  canary <- "PRIVATE_JOB_REFERENCE"
  invalid <- list(
    NULL,
    canary,
    list(projectId = "another-project", jobId = canary),
    list(projectId = "billing"),
    list(projectId = "billing", jobId = ""),
    list(projectId = "billing", jobId = NA_character_),
    list(projectId = "billing", jobId = c(canary, "second-job")),
    list(projectId = "billing", jobId = 42L)
  )
  for (job in invalid) {
    local({
      requests <- list()
      httr2::local_mocked_responses(function(req) {
        requests[[length(requests) + 1L]] <<- req
        if (length(requests) > 1L) {
          stop("An invalid job reference must not cause polling")
        }
        value <- bq_test_result()
        value$jobReference <- job
        value$jobComplete <- FALSE
        bq_test_response(value)
      })
      odb_test_domain(function(session) {
        auth <- odb_test_response_authorization()
        api <- oauth_db_bigquery_api(auth$connection, "billing")
        error <- expect_error(
          api$query("SELECT value"),
          class = "shinyOAuthDB_invalid_response"
        )
        expect_false(grepl(canary, conditionMessage(error), fixed = TRUE))
        expect_null(error$parent)
        expect_length(requests, 1L)
        expect_identical(requests[[1L]]$method, "POST")
      })
    })
  }
})

test_that("BigQuery requires an unambiguous completion flag on submissions and polls", {
  for (poll in c(FALSE, TRUE)) {
    for (complete in list(NULL, NA, 1L, "true", c(TRUE, FALSE))) {
      local({
        requests <- list()
        httr2::local_mocked_responses(function(req) {
          requests[[length(requests) + 1L]] <<- req
          value <- bq_test_result()
          value$jobComplete <- if (poll && length(requests) == 1L) {
            FALSE
          } else {
            complete
          }
          bq_test_response(value)
        })
        odb_test_domain(function(session) {
          auth <- odb_test_authorization(session)
          api <- oauth_db_bigquery_api(auth$connection, "billing")
          error <- expect_error(
            api$query("SELECT value"),
            class = "shinyOAuthDB_invalid_response"
          )
          expect_null(error$parent)
          expect_length(requests, if (poll) 2L else 1L)
          expect_identical(
            sum(vapply(
              requests,
              function(req) identical(req$method, "POST"),
              logical(1)
            )),
            1L
          )
        })
      })
    }
  }
})

test_that("BigQuery metadata pagination rejects repeated cursors without an extra request", {
  for (operation in c("datasets", "tables")) {
    local({
      requests <- list()
      httr2::local_mocked_responses(function(req) {
        requests[[length(requests) + 1L]] <<- req
        if (length(requests) > 2L) {
          stop("Unexpected third metadata request")
        }
        item <- if (operation == "datasets") {
          list(
            datasetReference = list(projectId = "billing", datasetId = "one")
          )
        } else {
          list(
            tableReference = list(
              projectId = "billing",
              datasetId = "reports",
              tableId = "one"
            )
          )
        }
        payload <- list(
          kind = if (operation == "datasets") {
            "bigquery#datasetList"
          } else {
            "bigquery#tableList"
          },
          nextPageToken = "repeated-cursor"
        )
        payload[[operation]] <- list(item)
        bq_test_response(payload)
      })
      odb_test_domain(function(session) {
        auth <- odb_test_response_authorization()
        api <- oauth_db_bigquery_api(
          auth$connection,
          "billing",
          dataset = "reports"
        )
        error <- expect_error(
          api[[operation]](),
          class = "shinyOAuthDB_invalid_response"
        )
        expect_match(
          conditionMessage(error),
          "repeated a page token",
          fixed = TRUE
        )
        expect_null(error$parent)
        expect_length(requests, 2L)
        expect_true(all(vapply(
          requests,
          function(req) identical(req$method, "GET"),
          logical(1)
        )))
        expect_false(grepl("pageToken=", requests[[1L]]$url, fixed = TRUE))
        expect_match(
          requests[[2L]]$url,
          "pageToken=repeated-cursor",
          fixed = TRUE
        )
      })
    })
  }
})
