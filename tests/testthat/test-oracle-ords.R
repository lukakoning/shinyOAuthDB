test_that("ORDS preserves collection pages and sends user credentials only to the configured endpoint", {
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    odb_http_response(
      '{"items":[{"id":9007199254740993,"amount":"123456789.12"}],"hasMore":true,"offset":20,"limit":10,"links":[{"rel":"next","href":"https://elsewhere.example/private"}]}'
    )
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_oracle_ords_api(
      auth$connection,
      "https://data.example/proxy/ords/reports/",
      ca_bundle = "ca.pem"
    )
    page <- api$select(
      "orders",
      query = list(limit = 10L, offset = 20L, q = '{"country":"NL"}')
    )
    expect_identical(page$items[[1L]]$id, "9007199254740993")
    expect_identical(page$items[[1L]]$amount, "123456789.12")
    expect_true(page$hasMore)
    expect_identical(page$links[[1L]]$href, "https://elsewhere.example/private")
    expect_length(requests, 1L)
    expect_match(
      requests[[1L]]$url,
      "/proxy/ords/reports/orders/\\?",
      perl = TRUE
    )
    expect_identical(httr2::url_parse(requests[[1L]]$url)$query$offset, "20")
    expect_identical(
      httr2::req_get_headers(requests[[1L]], redacted = "reveal")$Authorization,
      "Bearer fixture-A"
    )
    expect_false(requests[[1L]]$options$followlocation)
    expect_identical(requests[[1L]]$options$cainfo, "ca.pem")
    raw <- api$request(c("api", "sales"), raw = TRUE)
    expect_s3_class(raw, "httr2_response")
    expect_match(requests[[2L]]$url, "/api/sales$", perl = TRUE)
    expect_output(print(api), "OAuthOracleORDSAPI")
  })
})

test_that("ORDS refreshes safe reads once and never replays writes", {
  requests <- list()
  fail <- TRUE
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    if (length(requests) == 2L || !fail) {
      odb_http_response('{"items":[],"hasMore":false}')
    } else {
      odb_http_response("PRIVATE_BODY", 401L)
    }
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, refresh_token = "fixture-refresh")
    api <- oauth_db_oracle_ords_api(
      auth$connection,
      "https://data.example/ords/reports"
    )
    expect_identical(api$select("orders")$items, list())
    expect_identical(auth$calls$acquire, 1L)
    expect_identical(
      httr2::req_get_headers(requests[[2L]], redacted = "reveal")$Authorization,
      "Bearer fixture-A-acquired"
    )
    for (method in c("POST", "PUT", "PATCH", "DELETE")) {
      error <- expect_error(
        api$request(c("api", "update"), method, body = list(total = 3L)),
        class = "shinyOAuthDB_request_failed"
      )
      expect_false(grepl("PRIVATE_BODY|fixture", conditionMessage(error)))
    }
    expect_identical(auth$calls$acquire, 1L)
    expect_length(requests, 6L)
    expect_identical(requests[[3L]]$body$data$total, 3L)
    expect_true(requests[[3L]]$options$fresh_connect)
    expect_true(requests[[3L]]$options$forbid_reuse)
  })
})

test_that("ORDS obtains current tokens and rejects stale and cross-session responses", {
  selected <- retained <- NULL
  retire <- FALSE
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    if (retire) {
      selected(NULL)
    }
    odb_http_response('{"items":[],"hasMore":false}')
  })
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    b <- odb_test_authorization(session, id = "B")
    selected <<- shiny::reactiveVal(NULL)
    api <- oauth_db_oracle_ords_api(
      selected,
      "https://data.example/ords/reports",
      required_scopes = "read"
    )
    expect_error(api$select("orders"), class = "shiny.silent.error")
    selected(a$connection)
    api$select("orders")
    a$token(a$make_token("renewed-A"))
    api$select("orders")
    selected(b$connection)
    api$select("orders")
    b$token(b$make_token("denied-B", permissions = "write"))
    expect_error(api$select("orders"), class = "shiny.silent.error")
    b$token(b$make_token("fixture-B"))
    retire <<- TRUE
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
      "Bearer renewed-A",
      "Bearer fixture-B",
      "Bearer fixture-B"
    )
  )
})

test_that("ORDS validates routes and preserves HTTP failure boundaries", {
  for (url in c(
    "http://data.example",
    "https://user:secret@data.example",
    "https://data.example?token=secret",
    "https://data.example/a/../b"
  )) {
    expect_error(
      oauth_db_oracle_ords_api(function() NULL, url),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  status <- 200L
  body <- "not-json"
  requests <- 0L
  httr2::local_mocked_responses(function(req) {
    requests <<- requests + 1L
    odb_http_response(body, status)
  })
  odb_test_domain(function(session) {
    auth <- odb_test_response_authorization()
    api <- oauth_db_oracle_ords_api(
      auth$connection,
      "https://data.example/ords/reports"
    )
    for (path in list(
      "../orders",
      "https://elsewhere.example",
      "..",
      c("api", "a/b")
    )) {
      expect_error(
        api$request(path),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
    expect_error(
      api$request("orders", query = list(access_token = "secret")),
      class = "shinyOAuthDB_invalid_configuration"
    )
    expect_error(
      api$request("orders", body = list(id = 1)),
      "cannot have a body"
    )
    expect_error(api$request("orders", method = "TRACE"), "Unsupported")
    expect_error(api$request("orders", trailing_slash = NA), "TRUE or FALSE")
    expect_identical(requests, 0L)
    expect_error(api$select("orders"), class = "shinyOAuthDB_invalid_response")
    for (value in c(
      '{}',
      '{"items":[],"hasMore":"false"}',
      '{"items":{},"hasMore":false}'
    )) {
      body <<- value
      expect_error(
        api$select("orders"),
        class = "shinyOAuthDB_invalid_response"
      )
      expect_s3_class(api$select("orders", raw = TRUE), "httr2_response")
    }
    for (value in c(302L, 403L, 500L)) {
      status <<- value
      expect_error(api$select("orders"), class = "shinyOAuthDB_request_failed")
    }
    status <<- 204L
    body <<- ""
    expect_null(api$request("orders", "DELETE"))
    expect_s3_class(api$request("orders", "HEAD"), "httr2_response")
  })
})
