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

test_that("BigQuery rejects invalid scalars in ordinary, repeated and nested fields", {
  payload <- function(type, value, shape) {
    field <- list(name = "value", type = type)
    cell <- list(v = value)
    if (grepl("repeated", shape, fixed = TRUE)) {
      field$mode <- "REPEATED"
      cell <- list(v = list(cell))
    }
    if (startsWith(shape, "record")) {
      field <- list(name = "record", type = "RECORD", fields = list(field))
      cell <- list(v = list(f = list(cell)))
    }
    result <- bq_test_result("fixture")
    result$schema <- list(fields = list(field))
    result$rows <- list(list(f = list(cell)))
    result
  }
  invalid <- list(
    list(type = "BOOL", value = "PRIVATE_INVALID_BOOLEAN"),
    list(type = "BOOLEAN", value = "1"),
    list(type = "BOOL", value = list("true")),
    list(type = "FLOAT64", value = "PRIVATE_INVALID_NUMBER"),
    list(type = "FLOAT", value = "1e400"),
    list(type = "FLOAT64", value = "0x10"),
    list(type = "FLOAT64", value = ""),
    list(type = "TIMESTAMP", value = "PRIVATE_INVALID_TIMESTAMP"),
    list(type = "TIMESTAMP", value = "NaN"),
    list(type = "TIMESTAMP", value = "Infinity"),
    list(type = "TIMESTAMP", value = "-Inf"),
    list(type = "TIMESTAMP", value = "1e400"),
    list(type = "DATE", value = "PRIVATE_INVALID_DATE"),
    list(type = "DATE", value = "2026-02-01TRAILER"),
    list(type = "DATE", value = "2026-02-30"),
    list(type = "DATE", value = "1900-02-29"),
    list(type = "DATE", value = "2026-1-01")
  )
  body <- NULL
  httr2::local_mocked_responses(function(req) bq_test_response(body))
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_bigquery_api(auth$connection, "billing")
    for (case in invalid) {
      for (shape in c("scalar", "repeated", "record", "record-repeated")) {
        body <<- payload(case$type, case$value, shape)
        error <- expect_error(
          api$query("SELECT value"),
          class = "shinyOAuthDB_invalid_response"
        )
        expect_false(grepl("PRIVATE_", conditionMessage(error), fixed = TRUE))
        expect_null(error$parent)
      }
    }
  })
})

test_that("BigQuery rejects invalid dates after valid rows as well as before them", {
  body <- NULL
  httr2::local_mocked_responses(function(req) bq_test_response(body))
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_bigquery_api(auth$connection, "billing")
    for (invalid in c(
      "2026-02-30",
      "2026-02-01TRAILER",
      "PRIVATE_INVALID_DATE"
    )) {
      for (values in list(c("2026-01-01", invalid), c(invalid, "2026-01-01"))) {
        body <<- bq_test_result(values)
        body$schema <<- list(fields = list(list(name = "day", type = "DATE")))
        expect_error(
          api$query("SELECT day"),
          class = "shinyOAuthDB_invalid_response"
        )
      }
    }
  })
})

test_that("BigQuery scalar decoding preserves NULL, dates, NaN, infinities and empty types", {
  body <- NULL
  httr2::local_mocked_responses(function(req) bq_test_response(body))
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_bigquery_api(auth$connection, "billing")
    for (type in c(
      "DATE",
      "BOOL",
      "BOOLEAN",
      "FLOAT",
      "FLOAT64",
      "TIMESTAMP"
    )) {
      if (type == "DATE") {
        values <- list("0001-01-01", "2000-02-29", "9999-12-31", NULL)
        expected <- as.Date(
          c("0001-01-01", "2000-02-29", "9999-12-31", NA),
          format = "%Y-%m-%d"
        )
      } else if (type %in% c("BOOL", "BOOLEAN")) {
        values <- list("true", "FALSE", NULL)
        expected <- c(TRUE, FALSE, NA)
      } else if (type == "TIMESTAMP") {
        values <- list("0", "-1.25", "1700000000.125", NULL)
        expected <- as.POSIXct(
          c(0, -1.25, 1700000000.125, NA),
          origin = "1970-01-01",
          tz = "UTC"
        )
      } else {
        values <- list("0", "-1.25e2", "NaN", "Infinity", "-Infinity", NULL)
        expected <- c(0, -125, NaN, Inf, -Inf, NA_real_)
      }
      body <<- bq_test_result(rep("fixture", length(values)))
      body$schema <<- list(fields = list(list(name = "value", type = type)))
      body$rows <<- lapply(values, function(value) {
        list(f = list(list(v = value)))
      })
      expect_identical(api$query("SELECT value")$value, expected)
      body$rows <<- list()
      body$totalRows <<- "0"
      expect_identical(
        api$query("SELECT value WHERE FALSE")$value,
        expected[0L]
      )
    }
  })
})
