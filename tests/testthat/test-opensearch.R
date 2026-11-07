opensearch_response <- function() {
  '{"took":2,"timed_out":false,"_shards":{"total":1,"successful":1,"failed":0},"hits":{"total":{"value":1,"relation":"eq"},"hits":[{"_index":"orders","_id":"1","_score":null,"_source":{"id":9007199254740993,"tags":["a"],"missing":null}}]},"aggregations":{"countries":{"buckets":[{"key":"NL","doc_count":1}]}}}'
}

test_that("OpenSearch preserves search metadata, nested documents and exact integers", {
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    odb_http_response(opensearch_response())
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_opensearch_api(
      auth$connection,
      "https://search.example/proxy/",
      ca_bundle = "ca.pem"
    )
    body <- list(
      size = 20L,
      query = list(term = list(country = "NL")),
      aggs = list(countries = list(terms = list(field = "country")))
    )
    result <- api$search(
      c("orders-*", "archive"),
      body,
      query = list(track_total_hits = TRUE)
    )
    expect_identical(result$hits$hits[[1L]]$`_source`$id, "9007199254740993")
    expect_identical(result$hits$hits[[1L]]$`_source`$tags, list("a"))
    expect_null(result$hits$hits[[1L]]$`_source`$missing)
    expect_equal(result$aggregations$countries$buckets[[1L]]$doc_count, 1)
    expect_identical(result$hits$total$relation, "eq")
    expect_equal(result$took, 2)
    expect_s3_class(api$search(raw = TRUE), "httr2_response")
    expect_identical(
      as.character(jsonlite::toJSON(requests[[2L]]$body$data)),
      "{}"
    )
    expect_output(print(api), "<OAuthOpenSearchAPI>")
    expect_identical(requests[[1L]]$body$data, body)
  })
  expect_match(
    requests[[1L]]$url,
    "/proxy/orders-%2A%2Carchive/_search\\?track_total_hits=true$"
  )
  expect_identical(requests[[1L]]$method, "POST")
  expect_false(requests[[1L]]$options$followlocation)
  expect_identical(requests[[1L]]$options$cainfo, "ca.pem")
  expect_identical(
    httr2::req_get_headers(requests[[1L]], redacted = "reveal")$Authorization,
    "Bearer fixture-A"
  )
})

test_that("OpenSearch SQL uses native typed parameters without interpolation", {
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    odb_http_response(
      '{"schema":[{"name":"id","type":"long"}],"datarows":[[9007199254740993]],"total":1,"size":1,"status":200,"cursor":"native-cursor"}'
    )
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_opensearch_api(auth$connection, "https://search.example")
    parameters <- list(list(
      type = "keyword",
      value = "NL'; DROP INDEX orders; --"
    ))
    sql <- "SELECT id FROM orders WHERE country = ?"
    result <- api$sql(sql, parameters)
    expect_identical(result$datarows[[1L]][[1L]], "9007199254740993")
    expect_identical(result$schema[[1L]]$type, "long")
    expect_identical(result$cursor, "native-cursor")
    expect_identical(
      requests[[1L]]$body$data,
      list(query = sql, parameters = parameters)
    )
    expect_match(
      as.character(jsonlite::toJSON(
        requests[[1L]]$body$data,
        auto_unbox = TRUE
      )),
      '"parameters":\\[\\{'
    )
    expect_s3_class(
      api$sql("SELECT * FROM orders", raw = TRUE),
      "httr2_response"
    )
    expect_identical(
      requests[[2L]]$body$data,
      list(query = "SELECT * FROM orders")
    )
  })
  expect_match(requests[[1L]]$url, "/_plugins/_sql\\?format=jdbc$")
})

test_that("OpenSearch renews GET once and never replays POSTs or writes", {
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    odb_http_response("private-body", 401L)
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, refresh_token = "fixture-refresh")
    api <- oauth_db_opensearch_api(auth$connection, "https://search.example")
    error <- expect_error(
      api$request(c("_plugins", "_security", "authinfo")),
      class = "shinyOAuthDB_request_failed"
    )
    expect_identical(error$status, 401L)
    expect_identical(auth$calls$acquire, 1L)
    expect_identical(
      httr2::req_get_headers(requests[[2L]], redacted = "reveal")$Authorization,
      "Bearer fixture-A-acquired"
    )
    expect_error(api$search("orders"), class = "shinyOAuthDB_request_failed")
    expect_error(
      api$sql("SELECT * FROM orders"),
      class = "shinyOAuthDB_request_failed"
    )
    for (method in c("POST", "PUT", "PATCH", "DELETE")) {
      expect_error(
        api$request(c("orders", "_doc", "1"), method, body = list(id = 1L)),
        class = "shinyOAuthDB_request_failed"
      )
    }
    expect_identical(auth$calls$acquire, 1L)
    expect_false(grepl("private-body|fixture-", conditionMessage(error)))
    expect_null(error$parent)
  })
  expect_length(requests, 8L)
  expect_identical(
    vapply(
      requests,
      function(req) if (is.null(req$method)) "GET" else req$method,
      ""
    ),
    c("GET", "GET", "POST", "POST", "POST", "PUT", "PATCH", "DELETE")
  )
})

test_that("OpenSearch follows accounts and targets, rejects stale results and ends access", {
  requests <- list()
  selected <- auth <- NULL
  action <- function() NULL
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    action()
    odb_http_response(opensearch_response())
  })
  saved <- NULL
  odb_test_domain(function(session) {
    auth <<- odb_test_authorization(
      session,
      target = "search",
      scopes = "read",
      refresh_token = "refresh"
    )
    b <- odb_test_authorization(
      session,
      id = "B",
      target = "search",
      scopes = "read"
    )
    selected <<- shiny::reactiveVal(NULL)
    api <- oauth_db_opensearch_api(
      selected,
      "https://search.example",
      target = "search",
      required_scopes = auth$scopes
    )
    expect_error(api$search(), class = "shiny.silent.error")
    expect_length(requests, 0L)
    selected(auth$connection)
    api$search()
    auth$token(auth$make_token("expired", lifetime = 0))
    api$search()
    expect_identical(auth$calls$acquire, 1L)
    selected(b$connection)
    api$search()
    b$token(b$make_token("denied", character()))
    expect_error(api$search(), class = "shiny.silent.error")
    b$token(b$make_token("restored"))
    action <<- function() selected(auth$connection)
    expect_error(api$search(), class = "shinyOAuthDB_authorization_unavailable")
    action <<- function() selected(NULL)
    expect_error(api$search(), class = "shinyOAuthDB_authorization_unavailable")
    saved <<- api
  })
  odb_test_domain(function(session) {
    expect_error(
      saved$search(),
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
      "Bearer fixture-A-acquired",
      "Bearer fixture-B",
      "Bearer restored",
      "Bearer fixture-A-acquired"
    )
  )
})

test_that("OpenSearch rejects incomplete and malformed query results without exposing data", {
  payload <- "not-json"
  httr2::local_mocked_responses(function(req) odb_http_response(payload))
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_opensearch_api(auth$connection, "https://search.example")
    for (value in c(
      "not-json",
      "null",
      "[]",
      "42",
      '"private-response"',
      "{}",
      '{"hits":null}'
    )) {
      payload <<- value
      expect_error(api$search(), class = "shinyOAuthDB_invalid_response")
    }
    for (value in c(
      '{"error":{"reason":"private-response"}}',
      '{"timed_out":true,"hits":{"hits":[]}}',
      '{"_shards":{"failed":1},"hits":{"hits":[]}}'
    )) {
      payload <<- value
      failure <- expect_error(api$search(), class = "shinyOAuthDB_query_failed")
      expect_false(grepl("private-response", conditionMessage(failure)))
      expect_null(failure$parent)
      expect_s3_class(api$search(raw = TRUE), "httr2_response")
    }
    payload <<- '{"hits":{"hits":[]},"timed_out":false,"_shards":{"failed":0}}'
    expect_identical(api$search()$hits$hits, list())
    for (metadata in c(
      '"timed_out":"true"',
      '"_shards":42',
      '"_shards":{"failed":-1}',
      '"_shards":{"failed":"private-response"}'
    )) {
      payload <<- paste0('{"hits":{"hits":[]},', metadata, '}')
      expect_error(api$search(), class = "shinyOAuthDB_invalid_response")
    }
    payload <<- '{"schema":[],"datarows":[]}'
    expect_identical(api$sql("SELECT * FROM orders")$datarows, list())
    for (value in c(
      "{}",
      '{"schema":[],"datarows":null}',
      '{"schema":1,"datarows":[]}'
    )) {
      payload <<- value
      expect_error(
        api$sql("SELECT * FROM orders"),
        class = "shinyOAuthDB_invalid_response"
      )
    }
  })
})

test_that("OpenSearch validates native destinations and options before requests", {
  for (url in c(
    "http://search.example",
    "https://user:password@search.example",
    "https://search.example?jwt=x",
    "https://search.example/#fragment",
    "https://search.example/%2e%2e/elsewhere"
  )) {
    expect_error(
      oauth_db_opensearch_api(function() NULL, url),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  expect_error(
    oauth_db_opensearch_api(
      stop("must stay lazy"),
      "https://search.example",
      timeout = 0
    ),
    class = "shinyOAuthDB_invalid_configuration"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_opensearch_api(auth$connection, "https://search.example")
    for (path in list("..", "a/b", "https://evil.example", c("orders", ".."))) {
      expect_error(
        api$request(path),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
    for (index in list(character(), c("orders", NA), "a/b", "..", 1)) {
      expect_error(
        api$search(index),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
    expect_error(api$search(body = list(1)), "nonempty")
    expect_error(
      api$request("orders", query = list(jwt = "override")),
      "cannot be overridden"
    )
    expect_error(api$request("orders", method = "TRACE"), "Unsupported")
    expect_error(
      api$request("orders", body = list(id = 1L)),
      "cannot have a body"
    )
    expect_error(
      api$request("orders", query = list(size = c(1, 2))),
      "query value"
    )
    expect_error(api$search(raw = NA), "raw must")
    for (parameters in list(
      list(x = 1),
      list(30),
      list(list(type = "integer")),
      list(list(type = "", value = 1)),
      list(list(type = "integer", value = c(1, 2)))
    )) {
      expect_error(
        api$sql("SELECT ?", parameters),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
  })
})

test_that("OpenSearch native requests preserve empty responses and error diagnostics", {
  response <- odb_http_response("", 204L)
  httr2::local_mocked_responses(function(req) response)
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_opensearch_api(auth$connection, "https://search.example")
    expect_null(api$request(c("orders", "_doc", "1"), "DELETE"))
    expect_s3_class(api$request("orders", "HEAD"), "httr2_response")
    response <<- odb_http_response('[{"index":"orders"}]')
    expect_identical(
      api$request(c("_cat", "indices"), query = list(format = "json")),
      list(list(index = "orders"))
    )
    response <<- odb_http_response(
      '{"errors":false,"error_count":0,"error":{"mappings":{}}}'
    )
    native <- api$request("_mapping")
    expect_false(native$errors)
    expect_equal(native$error_count, 0)
    expect_named(native$error, "mappings")
    response <<- odb_http_response(
      "{\"private\":\"sensitive\"}",
      403L,
      list("X-Request-Id" = "15e2b56b-357e-4f1d-9424-8291f07e030d")
    )
    failure <- expect_error(api$search(), class = "shinyOAuthDB_request_failed")
    expect_identical(failure$status, 403L)
    expect_identical(failure$request_id, "15e2b56b-357e-4f1d-9424-8291f07e030d")
    expect_false(grepl("sensitive", conditionMessage(failure)))
  })
})
