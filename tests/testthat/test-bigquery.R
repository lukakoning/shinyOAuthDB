test_that("BigQuery polls and pages with fresh tokens for the original authorization", {
  requests <- list()
  a <- NULL
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    n <- length(requests)
    if (n == 1L) {
      a$token(a$make_token("rotated-A"))
      result <- bq_test_result()
      result$jobComplete <- FALSE
      result$schema <- result$rows <- result$totalRows <- NULL
    } else {
      result <- bq_test_result(if (n == 2L) "first" else "second")
      if (n == 2L) result$pageToken <- "next-page"
    }
    bq_test_response(result)
  })
  odb_test_domain(function(session) {
    a <<- odb_test_authorization(session)
    api <- oauth_db_bigquery_api(a$connection, "billing", dataset = "reports", location = "EU", page_size = 1L)
    expect_identical(api$query("SELECT value FROM source")$value, c("first", "second"))
  })
  expect_length(requests, 3L)
  expect_identical(vapply(requests, function(req) httr2::req_get_headers(req, redacted = "reveal")$Authorization, ""),
    c("Bearer fixture-A", "Bearer rotated-A", "Bearer rotated-A"))
  expect_match(requests[[2L]]$url, "/queries/job-1", fixed = TRUE)
  expect_match(requests[[2L]]$url, "location=EU", fixed = TRUE)
  expect_match(requests[[3L]]$url, "pageToken=next-page", fixed = TRUE)
  body <- requests[[1L]]$body$data
  expect_false(body$useLegacySql)
  expect_identical(body$defaultDataset, list(projectId = "billing", datasetId = "reports"))
  expect_identical(body$location, "EU")
  expect_identical(body$jobCreationMode, "JOB_CREATION_REQUIRED")
  expect_match(body$requestId, "^[a-f0-9]{32}$")
})

test_that("BigQuery refreshes once on 401 without resubmitting a different mutation", {
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    if (length(requests) == 1L) bq_test_response(list(), 401L) else bq_test_response(bq_test_result("done"))
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, refresh_token = "fixture-refresh")
    api <- oauth_db_bigquery_api(auth$connection, "billing")
    expect_identical(api$query("DELETE FROM reports.orders WHERE id = @id", parameters = list(id = 7L))$value, "done")
    expect_equal(auth$calls$acquire, 1L)
  })
  expect_length(requests, 2L)
  expect_identical(requests[[1L]]$body$data, requests[[2L]]$body$data)
  expect_identical(httr2::req_get_headers(requests[[2L]], redacted = "reveal")$Authorization, "Bearer fixture-A-acquired")
})

test_that("BigQuery does not replay other errors or expose response bodies in conditions", {
  count <- 0L
  status <- 403L
  httr2::local_mocked_responses(function(req) {
    count <<- count + 1L
    bq_test_response(list(error = list(message = "fixture-secret-response")), status)
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, refresh_token = "fixture-refresh")
    api <- oauth_db_bigquery_api(auth$connection, "billing")
    error <- tryCatch(api$query("SELECT 1"), error = identity)
    expect_s3_class(error, "shinyOAuthDB_request_failed")
    expect_equal(error$status, 403L)
    expect_false(grepl("fixture-secret-response|fixture-A", conditionMessage(error)))
    expect_identical(count, 1L)
    status <<- 401L
    expect_error(api$query("SELECT 1"), class = "shinyOAuthDB_request_failed")
    expect_identical(count, 3L)
    status <<- 302L
    expect_error(api$query("SELECT 1"), class = "shinyOAuthDB_request_failed")
    expect_identical(count, 4L)
  })
})

test_that("BigQuery never changes accounts during a query or returns a late logged-out response", {
  selected <- NULL
  count <- 0L
  switch_after_request <- TRUE
  httr2::local_mocked_responses(function(req) {
    count <<- count + 1L
    if (switch_after_request) selected(NULL)
    bq_test_response(bq_test_result())
  })
  retained <- NULL
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session, id = "A")
    b <- odb_test_authorization(session, id = "B")
    selected <<- shiny::reactiveVal(a$connection)
    api <- oauth_db_bigquery_api(selected, "billing")
    expect_error(api$query("SELECT value"), class = "shinyOAuthDB_authorization_unavailable")
    expect_equal(count, 1L)
    expect_error(api$query("SELECT value"), class = "shiny.silent.error")
    switch_after_request <<- FALSE
    selected(b$connection)
    expect_equal(nrow(api$query("SELECT value")), 2L)
    retained <<- api
  })
  odb_test_domain(function(session) {
    expect_error(retained$query("SELECT value"), class = "shinyOAuthDB_authorization_unavailable")
  })
})

test_that("BigQuery clients remain independent within and across sessions", {
  tokens <- character()
  httr2::local_mocked_responses(function(req) {
    token <- httr2::req_get_headers(req, redacted = "reveal")$Authorization
    tokens <<- c(tokens, token)
    bq_test_response(bq_test_result(token))
  })
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session, id = "A")
    b <- odb_test_authorization(session, id = "B")
    api_a <- oauth_db_bigquery_api(a$connection, "billing")
    api_b <- oauth_db_bigquery_api(b$connection, "billing")
    expect_identical(api_a$query("SELECT user")$value, "Bearer fixture-A")
    expect_identical(api_b$query("SELECT user")$value, "Bearer fixture-B")
    expect_identical(api_a$query("SELECT user")$value, "Bearer fixture-A")
    a$current(FALSE)
    expect_error(api_a$query("SELECT user"), class = "shiny.silent.error")
  })
  odb_test_domain(function(session) {
    b <- odb_test_authorization(session, id = "B")
    expect_identical(oauth_db_bigquery_api(b$connection, "billing")$query("SELECT user")$value, "Bearer fixture-B")
  })
  expect_identical(tokens, c("Bearer fixture-A", "Bearer fixture-B", "Bearer fixture-A", "Bearer fixture-B"))
})

test_that("BigQuery uses query parameters without interpolating SQL", {
  body <- NULL
  httr2::local_mocked_responses(function(req) {
    body <<- req$body$data
    bq_test_response(bq_test_result("done"))
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_bigquery_api(auth$connection, "billing")
    sql <- "SELECT @country, @ids, @missing, @date, @time, @flag, @amount"
    api$query(sql, parameters = list(
      country = "'; DROP TABLE orders; --", ids = c(1L, 2L), missing = NULL,
      date = as.Date("2026-11-01"), time = as.POSIXct("2026-11-01 12:00:00", tz = "UTC"),
      flag = TRUE, amount = "12345678901234567890.12"
    ), parameter_types = c(missing = "STRING", amount = "NUMERIC"), maximum_bytes_billed = "1000000000")
    expect_identical(body$query, sql)
    expect_identical(body$parameterMode, "NAMED")
    p <- body$queryParameters
    expect_identical(p[[1L]]$parameterValue$value, "'; DROP TABLE orders; --")
    expect_identical(p[[2L]]$parameterType, list(type = "ARRAY", arrayType = list(type = "INT64")))
    expect_identical(p[[2L]]$parameterValue$arrayValues, list(list(value = "1"), list(value = "2")))
    expect_null(p[[3L]]$parameterValue$value)
    expect_identical(p[[4L]]$parameterValue$value, "2026-11-01")
    expect_match(p[[5L]]$parameterValue$value, "^2026-11-01 12:00:00")
    expect_identical(p[[6L]]$parameterValue$value, "true")
    expect_identical(p[[7L]]$parameterValue$value, "12345678901234567890.12")
    expect_identical(body$maximumBytesBilled, "1000000000")
    api$query("SELECT @ids", parameters = list(ids = 1L), parameter_types = c(ids = "ARRAY<INT64>"))
    expect_identical(body$queryParameters[[1L]]$parameterType, list(type = "ARRAY", arrayType = list(type = "INT64")))
    expect_identical(body$queryParameters[[1L]]$parameterValue$arrayValues, list(list(value = "1")))
    expect_error(api$query("SELECT 1", parameters = list(NULL)), "nonempty")
    expect_error(api$query("SELECT 1", parameters = list(x = NULL)), "parameter_types")
    expect_error(api$query("SELECT 1", parameters = list(x = 1L), parameter_types = c(y = "STRING")), "parameter_types")
    expect_error(api$query("SELECT 1", maximum_bytes_billed = -1), "maximum_bytes_billed")
  })
})

test_that("BigQuery preserves NaN separately from null in scalar and array parameters", {
  body <- NULL
  httr2::local_mocked_responses(function(req) {
    body <<- req$body$data
    bq_test_response(bq_test_result("done"))
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_bigquery_api(auth$connection, "billing")
    api$query("SELECT IS_NAN(@nan), @missing IS NULL, @values",
      parameters = list(nan = NaN, missing = NA_real_, values = c(NaN, NA_real_, 1.25)),
      parameter_types = c(values = "ARRAY<FLOAT>"))
    parameters <- body$queryParameters
    expect_identical(parameters[[1L]]$parameterType$type, "FLOAT64")
    expect_identical(parameters[[1L]]$parameterValue$value, "NaN")
    expect_null(parameters[[2L]]$parameterValue$value)
    expect_identical(parameters[[3L]]$parameterValue$arrayValues,
      list(list(value = "NaN"), list(value = NULL), list(value = "1.25")))
  })
})

test_that("BigQuery decodes exact numbers, nulls, nested values, dates, and arrays", {
  field <- function(name, type, ...) c(list(name = name, type = type), list(...))
  fields <- list(field("id", "INTEGER"), field("amount", "NUMERIC"), field("score", "FLOAT"),
    field("active", "BOOLEAN"), field("day", "DATE"), field("time", "TIMESTAMP"),
    field("tags", "STRING", mode = "REPEATED"),
    field("info", "RECORD", fields = list(field("name", "STRING"), field("count", "INTEGER"))))
  row <- list(f = list(list(v = "9007199254740993"), list(v = "12345678901234567890.123"),
    list(v = "1.5"), list(v = "true"), list(v = "2026-11-01"), list(v = "0.125"),
    list(v = list(list(v = "a"), list(v = "b"))),
    list(v = list(f = list(list(v = "name"), list(v = "42"))))))
  value <- .odb_bigquery_frame(list(row, list(f = rep(list(list(v = NULL)), length(fields)))), list(fields = fields))
  expect_identical(value$id, c("9007199254740993", NA_character_))
  expect_identical(value$amount[[1L]], "12345678901234567890.123")
  expect_identical(value$score, c(1.5, NA_real_))
  expect_identical(value$active, c(TRUE, NA))
  expect_s3_class(value$day, "Date")
  expect_s3_class(value$time, "POSIXct")
  expect_equal(as.numeric(value$time[[1L]]), 0.125)
  expect_identical(value$tags, list(c("a", "b"), character()))
  expect_identical(value$info, list(list(name = "name", count = "42"), NULL))
  empty <- .odb_bigquery_frame(list(), list(fields = fields))
  expect_identical(dim(empty), c(0L, 8L))
  expect_s3_class(empty$day, "Date")
  expect_error(.odb_bigquery_frame(list(row), NULL), class = "shinyOAuthDB_invalid_response")
})

test_that("BigQuery metadata lists all pages and raw queries preserve the schema", {
  count <- 0L
  httr2::local_mocked_responses(function(req) {
    count <<- count + 1L
    if (grepl("/datasets", req$url)) {
      if (grepl("/tables", req$url)) {
        return(bq_test_response(list(kind = "bigquery#tableList", tables = list(list(
          tableReference = list(projectId = "billing", datasetId = "reports", tableId = "orders"))))))
      }
      result <- list(kind = "bigquery#datasetList", datasets = list(list(
        datasetReference = list(projectId = "billing", datasetId = paste0("dataset", count)))))
      if (count == 1L) result$nextPageToken <- "next"
      return(bq_test_response(result))
    }
    bq_test_response(bq_test_result())
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_bigquery_api(auth$connection, "billing", dataset = "reports")
    expect_identical(api$datasets(), c("dataset1", "dataset2"))
    expect_identical(api$tables(), "orders")
    raw <- api$query("SELECT value", raw = TRUE)
    expect_identical(raw$jobReference$jobId, "job-1")
    expect_length(raw$rows, 2L)
    expect_identical(raw$schema$fields[[1L]]$type, "STRING")
  })
})

test_that("BigQuery combines result and metadata pages across empty pages", {
  requests <- 0L
  httr2::local_mocked_responses(function(req) {
    requests <<- requests + 1L
    page <- (requests - 1L) %% 3L + 1L
    if (grepl("/datasets", req$url, fixed = TRUE)) {
      result <- list(kind = "bigquery#datasetList", datasets = if (page == 2L) list() else
        list(list(datasetReference = list(projectId = "billing", datasetId = paste0("dataset", page)))))
      if (page < 3L) result$nextPageToken <- paste0("page", page + 1L)
    } else {
      result <- bq_test_result(switch(page, "first", character(), c(NA_character_, "last")))
      if (page < 3L) result$pageToken <- paste0("page", page + 1L)
    }
    bq_test_response(result)
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_bigquery_api(auth$connection, "billing", page_size = 2L)
    expect_identical(api$query("SELECT value")$value, c("first", NA_character_, "last"))
    raw <- api$query("SELECT value", raw = TRUE)
    expect_identical(raw$rows, list(list(f = list(list(v = "first"))),
      list(f = list(list(v = NULL))), list(f = list(list(v = "last")))))
    expect_identical(api$datasets(), c("dataset1", "dataset3"))
    expect_identical(requests, 9L)
  })
})

test_that("BigQuery retains submission metadata through polling and result pages", {
  for (polling in c(FALSE, TRUE)) local({
    requests <- 0L
    httr2::local_mocked_responses(function(req) {
      requests <<- requests + 1L
      page <- requests - as.integer(polling)
      result <- bq_test_result(if (page <= 1L) "first" else "second")
      result$totalRows <- "2"
      result$pageRowCount <- "1"
      if (requests == 1L) {
        result$queryId <- "query-1"
        result$creationTime <- "1000"
      }
      if (page == 0L) {
        result$jobComplete <- FALSE
        result$schema <- result$rows <- result$totalRows <- result$pageRowCount <- NULL
        result$totalSlotMs <- "1"
      } else if (page == 1L) {
        result$pageToken <- "next"
        result$totalBytesBilled <- "10000000"
        result$totalSlotMs <- "25"
        result$cacheHit <- FALSE
      } else {
        result$endTime <- "2000"
      }
      bq_test_response(result)
    })
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session)
      result <- oauth_db_bigquery_api(auth$connection, "billing")$query("SELECT value", raw = TRUE)
      expect_identical(result$queryId, "query-1")
      expect_identical(result$creationTime, "1000")
      expect_identical(result$endTime, "2000")
      expect_identical(result$totalBytesBilled, "10000000")
      expect_identical(result$totalSlotMs, "25")
      expect_false(result$cacheHit)
      expect_true(result$jobComplete)
      expect_identical(result$pageRowCount, "2")
      expect_null(result$pageToken)
      expect_identical(.odb_bigquery_frame(result$rows, result$schema)$value, c("first", "second"))
    })
    expect_identical(requests, 2L + as.integer(polling))
  })
})

test_that("BigQuery distinguishes warnings from failed jobs and bounds polling", {
  failure <- FALSE
  httr2::local_mocked_responses(function(req) {
    if (grepl("/jobs/", req$url)) {
      return(bq_test_response(list(status = if (failure) list(errorResult = list(reason = "invalidQuery")) else list(state = "DONE"))))
    }
    result <- bq_test_result()
    result$errors <- list(list(reason = "warning", message = "A warning"))
    bq_test_response(result)
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_bigquery_api(auth$connection, "billing")
    expect_equal(nrow(api$query("SELECT value")), 2L)
    failure <<- TRUE
    expect_error(api$query("SELECT value"), class = "shinyOAuthDB_query_failed")
  })
  httr2::local_mocked_responses(function(req) {
    Sys.sleep(0.04)
    bq_test_response(bq_test_result())
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_bigquery_api(auth$connection, "billing", timeout = 0.02)
    expect_error(api$query("SELECT value"), class = "shinyOAuthDB_timeout")
  })
})

test_that("BigQuery rejects loops and permission loss before subsequent requests", {
  auth <- NULL
  count <- 0L
  httr2::local_mocked_responses(function(req) {
    count <<- count + 1L
    result <- bq_test_result()
    result$pageToken <- "same"
    bq_test_response(result)
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_bigquery_api(auth$connection, "billing")
    expect_error(api$query("SELECT value"), class = "shinyOAuthDB_invalid_response")
    expect_equal(count, 2L)
    auth$status("insufficient_scope")
    expect_error(api$query("SELECT value"), class = "shiny.silent.error")
    expect_equal(count, 2L)
  })
  expect_error(oauth_db_bigquery_api(function() NULL, "billing"), class = "shinyOAuthDB_authorization_unavailable")
  expect_error(oauth_db_bigquery_api(function() NULL, "billing", page_size = 0), "page_size")
})

test_that("BigQuery sign-in uses Google scopes and preserves custom clients", {
  client <- oauth_db_bigquery_client("client", "http://localhost:8100", "secret")
  expect_s3_class(client, "shinyOAuth::OAuthClient")
  expect_true("https://www.googleapis.com/auth/bigquery" %in% client@scopes)
  expect_identical(client@provider@extra_auth_params$access_type, "offline")
  expect_length(client@token_targets, 0L)
  provider <- shinyOAuth::oauth_provider_google()
  custom <- oauth_db_bigquery_client("custom", "http://localhost:8100", "secret", provider = provider,
    scopes = c("openid", "custom"))
  expect_identical(custom@provider, provider)
  expect_identical(custom@scopes, c("openid", "custom"))
})

test_that("BigQuery accepts completed responses without renewing a still-live token", {
  auth <- NULL
  deny <- FALSE
  requests <- 0L
  httr2::local_mocked_responses(function(req) {
    requests <<- requests + 1L
    auth$token(auth$make_token("fixture-A", lifetime = 59,
      permissions = if (deny) "write" else auth$scopes))
    bq_test_response(bq_test_result("completed"))
  })
  odb_test_domain(function(session) {
    auth <<- odb_test_authorization(session)
    api <- oauth_db_bigquery_api(auth$connection, "billing", required_scopes = "read")
    expect_identical(api$query("SELECT value")$value, "completed")
    expect_identical(auth$calls$acquire, 0L)
    auth$token(auth$make_token("fixture-A"))
    deny <<- TRUE
    expect_error(api$query("SELECT value"), class = "shinyOAuthDB_authorization_unavailable")
    expect_identical(requests, 2L)
    expect_identical(auth$calls$acquire, 0L)
  })
})

test_that("BigQuery numeric parameter values ignore the display decimal mark", {
  withr::local_options(OutDec = ",")
  parameters <- .odb_bigquery_parameters(list(x = 1.25, xs = c(1.25, -2.5), id = 42L), NULL)
  expect_identical(parameters[[1L]]$parameterValue$value, "1.25")
  expect_identical(parameters[[2L]]$parameterValue$arrayValues,
    list(list(value = "1.25"), list(value = "-2.5")))
  expect_identical(parameters[[3L]]$parameterValue$value, "42")
})

test_that("BigQuery rechecks the deadline after obtaining credentials for each attempt", {
  for (method in c("POST", "GET")) local({
    now <- 0
    requests <- 0L
    local_mocked_bindings(.odb_bigquery_time = function() now)
    httr2::local_mocked_responses(function(req) {
      requests <<- requests + 1L
      bq_test_response(bq_test_result())
    })
    token <- function(...) { now <<- 20; "fixture-token" }
    expect_error(.odb_bigquery_request(token, method, c("projects", "billing", "queries"), deadline = 10),
      class = "shinyOAuthDB_timeout")
    expect_identical(requests, 0L)
  })
  now <- 0
  requests <- list()
  retry <- FALSE
  local_mocked_bindings(.odb_bigquery_time = function() now)
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    if (retry) bq_test_response(list(), 401L) else bq_test_response(bq_test_result())
  })
  token <- function(force_refresh = FALSE, .check_only = FALSE) {
    if (!.check_only) now <<- if (force_refresh) 20 else 6
    "fixture-token"
  }
  expect_identical(.odb_bigquery_request(token, "GET", c("projects", "billing", "datasets"),
    deadline = 10)$jobComplete, TRUE)
  expect_equal(requests[[1L]]$options$timeout_ms, 4000)
  now <- 0
  requests <- list()
  retry <- TRUE
  expect_error(.odb_bigquery_request(token, "POST", c("projects", "billing", "queries"), deadline = 10),
    class = "shinyOAuthDB_timeout")
  expect_length(requests, 1L)
})

test_that("BigQuery public operations include initial token acquisition in their timeout", {
  for (operation in c("query", "datasets", "tables")) local({
    now <- 0
    requests <- acquisitions <- 0L
    local_mocked_bindings(.odb_bigquery_time = function() now)
    httr2::local_mocked_responses(function(req) {
      requests <<- requests + 1L
      bq_test_response(bq_test_result())
    })
    odb_test_domain(function(session) {
      grant <- list(id = "slow-authorization", has_scopes = function(...) TRUE,
        access_token = function(...) {
          acquisitions <<- acquisitions + 1L
          now <<- now + 20
          "fixture-token"
        })
      api <- oauth_db_bigquery_api(grant, "billing", dataset = "reports", timeout = 10)
      expect_error(switch(operation,
        query = api$query("SELECT value"), datasets = api$datasets(), tables = api$tables()),
        class = "shinyOAuthDB_timeout")
      expect_identical(acquisitions, 1L)
      expect_identical(requests, 0L)
    })
  })
})
