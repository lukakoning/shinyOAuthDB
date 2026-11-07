cratedb_test_response <- function() {
  odb_http_response(paste0(
    '{"cols":["user","id","amount","n","flag","items","at"],',
    '"col_types":[4,10,22,9,3,[100,10],11],"rows":[["alice",9223372036854775807,',
    '123456789012345678.123456789,42,true,[9007199254740993],1700000000123]],"rowcount":1,"duration":1.25}'
  ))
}

test_that("CrateDB separates SQL and positional arguments and preserves exact results", {
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    cratedb_test_response()
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_cratedb_api(
      auth$connection,
      "https://crate.example:4200/proxy/_sql",
      schema = "reporting"
    )
    result <- api$query(
      "SELECT * FROM orders WHERE country = $1",
      list("'; DROP TABLE orders; --")
    )
    expect_identical(result$id, "9223372036854775807")
    expect_identical(result$amount, "123456789012345678.123456789")
    expect_identical(result$n, 42)
    expect_identical(result$flag, TRUE)
    expect_identical(result$items, list(list("9007199254740993")))
    expect_identical(result$at, "1700000000123")
    req <- requests[[1L]]
    expect_identical(
      req$body$data$stmt,
      "SELECT * FROM orders WHERE country = $1"
    )
    expect_identical(req$body$data$args, list("'; DROP TABLE orders; --"))
    expect_identical(httr2::url_parse(req$url)$query$types, "true")
    headers <- httr2::req_get_headers(req, redacted = "reveal")
    expect_identical(headers$Authorization, "Bearer fixture-A")
    expect_identical(headers[["Default-Schema"]], "reporting")
    expect_false(req$options$followlocation)
    auth$token(auth$make_token("rotated"))
    raw <- api$query("SELECT 1", raw = TRUE)
    expect_identical(raw$col_types[[2L]], 10L)
    expect_identical(raw$rowcount, 1)
    expect_identical(
      httr2::req_get_headers(requests[[2L]], redacted = "reveal")$Authorization,
      "Bearer rotated"
    )
    expect_output(print(api), "OAuthCrateDBAPI")
  })
})

test_that("CrateDB handles nested parameters and rejects ambiguous or lossy values before requests", {
  values <- .odb_cratedb_parameters(list(
    "9007199254740993",
    TRUE,
    NA_real_,
    NULL,
    c(1, 2),
    list(x = "hello", y = list(FALSE, NULL)),
    as.Date("2026-11-06"),
    as.POSIXct("2026-11-06 13:00:00.125", tz = "Europe/Amsterdam")
  ))
  expect_identical(
    values[1:6],
    list(
      "9007199254740993",
      TRUE,
      NULL,
      NULL,
      list(1, 2),
      list(x = "hello", y = list(FALSE, NULL))
    )
  )
  expect_identical(values[[7L]], "2026-11-06")
  expect_identical(values[[8L]], "2026-11-06T12:00:00.125000Z")
  expect_identical(.odb_cratedb_parameters(list()), list())
  for (value in list(list(id = 1), 1, NULL)) {
    expect_error(.odb_cratedb_parameters(value), "unnamed list")
  }
  for (value in list(
    Inf,
    -Inf,
    NaN,
    factor("a"),
    1 + 2i,
    as.raw(1),
    matrix(1),
    list(x = 1, x = 2),
    stats::setNames(list(1), "")
  )) {
    expect_error(
      .odb_cratedb_parameters(list(value)),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  requests <- 0L
  httr2::local_mocked_responses(function(req) {
    requests <<- requests + 1L
    cratedb_test_response()
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_cratedb_api(auth$connection, "https://crate.example/_sql")
    expect_error(api$query("SELECT $1", list(Inf)), "finite")
    expect_identical(requests, 0L)
  })
  for (url in c(
    "http://crate.example/_sql",
    "https://user:password@crate.example/_sql",
    "https://crate.example/_sql?token=bad",
    "https://crate.example/../_sql"
  )) {
    expect_error(
      oauth_db_cratedb_api(NULL, url),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  expect_error(
    oauth_db_cratedb_api(
      NULL,
      "https://crate.example/_sql",
      schema = "doc\r\nAuthorization: bad"
    ),
    "control"
  )
})

test_that("CrateDB validates complete results, numeric lexemes and typed empty frames", {
  json <- '{"cols":["x","x","text","obj"],"col_types":[10,22,4,12],"rows":[[-9223372036854775808,1.234567890123456789e-20,"123 \\\"456\\\" café",{"id":9007199254740993}],[null,null,null,null]],"rowcount":2}'
  result <- .odb_cratedb_result(odb_http_response(json))
  frame <- .odb_cratedb_frame(result)
  expect_identical(names(frame), c("x", "x", "text", "obj"))
  expect_identical(frame[[1L]], c("-9223372036854775808", NA_character_))
  expect_identical(frame[[2L]], c("1.234567890123456789e-20", NA_character_))
  expect_identical(frame$text, c('123 "456" café', NA_character_))
  expect_identical(frame$obj, list(list(id = "9007199254740993"), NULL))
  empty <- .odb_cratedb_frame(.odb_cratedb_result(odb_http_response(
    '{"cols":["b","n","a","t"],"col_types":[3,9,[100,4],4],"rows":[],"rowcount":0}'
  )))
  expect_identical(empty$b, logical())
  expect_identical(empty$n, numeric())
  expect_identical(empty$a, list())
  expect_identical(empty$t, character())
  malformed <- c(
    '{bad',
    '[]',
    '{"cols":[],"rows":[],"rowcount":0}',
    '{"cols":["x"],"col_types":[],"rows":[],"rowcount":0}',
    '{"cols":["x"],"col_types":[9],"rows":[[]],"rowcount":1}',
    '{"cols":["x"],"col_types":[9],"rows":[[1]],"rowcount":2}',
    '{"cols":["x"],"col_types":[3],"rows":[["true"]],"rowcount":1}',
    '{"cols":["x"],"col_types":[10],"rows":[["invalid"]],"rowcount":1}',
    '{"cols":["x"],"col_types":[9],"rows":[[{}]],"rowcount":1}',
    '{"cols":["x"],"col_types":[[100]],"rows":[],"rowcount":0}'
  )
  for (json in malformed) {
    expect_error(
      .odb_cratedb_result(odb_http_response(json)),
      class = "shinyOAuthDB_invalid_response"
    )
  }
})

test_that("CrateDB never replays statements or exposes server messages on failure", {
  requests <- 0L
  response <- odb_http_response(
    '{"cols":[],"col_types":[],"rows":[],"rowcount":3}'
  )
  httr2::local_mocked_responses(function(req) {
    requests <<- requests + 1L
    response
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, refresh_token = "fixture-refresh")
    api <- oauth_db_cratedb_api(auth$connection, "https://crate.example/_sql")
    expect_identical(api$execute("UPDATE orders SET n = n + 1"), 3)
    for (status in c(401L, 403L, 302L, 503L)) {
      response <<- odb_http_response(
        '{"error":{"message":"fixture-A sensitive SQL"}}',
        status
      )
      error <- tryCatch(
        api$execute("UPDATE orders SET n = n + 1"),
        error = identity
      )
      expect_s3_class(error, "shinyOAuthDB_request_failed")
      expect_identical(error$status, status)
      expect_false(grepl("fixture-A|sensitive SQL", conditionMessage(error)))
    }
    response <<- odb_http_response(
      '{"error":{"message":"fixture-A sensitive SQL"}}'
    )
    expect_error(
      api$query("SELECT 1", raw = TRUE),
      class = "shinyOAuthDB_query_failed"
    )
    expect_identical(requests, 6L)
    expect_identical(auth$calls$acquire, 0L)
  })
})

test_that("CrateDB follows selected accounts and targets, checks permissions and discards late results", {
  selected <- NULL
  revoke <- FALSE
  headers <- character()
  httr2::local_mocked_responses(function(req) {
    headers <<- c(
      headers,
      httr2::req_get_headers(req, redacted = "reveal")$Authorization
    )
    if (revoke) {
      selected(NULL)
    }
    cratedb_test_response()
  })
  retained <- NULL
  odb_test_domain(function(session) {
    a <- odb_test_authorization(
      session,
      target = "analytics",
      scopes = "read",
      refresh_token = "refresh"
    )
    b <- odb_test_authorization(
      session,
      id = "B",
      target = "analytics",
      scopes = "read"
    )
    selected <<- shiny::reactiveVal(NULL)
    api <- oauth_db_cratedb_api(
      selected,
      "https://crate.example/_sql",
      target = "analytics",
      required_scopes = a$scopes
    )
    expect_error(api$query("SELECT 1"), class = "shiny.silent.error")
    expect_length(headers, 0L)
    selected(a$connection)
    a$token(a$make_token("expired", lifetime = 0))
    api$query("SELECT 1")
    expect_identical(a$calls$acquire, 1L)
    selected(b$connection)
    api$query("SELECT 1")
    expect_identical(
      headers,
      c("Bearer fixture-A-acquired", "Bearer fixture-B")
    )
    b$token(b$make_token("denied", character()))
    expect_error(api$query("SELECT 1"), class = "shiny.silent.error")
    expect_length(headers, 2L)
    b$token(b$make_token("restored"))
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
