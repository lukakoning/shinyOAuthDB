test_that("HTTP failures expose bounded service codes and request identifiers", {
  request_id <- "36cf6384-1189-4a47-8272-bf3a01fa3536"
  for (service in c("BigQuery", "PostgREST", "ClickHouse")) {
    local({
      body <- switch(
        service,
        BigQuery = '{"error":{"errors":[{"reason":"invalidQuery","message":"private-canary"}]}}',
        PostgREST = '{"code":"42P01","message":"private-canary","details":"secret"}',
        ClickHouse = "private-canary"
      )
      headers <- if (service == "ClickHouse") {
        list(
          "X-ClickHouse-Exception-Code" = "62",
          "X-ClickHouse-Query-Id" = request_id
        )
      } else {
        list("X-Request-Id" = request_id)
      }
      httr2::local_mocked_responses(function(req) {
        odb_http_response(body, 400L, headers)
      })
      odb_test_domain(function(session) {
        auth <- odb_test_authorization(session)
        api <- switch(
          service,
          BigQuery = oauth_db_bigquery_api(auth$connection, "billing"),
          PostgREST = oauth_db_postgrest_api(
            auth$connection,
            "https://data.example"
          ),
          ClickHouse = oauth_db_clickhouse_api(
            auth$connection,
            "https://data.example"
          )
        )
        operation <- function() {
          if (service == "PostgREST") {
            api$select("rows")
          } else {
            api$query("SELECT value")
          }
        }
        error <- expect_error(
          operation(),
          class = "shinyOAuthDB_request_failed"
        )
        expect_identical(error$status, 400L)
        expect_identical(
          error$service_code,
          switch(
            service,
            BigQuery = "invalidQuery",
            PostgREST = "42P01",
            ClickHouse = "62"
          )
        )
        expect_identical(error$request_id, request_id)
        expect_false(grepl(
          "private-canary|secret|fixture-A",
          conditionMessage(error)
        ))
        expect_null(error$parent)
        expect_null(error$resp)
        expect_null(error[["request"]])
      })
    })
  }
})

test_that("malformed diagnostic fields never replace the sanitized HTTP failure", {
  for (body in c(
    "not JSON",
    "null",
    "[]",
    '{"error":"private-canary"}',
    '{"error":{"errors":[{"reason":"private-canary"}]} }',
    '{"code":"private-canary"}',
    '{"code":["42P01","private-canary"]}'
  )) {
    for (service in c("BigQuery", "PostgREST", "ClickHouse")) {
      resp <- odb_http_response(
        body,
        400L,
        list(
          "X-Request-Id" = "private-canary",
          "X-ClickHouse-Exception-Code" = "private-canary"
        )
      )
      result <- .odb_http_diagnostics(resp, service, character())
      expect_null(result$service_code)
      expect_null(result$request_id)
    }
  }
})

test_that("diagnostics omit credentials from both attempts of a refreshed request", {
  for (backend in c("shared", "bigquery")) {
    local({
      previous <- "36cf6384-1189-4a47-8272-bf3a01fa3536"
      renewed <- "invalidQuery"
      requests <- 0L
      httr2::local_mocked_responses(function(req) {
        requests <<- requests + 1L
        odb_http_response(
          '{"error":{"errors":[{"reason":"invalidQuery"}]}}',
          401L,
          list("X-Request-Id" = previous)
        )
      })
      token <- function(force_refresh = FALSE, .check_only = FALSE) {
        if (force_refresh) renewed else previous
      }
      operation <- function() {
        if (backend == "shared") {
          .odb_http_request(
            token,
            httr2::request("https://data.example"),
            "BigQuery",
            10,
            retry_401 = TRUE
          )
        } else {
          .odb_bigquery_request(
            token,
            "GET",
            c("projects", "billing", "datasets"),
            .odb_bigquery_time() + 10
          )
        }
      }
      error <- expect_error(operation(), class = "shinyOAuthDB_request_failed")
      expect_identical(requests, 2L)
      expect_null(error$request_id)
      expect_null(error$service_code)
    })
  }
})

test_that("diagnostics skip oversized bodies and non-schema field aliases", {
  body <- paste0('{"code":"42P01","details":"', strrep("x", 65536), '"}')
  expect_null(
    .odb_http_diagnostics(
      odb_http_response(body, 400L),
      "PostgREST",
      character()
    )$service_code
  )
  body <- '{"codename":"42P01"}'
  expect_null(
    .odb_http_diagnostics(
      odb_http_response(body, 400L),
      "PostgREST",
      character()
    )$service_code
  )
})
