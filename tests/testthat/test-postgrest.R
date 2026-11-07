test_that("PostgREST sends native filters and schema headers and preserves JSON values", {
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    odb_http_response(
      '[{"id":9007199254740993,"amount":"123456789012345678.12","country":"NL","tags":["a","b"],"missing":null}]',
      headers = list("Content-Range" = "0-0/3")
    )
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_postgrest_api(
      auth$connection,
      "https://data.example/rest/v1/",
      schema = "reports",
      ca_bundle = "ca.pem"
    )
    result <- api$select(
      "orders",
      select = "id,amount,country,tags,missing",
      filters = list(country = "eq.NL", or = "(id.eq.1,id.eq.2)"),
      order = "id.asc",
      limit = 1,
      offset = 2,
      count = "exact"
    )
    expect_s3_class(result, "data.frame")
    expect_identical(result$id, "9007199254740993")
    expect_identical(result$amount, "123456789012345678.12")
    expect_identical(result$tags[[1L]], c("a", "b"))
    raw <- api$select("orders", count = "planned", raw = TRUE)
    expect_equal(httr2::resp_header(raw, "Content-Range"), "0-0/3")
    expect_output(print(api), "OAuthPostgRESTAPI")
  })
  query <- httr2::url_parse(requests[[1L]]$url)$query
  expect_identical(query$country, "eq.NL")
  expect_identical(query$or, "(id.eq.1,id.eq.2)")
  expect_identical(query$limit, "1")
  expect_identical(query$offset, "2")
  headers <- httr2::req_get_headers(requests[[1L]], redacted = "reveal")
  expect_identical(headers$Authorization, "Bearer fixture-A")
  expect_identical(headers[["Accept-Profile"]], "reports")
  expect_identical(headers$Prefer, "count=exact")
  expect_false(requests[[1L]]$options$followlocation)
  expect_identical(requests[[1L]]$options$cainfo, "ca.pem")
})

test_that("PostgREST RPC and native writes preserve arguments and never retry mutations", {
  requests <- list()
  fail <- FALSE
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    if (fail) {
      odb_http_response('{"message":"sensitive-response"}', 401L)
    } else {
      odb_http_response("3")
    }
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, refresh_token = "fixture-refresh")
    api <- oauth_db_postgrest_api(
      auth$connection,
      "https://data.example",
      schema = "reports"
    )
    expect_equal(api$rpc("add_them", list(a = 1L, b = 2L)), 3)
    expect_equal(api$rpc("no_arguments"), 3)
    expect_identical(
      as.character(jsonlite::toJSON(requests[[2L]]$body$data)),
      "{}"
    )
    fail <<- TRUE
    for (method in c("POST", "PUT", "PATCH", "DELETE")) {
      expect_error(
        api$request("orders", method = method, body = list(id = 1L)),
        class = "shinyOAuthDB_request_failed"
      )
    }
    expect_identical(auth$calls$acquire, 0L)
  })
  expect_length(requests, 6L)
  expect_identical(requests[[1L]]$body$data, list(a = 1L, b = 2L))
  expect_identical(
    httr2::req_get_headers(requests[[1L]])[["Content-Profile"]],
    "reports"
  )
  expect_match(requests[[1L]]$url, "/rpc/add_them$", perl = TRUE)
})

test_that("PostgREST refreshes reads once and reports failures without response secrets", {
  requests <- list()
  status <- 401L
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    if (length(requests) == 2L) {
      odb_http_response("[]")
    } else {
      odb_http_response("sensitive-response", status)
    }
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, refresh_token = "fixture-refresh")
    api <- oauth_db_postgrest_api(auth$connection, "https://data.example")
    expect_identical(api$select("orders"), data.frame())
    expect_identical(auth$calls$acquire, 1L)
    expect_identical(
      httr2::req_get_headers(requests[[2L]], redacted = "reveal")$Authorization,
      "Bearer fixture-A-acquired"
    )
    for (value in c(401L, 403L, 302L, 500L)) {
      status <<- value
      error <- tryCatch(api$select("orders"), error = identity)
      expect_s3_class(error, "shinyOAuthDB_request_failed")
      expect_identical(error$status, value)
      expect_false(grepl("fixture|sensitive-response", conditionMessage(error)))
    }
  })
  expect_length(requests, 7L)
})

test_that("PostgREST uses fresh tokens and rejects late or cross-session results", {
  selected <- NULL
  switch <- FALSE
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    if (switch) {
      selected(NULL)
    }
    odb_http_response('[{"value":"ok"}]')
  })
  retained <- NULL
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session, id = "A")
    b <- odb_test_authorization(session, id = "B")
    selected <<- shiny::reactiveVal(NULL)
    api <- oauth_db_postgrest_api(selected, "https://data.example")
    expect_error(api$select("orders"), class = "shiny.silent.error")
    selected(a$connection)
    expect_identical(api$select("orders")$value, "ok")
    a$token(a$make_token("rotated-A"))
    api$select("orders")
    selected(b$connection)
    api$select("orders")
    switch <<- TRUE
    expect_error(
      api$select("orders"),
      class = "shinyOAuthDB_authorization_unavailable"
    )
    retained <<- api
  })
  odb_test_domain(function(session) {
    expect_error(
      retained$select("orders"),
      class = "shinyOAuthDB_authorization_unavailable"
    )
  })
  expect_identical(
    vapply(
      requests,
      function(req) {
        httr2::req_get_headers(req, redacted = "reveal")$Authorization
      },
      ""
    ),
    c(
      "Bearer fixture-A",
      "Bearer rotated-A",
      "Bearer fixture-B",
      "Bearer fixture-B"
    )
  )
})

test_that("PostgREST validates endpoints, paths, arguments, and malformed results", {
  for (url in c(
    "http://data.example",
    "https://user:pass@data.example",
    "https://data.example?x=1",
    "https://data.example/#secret",
    "https://data.example/a/../b",
    "https://data.example/%2e%2e/b"
  )) {
    expect_error(
      oauth_db_postgrest_api(function() NULL, url),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  payload <- "not-json"
  httr2::local_mocked_responses(function(req) odb_http_response(payload))
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_postgrest_api(auth$connection, "https://data.example")
    expect_error(api$select("orders"), class = "shinyOAuthDB_invalid_response")
    payload <<- "17"
    expect_error(api$select("orders"), class = "shinyOAuthDB_invalid_response")
    for (path in list(
      "../orders",
      "https://elsewhere.example",
      "..",
      c("rpc", "a/b")
    )) {
      expect_error(
        api$request(path),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
    expect_error(api$select("orders", limit = -1), "limit")
    expect_error(api$select("orders", filters = list(limit = 2)), "arguments")
    expect_error(
      api$select("orders", filters = list(id = c("eq.1", "eq.2"))),
      "query value"
    )
    expect_error(
      api$request(
        "orders",
        prefer = "return=representation\r\nHost: elsewhere"
      ),
      "control"
    )
    expect_error(
      api$request("orders", body = list(x = 1)),
      "cannot have a body"
    )
    expect_error(api$rpc("f", list(1)), "nonempty")
  })
})

test_that("PostgREST accepts successful writes with no representation", {
  httr2::local_mocked_responses(function(req) odb_http_response("", 204L))
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_postgrest_api(auth$connection, "https://data.example")
    expect_null(api$request("orders", method = "PATCH", body = list(total = 1)))
  })
})

test_that("PostgREST distinguishes empty table arrays from objects and RPC values", {
  payload <- "[]"
  httr2::local_mocked_responses(function(req) odb_http_response(payload))
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_postgrest_api(auth$connection, "https://data.example")
    expect_identical(api$select("orders"), data.frame())
    for (body in c("{}", "null", "[1,2]", '{"private":"response-canary"}')) {
      payload <<- body
      error <- expect_error(
        api$select("orders"),
        class = "shinyOAuthDB_invalid_response"
      )
      expect_false(grepl(
        "response-canary",
        conditionMessage(error),
        fixed = TRUE
      ))
      expect_null(error$parent)
    }
    payload <<- "{}"
    expect_identical(
      api$rpc("empty_object"),
      stats::setNames(list(), character())
    )
    expect_s3_class(api$select("orders", raw = TRUE), "httr2_response")
    payload <<- "42"
    expect_equal(api$rpc("scalar"), 42)
    payload <<- '[{"id":null,"children":[]}]'
    rows <- api$select("orders")
    expect_equal(nrow(rows), 1)
    expect_true(is.na(rows$id))
  })
})
