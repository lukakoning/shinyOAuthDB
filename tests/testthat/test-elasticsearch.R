elasticsearch_response <- function() {
  '{"took":2,"timed_out":false,"_shards":{"total":1,"successful":1,"failed":0},"hits":{"total":{"value":1,"relation":"eq"},"hits":[{"_index":"orders","_id":"1","_source":{"id":9007199254740993,"tags":["a"],"missing":null}}]},"aggregations":{"countries":{"buckets":[{"key":"NL","doc_count":1}]}}}'
}

test_that("Elasticsearch searches preserve native results and authenticate both user and app", {
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    odb_http_response(elasticsearch_response())
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_elasticsearch_api(
      auth$connection,
      "https://search.example/proxy/",
      client_secret = "realm-secret",
      ca_bundle = "ca.pem"
    )
    expect_identical(auth$calls$acquire, 0L)
    body <- list(query = list(term = list(country = "NL")))
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
    expect_identical(requests[[1L]]$body$data, body)
    expect_s3_class(api$search(raw = TRUE), "httr2_response")
    expect_identical(
      as.character(jsonlite::toJSON(requests[[2L]]$body$data)),
      "{}"
    )
    expect_output(print(api), "<OAuthElasticsearchAPI>")
  })
  request <- requests[[1L]]
  expect_identical(
    utils::URLdecode(request$url),
    "https://search.example/proxy/orders-*,archive/_search?track_total_hits=true"
  )
  expect_identical(request$method, "POST")
  expect_false(request$options$followlocation)
  expect_true(request$options$fresh_connect)
  expect_true(request$options$forbid_reuse)
  expect_identical(request$options$cainfo, "ca.pem")
  headers <- httr2::req_get_headers(request, redacted = "reveal")
  expect_identical(headers$Authorization, "Bearer fixture-A")
  expect_identical(
    headers$`ES-Client-Authentication`,
    "SharedSecret realm-secret"
  )
  expect_false(grepl(
    "realm-secret|fixture-A",
    paste(capture.output(print(request)), collapse = "\n")
  ))
  expect_null(httr2::req_get_headers(request)$`ES-Client-Authentication`)
})

test_that("Elasticsearch SQL and ES|QL use their own protocols and bound parameter arrays", {
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    field <- if (grepl("/_sql", req$url, fixed = TRUE)) "rows" else "values"
    odb_http_response(paste0(
      '{"columns":[{"name":"id","type":"long"},{"name":"tags","type":"keyword"}],"',
      field,
      '":[[9007199254740993,["a","b"]]],"cursor":"page-2"}'
    ))
  })
  odb_test_domain(function(session) {
    auth <- odb_test_response_authorization()
    api <- oauth_db_elasticsearch_api(auth$connection, "https://search.example")
    parameters <- list("NL'; DROP INDEX orders; --", 42L, TRUE, NULL)
    result <- api$sql("SELECT * FROM orders WHERE country = ?", parameters)
    expect_identical(result$rows[[1L]][[1L]], "9007199254740993")
    expect_identical(result$rows[[1L]][[2L]], list("a", "b"))
    expect_identical(result$cursor, "page-2")
    expect_identical(requests[[1L]]$body$data$params, parameters)
    expect_identical(
      requests[[1L]]$body$data$query,
      "SELECT * FROM orders WHERE country = ?"
    )
    encoded <- as.character(jsonlite::toJSON(
      requests[[1L]]$body$data,
      auto_unbox = TRUE,
      null = "null"
    ))
    expect_match(encoded, '"params":\\[')
    expect_match(encoded, ',42,true,null\\]')
    result <- api$esql(
      "FROM orders | WHERE country == ? | LIMIT 10",
      list("NL")
    )
    expect_identical(result$values[[1L]][[1L]], "9007199254740993")
    expect_identical(requests[[2L]]$body$data$params, list("NL"))
    expect_s3_class(
      api$sql("SELECT * FROM orders", raw = TRUE),
      "httr2_response"
    )
    expect_s3_class(api$esql("FROM orders", raw = TRUE), "httr2_response")
    expect_named(requests[[3L]]$body$data, "query")
    expect_null(
      httr2::req_get_headers(requests[[1L]])$`ES-Client-Authentication`
    )
  })
  expect_identical(
    requests[[1L]]$url,
    "https://search.example/_sql?format=json"
  )
  expect_identical(
    requests[[2L]]$url,
    "https://search.example/_query?format=json"
  )
})

test_that("Elasticsearch refreshes safe reads once without replaying queries or writes", {
  requests <- list()
  status <- 401L
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    odb_http_response("PRIVATE_BODY realm-secret", status)
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, refresh_token = "fixture-refresh")
    api <- oauth_db_elasticsearch_api(
      auth$connection,
      "https://search.example",
      "realm-secret"
    )
    failure <- expect_error(
      api$request(c("_security", "_authenticate")),
      class = "shinyOAuthDB_request_failed"
    )
    expect_identical(failure$status, 401L)
    expect_identical(auth$calls$acquire, 1L)
    expect_identical(
      httr2::req_get_headers(requests[[2L]], redacted = "reveal")$Authorization,
      "Bearer fixture-A-acquired"
    )
    expect_identical(
      httr2::req_get_headers(
        requests[[2L]],
        redacted = "reveal"
      )$`ES-Client-Authentication`,
      "SharedSecret realm-secret"
    )
    expect_false(grepl("PRIVATE_BODY|realm-secret", conditionMessage(failure)))
    expect_null(failure$parent)
    for (operation in list(
      function() api$search("orders"),
      function() api$sql("SELECT * FROM orders"),
      function() api$esql("FROM orders"),
      function() {
        api$request(c("orders", "_doc", "1"), "PUT", body = list(total = 1))
      },
      function() api$request(c("orders", "_doc", "1"), "DELETE")
    )) {
      before <- length(requests)
      expect_error(operation(), class = "shinyOAuthDB_request_failed")
      expect_length(requests, before + 1L)
    }
    for (code in c(403L, 429L, 503L, 302L)) {
      status <<- code
      before <- length(requests)
      error <- expect_error(
        api$request("orders"),
        class = "shinyOAuthDB_request_failed"
      )
      expect_identical(error$status, code)
      expect_length(requests, before + 1L)
    }
    expect_identical(auth$calls$acquire, 1L)
  })
})

test_that("Elasticsearch keeps authorization targets, accounts and sessions separate", {
  current <- requests <- saved <- NULL
  during <- function() NULL
  httr2::local_mocked_responses(function(req) {
    current <<- httr2::req_get_headers(req, redacted = "reveal")$Authorization
    requests <<- c(requests, current)
    during()
    odb_http_response(elasticsearch_response())
  })
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session, target = "search", scopes = "read")
    b <- odb_test_authorization(
      session,
      id = "B",
      target = "search",
      scopes = "read"
    )
    selected <- shiny::reactiveVal(NULL)
    api <- oauth_db_elasticsearch_api(
      selected,
      "https://search.example",
      target = "search",
      required_scopes = "https://example.invalid/api/read"
    )
    expect_error(api$search(), class = "shiny.silent.error")
    expect_null(requests)
    selected(a$connection)
    api$search()
    expect_identical(current, "Bearer fixture-A")
    a$token(a$make_token("renewed-A"))
    api$search()
    expect_identical(current, "Bearer renewed-A")
    during <<- function() selected(b$connection)
    expect_error(api$search(), class = "shinyOAuthDB_authorization_unavailable")
    during <<- function() NULL
    api$search()
    expect_identical(current, "Bearer fixture-B")
    b$token(b$make_token("denied", permissions = character()))
    before <- length(requests)
    expect_error(api$search(), class = "shiny.silent.error")
    expect_length(requests, before)
    b$token(b$make_token("fixture-B"))
    during <<- function() selected(NULL)
    expect_error(api$search(), class = "shinyOAuthDB_authorization_unavailable")
    during <<- function() NULL
    expect_error(api$search(), class = "shiny.silent.error")
    saved <<- api
  })
  odb_test_domain(function(session) {
    expect_error(
      saved$search(),
      class = "shinyOAuthDB_authorization_unavailable"
    )
  })
})

test_that("Elasticsearch rejects partial and malformed results while allowing raw inspection", {
  payload <- "{}"
  httr2::local_mocked_responses(function(req) odb_http_response(payload))
  odb_test_domain(function(session) {
    auth <- odb_test_response_authorization()
    api <- oauth_db_elasticsearch_api(auth$connection, "https://search.example")
    for (metadata in c(
      '"timed_out":true',
      '"_shards":{"failed":1}',
      '"_clusters":{"failed":1}',
      '"_clusters":{"partial":1}',
      '"is_partial":true',
      '"is_running":true',
      '"error":{"reason":"PRIVATE"}'
    )) {
      payload <<- paste0('{"hits":{"hits":[]},', metadata, '}')
      failure <- expect_error(api$search(), class = "shinyOAuthDB_query_failed")
      expect_false(grepl("PRIVATE", conditionMessage(failure)))
      expect_s3_class(api$search(raw = TRUE), "httr2_response")
    }
    for (value in c(
      "[]",
      "{}",
      '{"hits":{"hits":{}}}',
      '{"hits":{"hits":[]},"timed_out":"true"}',
      '{"hits":{"hits":[]},"_shards":{"failed":-1}}',
      '{"hits":{"hits":[]},"_clusters":42}'
    )) {
      payload <<- value
      expect_error(api$search(), class = "shinyOAuthDB_invalid_response")
    }
    payload <<- '{"hits":{"hits":[]},"_shards":{"failed":0}}'
    expect_identical(api$search()$hits$hits, list())
    for (kind in c("sql", "esql")) {
      field <- if (kind == "sql") "rows" else "values"
      for (metadata in c(
        '"is_partial":true',
        '"is_running":true',
        '"_clusters":{"skipped":1}'
      )) {
        payload <<- paste0('{"columns":[],"', field, '":[],', metadata, '}')
        expect_error(api[[kind]]("query"), class = "shinyOAuthDB_query_failed")
        expect_s3_class(api[[kind]]("query", raw = TRUE), "httr2_response")
      }
      for (value in c(
        "{}",
        paste0('{"columns":[],"', field, '":null}'),
        paste0('{"columns":[42],"', field, '":[[1]]}'),
        paste0('{"columns":[],"', field, '":[[1]]}')
      )) {
        payload <<- value
        expect_error(
          api[[kind]]("query"),
          class = "shinyOAuthDB_invalid_response"
        )
      }
      payload <<- paste0('{"columns":[],"', field, '":[]}')
      expect_identical(api[[kind]]("query")[[field]], list())
    }
  })
})

test_that("Elasticsearch rejects skipped remote clusters but permits prefiltered shards", {
  payload <- paste0(
    '{"timed_out":false,"_shards":{"total":2,"successful":2,"skipped":1,"failed":0},',
    '"_clusters":{"total":2,"successful":1,"skipped":1,"running":0,"partial":0,"failed":0},',
    '"hits":{"hits":[{"_id":"local-row"}]},"aggregations":{"sales":{"value":25}}}'
  )
  httr2::local_mocked_responses(function(req) odb_http_response(payload))
  odb_test_domain(function(session) {
    auth <- odb_test_response_authorization()
    api <- oauth_db_elasticsearch_api(auth$connection, "https://search.example")
    expect_error(
      api$search(c("orders", "remote:orders")),
      class = "shinyOAuthDB_query_failed"
    )
    raw <- api$search(c("orders", "remote:orders"), raw = TRUE)
    expect_identical(
      .odb_http_json(raw, "Elasticsearch")[["_clusters"]]$skipped,
      1L
    )
    payload <<- sub(
      '"skipped":1,"running"',
      '"skipped":0,"running"',
      payload,
      fixed = TRUE
    )
    expect_identical(api$search()$hits$hits[[1L]][["_id"]], "local-row")
    for (skipped in c("-1", "0.5", '"unknown"')) {
      payload <<- sub(
        '"skipped":[^,]+,"running"',
        paste0('"skipped":', skipped, ',"running"'),
        payload
      )
      expect_error(api$search(), class = "shinyOAuthDB_invalid_response")
    }
  })
})

test_that("Elasticsearch rejects unsafe configuration before authorization and network work", {
  for (url in c(
    "http://search.example",
    "https://user:pass@search.example",
    "https://search.example?jwt=x",
    "https://search.example/#x",
    "https://search.example/%2e%2e/other"
  )) {
    expect_error(
      oauth_db_elasticsearch_api(stop("stay lazy"), url),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  for (secret in list(
    "",
    NA_character_,
    c("a", "b"),
    "secret\r\ninjected: header"
  )) {
    expect_error(
      oauth_db_elasticsearch_api(
        stop("stay lazy"),
        "https://search.example",
        secret
      ),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  expect_error(
    oauth_db_elasticsearch_api(
      stop("stay lazy"),
      "https://search.example",
      timeout = 0
    ),
    class = "shinyOAuthDB_invalid_configuration"
  )
  odb_test_domain(function(session) {
    api <- oauth_db_elasticsearch_api(
      function() stop("stay lazy"),
      "https://search.example"
    )
    for (index in list(character(), NA_character_, "a/b", "..", 42)) {
      expect_error(
        api$search(index),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
    for (path in list("..", "a/b", "https://evil.example", c("orders", ".."))) {
      expect_error(
        api$request(path),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
    for (key in c(
      "Authorization",
      "access_token",
      "client_secret",
      "ES-Client-Authentication",
      "api_key"
    )) {
      expect_error(
        api$request("orders", query = stats::setNames(list("override"), key)),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
    expect_error(api$request("orders", method = "TRACE"), "Unsupported")
    expect_error(
      api$request("orders", body = list(query = 1)),
      "cannot have a body"
    )
    expect_error(api$search(body = list(1)), "nonempty")
    expect_error(api$search(raw = NA), "raw must")
    for (parameters in list(
      list(named = 1),
      list(NA),
      list(NaN),
      list(Inf),
      list(as.Date("2026-01-01")),
      list(c(1, 2)),
      list(list(type = "long", value = 1))
    )) {
      expect_error(
        api$sql("SELECT ?", parameters),
        class = "shinyOAuthDB_invalid_configuration"
      )
      expect_error(
        api$esql("ROW value = ?", parameters),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
  })
})

test_that("Elasticsearch native requests support cursors and keep realm secrets out of diagnostics", {
  requests <- list()
  response <- odb_http_response('{"rows":[[1]],"cursor":"next"}')
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    response
  })
  odb_test_domain(function(session) {
    auth <- odb_test_response_authorization()
    secret <- "15e2b56b-357e-4f1d-9424-8291f07e030d"
    api <- oauth_db_elasticsearch_api(
      auth$connection,
      "https://search.example",
      secret
    )
    expect_identical(
      api$request("_sql", "POST", body = list(cursor = "first"))$cursor,
      "next"
    )
    expect_identical(requests[[1L]]$body$data, list(cursor = "first"))
    response <<- odb_http_response('{"succeeded":true}')
    expect_true(
      api$request(
        c("_sql", "close"),
        "POST",
        body = list(cursor = "next")
      )$succeeded
    )
    response <<- odb_http_response("", 204L)
    expect_null(api$request(c("orders", "_doc", "1"), "DELETE"))
    expect_s3_class(api$request("orders", "HEAD"), "httr2_response")
    response <<- odb_http_response(
      "PRIVATE",
      403L,
      list("X-Request-Id" = secret)
    )
    failure <- expect_error(api$search(), class = "shinyOAuthDB_request_failed")
    expect_null(failure$request_id)
    expect_false(grepl(
      secret,
      paste(capture.output(str(failure)), collapse = "\n"),
      fixed = TRUE
    ))
    response <<- odb_http_response("not JSON")
    expect_error(api$search(), class = "shinyOAuthDB_invalid_response")
  })
})
