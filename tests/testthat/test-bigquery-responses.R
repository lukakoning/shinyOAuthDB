test_that("BigQuery rejects malformed successful responses without exposing their contents", {
  canary <- "PRIVATE_RESPONSE_CANARY"
  bodies <- c(paste0('{"private":"', canary, '"'),
    paste0("<html>", canary, "</html>"), paste0('"', canary, '"'), "null", "42")
  for (body in bodies) local({
    requests <- 0L
    httr2::local_mocked_responses(function(req) {
      requests <<- requests + 1L
      httr2::response(200L, headers = list(`Content-Type` = "application/json"), body = charToRaw(body))
    })
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session)
      api <- oauth_db_bigquery_api(auth$connection, "billing")
      for (operation in list(function() api$query("SELECT 1"), function() api$datasets())) {
        error <- tryCatch(operation(), error = identity)
        expect_s3_class(error, "shinyOAuthDB_invalid_response")
        expect_false(grepl(paste(canary, "fixture-A", sep = "|"), conditionMessage(error)))
        expect_null(error$parent)
      }
      expect_identical(requests, 2L)
    })
  })
})

test_that("BigQuery sanitizes malformed row and schema structures", {
  canary <- "PRIVATE_STRUCTURE_CANARY"
  replacements <- list(list("schema", canary),
    list("schema", list(fields = list(list(type = canary)))),
    list("rows", list(canary)),
    list("rows", list(list(f = list(list(v = list(canary, canary)))))),
    list("rows", list(list(f = list()))))
  for (replacement in replacements) local({
    payload <- bq_test_result()
    payload[[replacement[[1L]]]] <- replacement[[2L]]
    httr2::local_mocked_responses(function(req) bq_test_response(payload))
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session)
      api <- oauth_db_bigquery_api(auth$connection, "billing")
      error <- tryCatch(api$query("SELECT value"), error = identity)
      expect_s3_class(error, "shinyOAuthDB_invalid_response")
      expect_false(grepl(canary, conditionMessage(error), fixed = TRUE))
      expect_null(error$parent)
    })
  })
})

test_that("BigQuery preserves authorization loss before decoding malformed responses", {
  selected <- NULL
  httr2::local_mocked_responses(function(req) {
    selected(NULL)
    httr2::response(200L, headers = list(`Content-Type` = "application/json"), body = charToRaw("invalid JSON"))
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    selected <<- shiny::reactiveVal(auth$connection)
    api <- oauth_db_bigquery_api(selected, "billing")
    expect_error(api$query("SELECT value"), class = "shinyOAuthDB_authorization_unavailable")
  })
  expect_error(.odb_bigquery_frame(stop(structure(list(message = "Ended", call = NULL),
    class = c("shinyOAuthDB_authorization_unavailable", "error", "condition"))), NULL),
    class = "shinyOAuthDB_authorization_unavailable")
})
