test_that("BigQuery rejects ambiguous parameter type maps before credentials or HTTP", {
  invalid <- list(
    c("STRING", "INT64"),
    stats::setNames(c("STRING", "INT64"), c("text", "")),
    stats::setNames(c("STRING", "INT64"), c("text", "text")),
    c(text = NA_character_),
    c(unknown = "INT64"),
    c(text = 42)
  )
  for (types in invalid) {
    local({
      requests <- 0L
      httr2::local_mocked_responses(function(req) {
        requests <<- requests + 1L
        bq_test_response(bq_test_result())
      })
      odb_test_domain(function(session) {
        auth <- odb_test_authorization(session)
        api <- oauth_db_bigquery_api(auth$connection, "billing")
        error <- tryCatch(
          api$query(
            "SELECT @text, @number",
            parameters = list(text = "one", number = 1L),
            parameter_types = types
          ),
          error = identity
        )
        expect_s3_class(error, "shinyOAuthDB_invalid_configuration")
        expect_identical(requests, 0L)
        expect_identical(auth$calls$acquire, 0L)
      })
    })
  }
})

test_that("BigQuery round-trips explicit DATETIME and TIME parameters without inference", {
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    bq_test_response(bq_test_result())
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_bigquery_api(auth$connection, "billing")
    api$query(
      "SELECT @daytime, @clock",
      parameters = list(
        daytime = "2020-02-29 12:34:56",
        clock = "12:34:56.123456"
      ),
      parameter_types = c(daytime = "DATETIME", clock = "TIME")
    )
    parameters <- requests[[1L]]$body$data$queryParameters
    expect_identical(parameters[[1L]]$parameterType$type, "DATETIME")
    expect_identical(
      parameters[[1L]]$parameterValue$value,
      "2020-02-29 12:34:56"
    )
    expect_identical(parameters[[2L]]$parameterType$type, "TIME")
    expect_identical(parameters[[2L]]$parameterValue$value, "12:34:56.123456")
    expect_length(requests, 1L)
  })
})

test_that("BigQuery timestamps retain UTC and STRUCT aliases retain named fields", {
  withr::local_timezone("Pacific/Auckland")
  value <- list(
    jobComplete = TRUE,
    jobReference = list(projectId = "billing", jobId = "types"),
    schema = list(
      fields = list(
        list(name = "instant", type = "TIMESTAMP"),
        list(
          name = "record",
          type = "STRUCT",
          fields = list(list(name = "id", type = "INT64"))
        )
      )
    ),
    rows = list(list(
      f = list(
        list(v = "0"),
        list(v = list(f = list(list(v = "9223372036854775807"))))
      )
    ))
  )
  httr2::local_mocked_responses(function(req) bq_test_response(value))
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_bigquery_api(auth$connection, "billing")
    rows <- api$query("SELECT instant, record")
    expect_s3_class(rows$instant, "POSIXct")
    expect_identical(attr(rows$instant, "tzone"), "UTC")
    expect_identical(as.numeric(rows$instant), 0)
    expect_identical(
      format(rows$instant, "%Y-%m-%d %H:%M:%S %z"),
      "1970-01-01 00:00:00 +0000"
    )
    expect_identical(rows$record, list(list(id = "9223372036854775807")))
  })
})
