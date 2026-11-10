test_that("BigQuery rejects malformed successful responses without exposing their contents", {
  canary <- "PRIVATE_RESPONSE_CANARY"
  bodies <- c(
    paste0('{"private":"', canary, '"'),
    paste0("<html>", canary, "</html>"),
    paste0('"', canary, '"'),
    "null",
    "42"
  )
  for (body in bodies) {
    local({
      requests <- 0L
      httr2::local_mocked_responses(function(req) {
        requests <<- requests + 1L
        httr2::response(
          200L,
          headers = list(`Content-Type` = "application/json"),
          body = charToRaw(body)
        )
      })
      odb_test_domain(function(session) {
        auth <- odb_test_response_authorization()
        api <- oauth_db_bigquery_api(auth$connection, "billing")
        for (operation in list(function() api$query("SELECT 1"), function() {
          api$datasets()
        })) {
          error <- tryCatch(operation(), error = identity)
          expect_s3_class(error, "shinyOAuthDB_invalid_response")
          expect_false(grepl(
            paste(canary, "fixture-A", sep = "|"),
            conditionMessage(error)
          ))
          expect_null(error$parent)
        }
        expect_identical(requests, 2L)
      })
    })
  }
})

test_that("BigQuery sanitizes malformed row and schema structures", {
  canary <- "PRIVATE_STRUCTURE_CANARY"
  replacements <- list(
    list("schema", canary),
    list("schema", list(fields = list(list(type = canary)))),
    list("rows", list(canary)),
    list("rows", list(list(f = list(list(v = list(canary, canary)))))),
    list("rows", list(list(f = list())))
  )
  for (replacement in replacements) {
    local({
      payload <- bq_test_result()
      payload[[replacement[[1L]]]] <- replacement[[2L]]
      httr2::local_mocked_responses(function(req) bq_test_response(payload))
      odb_test_domain(function(session) {
        auth <- odb_test_response_authorization()
        api <- oauth_db_bigquery_api(auth$connection, "billing")
        error <- tryCatch(api$query("SELECT value"), error = identity)
        expect_s3_class(error, "shinyOAuthDB_invalid_response")
        expect_false(grepl(canary, conditionMessage(error), fixed = TRUE))
        expect_null(error$parent)
      })
    })
  }
})

test_that("BigQuery preserves authorization loss before decoding malformed responses", {
  selected <- NULL
  httr2::local_mocked_responses(function(req) {
    selected(NULL)
    httr2::response(
      200L,
      headers = list(`Content-Type` = "application/json"),
      body = charToRaw("invalid JSON")
    )
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    selected <<- shiny::reactiveVal(auth$connection)
    api <- oauth_db_bigquery_api(selected, "billing")
    expect_error(
      api$query("SELECT value"),
      class = "shinyOAuthDB_authorization_unavailable"
    )
  })
  expect_error(
    .odb_bigquery_frame(
      stop(structure(
        list(message = "Ended", call = NULL),
        class = c(
          "shinyOAuthDB_authorization_unavailable",
          "error",
          "condition"
        )
      )),
      NULL
    ),
    class = "shinyOAuthDB_authorization_unavailable"
  )
})

test_that("BigQuery metadata rejects malformed pages without exposing response details", {
  canary <- "PRIVATE_METADATA_CANARY"
  for (field in c("datasets", "tables")) {
    local({
      resource <- if (field == "datasets") "dataset" else "table"
      valid <- list(kind = paste0("bigquery#", resource, "List"))
      reference <- list(projectId = "billing", datasetId = "reports")
      if (field == "tables") {
        reference$tableId <- "orders"
      }
      valid[[field]] <- list(stats::setNames(
        list(reference),
        paste0(resource, "Reference")
      ))
      collection <- function(value) {
        result <- valid
        result[field] <- list(value)
        result
      }
      invalid <- list(
        list(),
        list(valid),
        list(error = list(message = canary)),
        utils::modifyList(valid, list(kind = canary)),
        utils::modifyList(valid, list(error = list(message = canary))),
        collection(canary),
        collection(list(canary)),
        collection(list(private = canary)),
        collection(NULL),
        collection(list(list())),
        utils::modifyList(valid, list(nextPageToken = list(canary)))
      )
      for (name in names(reference)) {
        bad <- valid
        bad[[field]][[1L]][[paste0(resource, "Reference")]][[name]] <- canary
        if (name %in% c("datasetId", "tableId")) {
          bad[[field]][[1L]][[paste0(resource, "Reference")]][[name]] <- c(
            canary,
            canary
          )
        }
        invalid[[length(invalid) + 1L]] <- bad
      }
      body <- NULL
      requests <- 0L
      httr2::local_mocked_responses(function(req) {
        requests <<- requests + 1L
        bq_test_response(body)
      })
      odb_test_domain(function(session) {
        auth <- odb_test_response_authorization()
        api <- oauth_db_bigquery_api(
          auth$connection,
          "billing",
          dataset = "reports"
        )
        for (value in invalid) {
          body <<- value
          error <- tryCatch(
            if (field == "datasets") api$datasets() else api$tables(),
            error = identity
          )
          expect_s3_class(error, "shinyOAuthDB_invalid_response")
          expect_false(grepl(
            paste(canary, "fixture-A", sep = "|"),
            conditionMessage(error)
          ))
          expect_null(error$parent)
        }
        expect_identical(requests, length(invalid))
      })
    })
  }
})

test_that("BigQuery metadata accepts empty collections and empty intermediate pages", {
  for (field in c("datasets", "tables")) {
    for (omitted in c(TRUE, FALSE)) {
      local({
        resource <- if (field == "datasets") "dataset" else "table"
        requests <- 0L
        httr2::local_mocked_responses(function(req) {
          requests <<- requests + 1L
          result <- list(kind = paste0("bigquery#", resource, "List"))
          if (!omitted) {
            result[[field]] <- list()
          }
          if (requests == 1L) {
            result$nextPageToken <- "next"
          }
          bq_test_response(result)
        })
        odb_test_domain(function(session) {
          auth <- odb_test_response_authorization()
          api <- oauth_db_bigquery_api(
            auth$connection,
            "billing",
            dataset = "reports"
          )
          expect_identical(
            if (field == "datasets") api$datasets() else api$tables(),
            character()
          )
          expect_identical(requests, 2L)
        })
      })
    }
  }
})

test_that("BigQuery rejects dataset listings that omit unreachable locations", {
  for (page in c(1L, 2L)) {
    for (empty in c(FALSE, TRUE)) {
      local({
        requests <- 0L
        httr2::local_mocked_responses(function(req) {
          requests <<- requests + 1L
          result <- list(kind = "bigquery#datasetList")
          if (!empty) {
            result$datasets <- list(list(
              datasetReference = list(
                projectId = "billing",
                datasetId = "reports"
              )
            ))
          }
          if (requests < page) {
            result$nextPageToken <- "next"
          } else {
            result$unreachable <- list("PRIVATE_LOCATION_CANARY")
          }
          bq_test_response(result)
        })
        odb_test_domain(function(session) {
          auth <- odb_test_response_authorization()
          api <- oauth_db_bigquery_api(auth$connection, "billing")
          error <- expect_error(
            api$datasets(),
            "discovery is incomplete",
            class = "shinyOAuthDB_query_failed"
          )
          expect_false(grepl(
            "PRIVATE_LOCATION_CANARY",
            conditionMessage(error),
            fixed = TRUE
          ))
          expect_null(error$parent)
          expect_identical(requests, page)
        })
      })
    }
  }
})

test_that("BigQuery accepts dataset discovery without unreachable locations", {
  for (unreachable in list(NULL, list())) {
    local({
      httr2::local_mocked_responses(function(req) {
        bq_test_response(list(
          kind = "bigquery#datasetList",
          unreachable = unreachable
        ))
      })
      odb_test_domain(function(session) {
        auth <- odb_test_authorization(session)
        api <- oauth_db_bigquery_api(auth$connection, "billing")
        expect_identical(api$datasets(), character())
      })
    })
  }
})
