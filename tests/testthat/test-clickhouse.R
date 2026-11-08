clickhouse_test_result <- function() {
  list(
    meta = list(
      list(name = "user", type = "String"),
      list(name = "id", type = "UInt64")
    ),
    data = list(list("alice", "9007199254740993")),
    rows = 1L,
    statistics = list(elapsed = 0.01)
  )
}

clickhouse_test_response <- function() {
  odb_http_response(as.character(jsonlite::toJSON(
    clickhouse_test_result(),
    auto_unbox = TRUE
  )))
}

test_that("ClickHouse rejects malformed dates in all date wrappers and result modes", {
  body <- NULL
  httr2::local_mocked_responses(function(req) {
    odb_http_response(as.character(jsonlite::toJSON(
      body,
      auto_unbox = TRUE,
      null = "null"
    )))
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_clickhouse_api(
      auth$connection,
      "https://clickhouse.example"
    )
    operations <- list(
      function() api$query("SELECT day"),
      function() api$query("SELECT day", raw = TRUE),
      function() api$execute("SELECT day")
    )
    for (type in c(
      "Date",
      "Date32",
      "Nullable(Date)",
      "LowCardinality(Nullable(Date32))"
    )) {
      body <<- list(
        meta = list(list(name = "day", type = type)),
        data = list(list("2000-02-29"), list(NULL)),
        rows = 2L
      )
      expect_identical(
        api$query("SELECT day")$day,
        as.Date(c("2000-02-29", NA))
      )
      body$data <<- list()
      body$rows <<- 0L
      expect_identical(api$query("SELECT day")$day, as.Date(character()))
      for (invalid in c(
        "2026-02-30",
        "1900-02-29",
        "2026-02-01TRAILER",
        "2026-1-01",
        "PRIVATE_INVALID_DATE"
      )) {
        for (values in list(
          c("2026-01-01", invalid),
          c(invalid, "2026-01-01")
        )) {
          body$data <<- lapply(values, list)
          body$rows <<- 2L
          for (operation in operations) {
            error <- expect_error(
              operation(),
              class = "shinyOAuthDB_invalid_response"
            )
            expect_false(grepl(
              "PRIVATE_",
              conditionMessage(error),
              fixed = TRUE
            ))
            expect_null(error$parent)
          }
        }
      }
    }
  })
})

test_that("ClickHouse enforces signedness and width for small integer columns", {
  for (base in c("Int8", "UInt8", "Int16", "UInt16", "Int32", "UInt32")) {
    bits <- as.integer(sub("^U?Int", "", base))
    unsigned <- startsWith(base, "U")
    lower <- if (unsigned) 0 else -2^(bits - 1L)
    upper <- if (unsigned) 2^bits - 1 else 2^(bits - 1L) - 1
    for (type in c(
      base,
      paste0("Nullable(", base, ")"),
      paste0("LowCardinality(", base, ")"),
      paste0("LowCardinality(Nullable(", base, "))")
    )) {
      expect_identical(
        .odb_clickhouse_column(list(lower, upper, NULL), type),
        c(lower, upper, NA_real_)
      )
      expect_identical(.odb_clickhouse_column(list(), type), numeric())
      for (invalid in list(
        lower - 1,
        upper + 1,
        0.5,
        Inf,
        -Inf,
        NaN,
        "invalid"
      )) {
        expect_error(
          .odb_clickhouse_column(list(0, invalid), type),
          class = "shinyOAuthDB_invalid_response"
        )
      }
    }
  }
  for (type in c("Float32", "Float64", "Nullable(Float64)")) {
    expect_identical(
      .odb_clickhouse_column(list("-nan", "Inf", "-Infinity", NULL), type),
      c(NaN, Inf, -Inf, NA_real_)
    )
  }
})

test_that("ClickHouse validates integer cells in queries, raw results and statements", {
  body <- NULL
  httr2::local_mocked_responses(function(req) {
    odb_http_response(as.character(jsonlite::toJSON(
      body,
      auto_unbox = TRUE
    )))
  })
  odb_test_domain(function(session) {
    api <- oauth_db_clickhouse_api(
      odb_test_authorization(session)$connection,
      "https://clickhouse.example"
    )
    operations <- list(
      function() api$query("SELECT n"),
      function() api$query("SELECT n", raw = TRUE),
      function() api$execute("SELECT n")
    )
    for (case in list(
      list(type = "UInt8", value = -1),
      list(type = "Int8", value = 128),
      list(type = "Int32", value = 1.5),
      list(type = "UInt32", value = "Inf")
    )) {
      body <<- list(
        meta = list(list(
          name = "n",
          type = paste0("LowCardinality(Nullable(", case$type, "))")
        )),
        data = list(list(0), list(case$value)),
        rows = 2L
      )
      for (operation in operations) {
        expect_error(operation(), class = "shinyOAuthDB_invalid_response")
      }
    }
  })
})

test_that("ClickHouse sends SQL and parameters separately with per-user bearer authentication", {
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    clickhouse_test_response()
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_clickhouse_api(
      auth$connection,
      "https://clickhouse.example:8443",
      database = "reporting"
    )
    sql <- "SELECT user, id FROM orders WHERE country = {country:String}"
    result <- api$query(
      sql,
      parameters = list(country = "'; DROP TABLE orders; --")
    )
    expect_identical(result$id, "9007199254740993")
    expect_identical(result$user, "alice")
    a <- requests[[1L]]
    expect_identical(rawToChar(a$body$data), sql)
    query <- httr2::url_parse(a$url)$query
    expect_identical(query$param_country, "'; DROP TABLE orders; --")
    expect_identical(query$database, "reporting")
    expect_identical(query$default_format, "JSONCompact")
    expect_identical(query$wait_end_of_query, "1")
    expect_identical(query$output_format_json_quote_64bit_integers, "1")
    expect_identical(query$output_format_json_quote_decimals, "1")
    expect_identical(
      httr2::req_get_headers(a, redacted = "reveal")$Authorization,
      "Bearer fixture-A"
    )
    expect_false(a$options$followlocation)
    auth$token(auth$make_token("rotated-A"))
    raw <- api$query("SELECT user, id", raw = TRUE)
    expect_identical(raw$meta[[2L]]$type, "UInt64")
    expect_identical(
      httr2::req_get_headers(requests[[2L]], redacted = "reveal")$Authorization,
      "Bearer rotated-A"
    )
    expect_output(print(api), "OAuthClickHouseAPI")
  })
})

test_that("ClickHouse serializes native scalar parameters without SQL interpolation", {
  withr::local_options(OutDec = ",")
  values <- .odb_clickhouse_parameters(list(
    text = "one\tline\n\\N",
    missing = NULL,
    empty = NA_character_,
    exact = "18446744073709551615",
    decimal = 1.25,
    yes = TRUE,
    day = as.Date("2026-11-03"),
    at = as.POSIXct("2026-11-03 12:00:00", tz = "UTC")
  ))
  expect_identical(values$param_text, "one\\tline\\n\\\\N")
  expect_identical(values$param_missing, "\\N")
  expect_identical(values$param_empty, "\\N")
  expect_identical(values$param_exact, "18446744073709551615")
  expect_identical(values$param_decimal, "1.25")
  expect_identical(values$param_yes, "1")
  expect_identical(values$param_day, "2026-11-03")
  expect_identical(values$param_at, "2026-11-03 12:00:00")
  expect_identical(.odb_clickhouse_parameters(list()), list())
  expect_identical(
    .odb_clickhouse_parameters(list(values = I("['a\\\\b']")))$param_values,
    "['a\\\\b']"
  )
  expect_error(
    .odb_clickhouse_parameters(list(values = I(c("a", "b")))),
    "one non-missing"
  )
  expect_error(.odb_clickhouse_parameters(list(x = c(1L, 2L))), "scalar")
  expect_error(.odb_clickhouse_parameters(list(1L)), "nonempty")
  expect_error(
    .odb_clickhouse_parameters(list("x&user" = "bad")),
    "parameter name"
  )
})

test_that("ClickHouse timestamp parameters preserve fractions without adding them to whole seconds", {
  at <- as.POSIXct("2026-11-04 12:00:00", tz = "UTC")
  values <- .odb_clickhouse_parameters(list(
    whole = at,
    fractional = at + 0.125,
    missing = as.POSIXct(NA_real_, origin = "1970-01-01", tz = "UTC")
  ))
  expect_identical(values$param_whole, "2026-11-04 12:00:00")
  expect_identical(values$param_fractional, "2026-11-04 12:00:00.125")
  expect_identical(values$param_missing, "\\N")
})

test_that("ClickHouse converts the R display timezone to the documented UTC representation", {
  amsterdam <- as.POSIXct("2026-11-04 13:00:00", tz = "Europe/Amsterdam")
  utc <- as.POSIXct("2026-11-04 12:00:00", tz = "UTC")
  expect_identical(
    .odb_clickhouse_parameters(list(at = amsterdam)),
    .odb_clickhouse_parameters(list(at = utc))
  )
  expect_identical(
    .odb_clickhouse_parameters(list(at = amsterdam))$param_at,
    "2026-11-04 12:00:00"
  )
})

test_that("ClickHouse preserves exact and nested types and typed empty results", {
  names <- c(
    "id",
    "amount",
    "small",
    "float",
    "flag",
    "day",
    "time",
    "array",
    "tuple"
  )
  types <- c(
    "Nullable(UInt64)",
    "Decimal(38, 9)",
    "Int32",
    "Float64",
    "Bool",
    "Date32",
    "DateTime64(6, 'UTC')",
    "Array(Int64)",
    "Tuple(x String)"
  )
  meta <- Map(function(name, type) list(name = name, type = type), names, types)
  row <- list(
    "18446744073709551615",
    "123456789012345678.123456789",
    -2147483648,
    "+nan",
    TRUE,
    "2026-11-03",
    "2026-11-03 12:00:00.123456",
    list("1", "2"),
    list(x = "name")
  )
  value <- .odb_clickhouse_frame(list(
    meta = meta,
    data = list(row, rep(list(NULL), length(row))),
    rows = 2L
  ))
  expect_identical(value$id, c("18446744073709551615", NA_character_))
  expect_identical(value$amount[[1L]], "123456789012345678.123456789")
  expect_identical(value$small, c(-2147483648, NA_real_))
  expect_true(is.nan(value$float[[1L]]))
  expect_identical(value$flag, c(TRUE, NA))
  expect_s3_class(value$day, "Date")
  expect_identical(value$time[[1L]], "2026-11-03 12:00:00.123456")
  expect_identical(value$array, list(list("1", "2"), NULL))
  expect_identical(value$tuple, list(list(x = "name"), NULL))
  empty <- .odb_clickhouse_frame(list(meta = meta, data = list(), rows = 0L))
  expect_identical(dim(empty), c(0L, 9L))
  expect_s3_class(empty$day, "Date")
  expect_identical(empty$id, character())
  expect_error(
    .odb_clickhouse_frame(list(meta = meta, data = list(list(1)))),
    class = "shinyOAuthDB_invalid_response"
  )
  expect_error(
    .odb_clickhouse_frame(list(meta = meta, data = list(), rows = 1)),
    class = "shinyOAuthDB_invalid_response"
  )
  expect_error(
    .odb_clickhouse_column(list("bad"), "Int32"),
    class = "shinyOAuthDB_invalid_response"
  )
})

test_that("ClickHouse never replays SQL errors or returns partial results", {
  requests <- 0L
  payload <- ""
  status <- 200L
  headers <- list()
  httr2::local_mocked_responses(function(req) {
    requests <<- requests + 1L
    odb_http_response(payload, status, headers)
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, refresh_token = "fixture-refresh")
    api <- oauth_db_clickhouse_api(
      auth$connection,
      "https://clickhouse.example"
    )
    expect_s3_class(
      api$execute("CREATE TABLE example (id UInt64) ENGINE=Memory"),
      "httr2_response"
    )
    for (value in c(401L, 403L, 302L, 500L)) {
      status <<- value
      error <- tryCatch(
        api$execute("INSERT INTO example VALUES (1)"),
        error = identity
      )
      expect_s3_class(error, "shinyOAuthDB_request_failed")
      expect_identical(error$status, value)
    }
    expect_identical(requests, 5L)
    expect_identical(auth$calls$acquire, 0L)
    status <<- 200L
    payload <<- '{"meta":[],"data":[] __exception__ sensitive-response'
    expect_error(api$query("SELECT 1"), class = "shinyOAuthDB_invalid_response")
    headers <<- list("X-ClickHouse-Exception-Code" = "395")
    error <- tryCatch(api$query("SELECT 1"), error = identity)
    expect_s3_class(error, "shinyOAuthDB_query_failed")
    expect_false(grepl("sensitive-response|fixture-A", conditionMessage(error)))
  })
})

test_that("ClickHouse clients isolate accounts and discard late responses", {
  selected <- NULL
  revoke <- FALSE
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    if (revoke) {
      selected(NULL)
    }
    clickhouse_test_response()
  })
  retained <- NULL
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    b <- odb_test_authorization(session, id = "B")
    selected <<- shiny::reactiveVal(NULL)
    api <- oauth_db_clickhouse_api(selected, "https://clickhouse.example")
    expect_error(api$query("SELECT 1"), class = "shiny.silent.error")
    selected(a$connection)
    api$query("SELECT 1")
    selected(b$connection)
    api$query("SELECT 1")
    expect_identical(
      httr2::req_get_headers(requests[[2L]], redacted = "reveal")$Authorization,
      "Bearer fixture-B"
    )
    revoke <<- TRUE
    expect_error(
      api$query("SELECT 1"),
      class = "shinyOAuthDB_authorization_unavailable"
    )
    retained <<- api
  })
  odb_test_domain(function(session) {
    expect_error(
      retained$query("SELECT 1"),
      class = "shinyOAuthDB_authorization_unavailable"
    )
  })
})

test_that("ClickHouse raw queries and statements validate without constructing data frames", {
  payload <- clickhouse_test_result()
  local_mocked_bindings(.odb_clickhouse_frame = function(...) {
    stop("Unexpected data frame construction")
  })
  httr2::local_mocked_responses(function(req) {
    odb_http_response(as.character(jsonlite::toJSON(
      payload,
      auto_unbox = TRUE
    )))
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_clickhouse_api(
      auth$connection,
      "https://clickhouse.example"
    )
    expect_identical(
      api$query("SELECT user, id", raw = TRUE),
      .odb_http_json(clickhouse_test_response(), "ClickHouse")
    )
    expect_s3_class(api$execute("SELECT user, id"), "httr2_response")
    invalid <- list(
      list(
        meta = list(list(name = "n", type = "Int32")),
        data = list(list("invalid")),
        rows = 1L
      ),
      list(
        meta = list(list(name = "b", type = "Bool")),
        data = list(list("invalid")),
        rows = 1L
      ),
      list(
        meta = list(list(name = "d", type = "Date")),
        data = list(list("invalid")),
        rows = 1L
      ),
      list(meta = payload$meta, data = list(list("wrong width")), rows = 1L),
      list(meta = payload$meta, data = list(), rows = 1L)
    )
    for (value in invalid) {
      payload <<- value
      expect_error(
        api$query("SELECT value", raw = TRUE),
        class = "shinyOAuthDB_invalid_response"
      )
      expect_error(
        api$execute("SELECT value"),
        class = "shinyOAuthDB_invalid_response"
      )
    }
  })
})
