cosmos_response <- function(documents = "[]", count = 0L, headers = list()) {
  odb_http_response(
    paste0('{"Documents":', documents, ',"_count":', count, '}'),
    headers = headers
  )
}

cosmos_test_api <- function(authorization, ...) {
  oauth_db_cosmos_api(
    authorization,
    "https://account.documents.azure.com",
    "reports",
    "orders",
    target = NULL,
    ...
  )
}

test_that("Cosmos queries use encoded Entra authorization and the native query protocol", {
  requests <- list()
  sent <- NULL
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    sent <<- jsonlite::parse_json(getFromNamespace("req_body_render", "httr2")(
      req
    ))
    cosmos_response('[{"id":"one","amount":1.2345678901234567}]', 1L)
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    auth$token(auth$make_token("user+/token=="))
    api <- oauth_db_cosmos_api(
      auth$connection,
      "https://account.documents.azure.com:443/",
      "report space",
      "order%data",
      target = NULL,
      page_size = 20L,
      ca_bundle = "fixture.pem"
    )
    result <- api$query(
      "SELECT c.id, c.amount FROM c WHERE c.country = @country AND c.total > @min",
      list(country = "'; DROP TABLE c; --", min = 1.2345678901234567)
    )
    expect_identical(result$id, "one")
    expect_identical(result$amount, 1.2345678901234567)
    expect_output(print(api), "OAuthCosmosAPI")
  })
  expect_length(requests, 1L)
  req <- requests[[1L]]
  expect_identical(
    req$url,
    "https://account.documents.azure.com:443/dbs/report%20space/colls/order%25data/docs"
  )
  headers <- httr2::req_get_headers(req, redacted = "reveal")
  expect_identical(
    headers$Authorization,
    "type%3Daad%26ver%3D1.0%26sig%3Duser%2B%2Ftoken%3D%3D"
  )
  expect_false(any(grepl(
    "user",
    unlist(httr2::req_get_headers(req)),
    fixed = TRUE
  )))
  expect_identical(headers[["Content-Type"]], "application/query+json")
  expect_identical(headers[["x-ms-documentdb-isquery"]], "True")
  expect_identical(
    headers[["x-ms-documentdb-query-enablecrosspartition"]],
    "True"
  )
  expect_identical(headers[["x-ms-max-item-count"]], "20")
  expect_identical(headers[["x-ms-version"]], "2020-07-15")
  expect_match(
    headers[["x-ms-date"]],
    "^[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} GMT$"
  )
  expect_null(headers[["x-ms-documentdb-partitionkey"]])
  expect_false(req$options$followlocation)
  expect_true(req$options$fresh_connect)
  expect_identical(req$options$cainfo, "fixture.pem")
  expect_identical(sent$query, req$body$data$query)
  expect_identical(
    sent$parameters,
    list(
      list(name = "@country", value = "'; DROP TABLE c; --"),
      list(name = "@min", value = 1.2345678901234567)
    )
  )
})

test_that("Cosmos pagination crosses empty pages with current tokens and session consistency", {
  requests <- list()
  auth <- NULL
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    if (length(requests) == 1L) {
      auth$token(auth$make_token("renewed"))
      cosmos_response(
        headers = list(
          "x-ms-continuation" = 'opaque+/="cursor"',
          "x-ms-session-token" = "0:-1#10",
          "x-ms-request-charge" = "1.5"
        )
      )
    } else {
      cosmos_response(
        '[{"id":"second","n":9007199254740993}]',
        1L,
        headers = list(
          "x-ms-request-charge" = "2.5",
          "x-ms-session-token" = "0:-1#11"
        )
      )
    }
  })
  odb_test_domain(function(session) {
    auth <<- odb_test_authorization(session)
    api <- cosmos_test_api(auth$connection)
    result <- api$query("SELECT * FROM c", partition_key = "NL", raw = TRUE)
    expect_identical(
      result$documents,
      list(list(id = "second", n = "9007199254740993"))
    )
    expect_identical(result$request_charge, 4)
    expect_null(result$continuation)
    expect_identical(result$session_token, "0:-1#11")
  })
  expect_length(requests, 2L)
  headers <- lapply(requests, httr2::req_get_headers, redacted = "reveal")
  expect_identical(
    utils::URLdecode(headers[[2L]]$Authorization),
    "type=aad&ver=1.0&sig=renewed"
  )
  expect_identical(headers[[2L]][["x-ms-continuation"]], 'opaque+/="cursor"')
  expect_identical(headers[[2L]][["x-ms-session-token"]], "0:-1#10")
  expect_identical(headers[[2L]][["x-ms-documentdb-partitionkey"]], '["NL"]')
  expect_identical(
    headers[[2L]][["x-ms-documentdb-query-enablecrosspartition"]],
    "False"
  )
  expect_identical(requests[[1L]]$body$data, requests[[2L]]$body$data)
})

test_that("Cosmos pages, point reads and partition keys preserve native JSON values", {
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    if (httr2::req_get_method(req) == "GET") {
      return(odb_http_response('{"id":"one","nested":{"x":null}}'))
    }
    cosmos_response(
      '[null,1,{"x":[1,2]}]',
      3L,
      headers = list("x-ms-continuation" = "next")
    )
  })
  odb_test_domain(function(session) {
    api <- cosmos_test_api(
      odb_test_authorization(session)$connection,
      page_size = -1L
    )
    result <- api$query_page(
      "SELECT VALUE c.x FROM c",
      partition_key = list("NL", 1, NULL),
      continuation = "previous",
      session_token = "0:1"
    )
    expect_identical(result$documents, list(NULL, 1L, list(x = list(1L, 2L))))
    expect_identical(result$continuation, "next")
    expect_identical(result$request_charge, NA_real_)
    expect_identical(
      api$read("order space", list(NULL)),
      list(id = "one", nested = list(x = NULL))
    )
  })
  headers <- httr2::req_get_headers(requests[[1L]])
  expect_identical(headers[["x-ms-documentdb-partitionkey"]], '["NL",1,null]')
  expect_identical(headers[["x-ms-continuation"]], "previous")
  expect_identical(headers[["x-ms-session-token"]], "0:1")
  expect_identical(headers[["x-ms-max-item-count"]], "-1")
  expect_identical(
    httr2::req_get_headers(requests[[2L]])[["x-ms-documentdb-partitionkey"]],
    "[null]"
  )
  expect_match(requests[[2L]]$url, "/docs/order%20space$", perl = TRUE)
})

test_that("Cosmos object projections retain heterogeneous fields and scalar values", {
  response <- cosmos_response(
    paste0(
      '[{"id":"one","n":1,"flag":true,"nested":{"x":1},"array":[],"allnull":null,"mixed":1},',
      '{"id":"two","n":2.5,"flag":null,"nested":null,"array":[1],"mixed":"two"},',
      '{"id":"three","onlyhere":"yes"}]'
    ),
    3L
  )
  httr2::local_mocked_responses(function(req) response)
  odb_test_domain(function(session) {
    api <- cosmos_test_api(odb_test_authorization(session)$connection)
    result <- api$query("SELECT * FROM c")
    expect_identical(result$n, c(1, 2.5, NA_real_))
    expect_identical(result$flag, c(TRUE, NA, NA))
    expect_identical(result$nested, list(list(x = 1L), NULL, NULL))
    expect_identical(result$array, list(list(), list(1L), NULL))
    expect_identical(result$allnull, rep(NA, 3L))
    expect_identical(result$mixed, list(1L, "two", NULL))
    expect_identical(result$onlyhere, c(NA_character_, NA_character_, "yes"))
    response <<- cosmos_response("[null,1,{},[]]", 4L)
    expect_identical(
      api$query("SELECT VALUE c.x FROM c")$value,
      list(NULL, 1L, structure(list(), names = character()), list())
    )
    response <<- cosmos_response()
    expect_identical(api$query("SELECT * FROM c"), data.frame())
    response <<- cosmos_response("[{},{}]", 2L)
    expect_equal(nrow(api$query("SELECT * FROM c")), 2L)
  })
})

test_that("Cosmos parameters encode null, arrays, objects, dates and precise doubles", {
  sent <- NULL
  httr2::local_mocked_responses(function(req) {
    sent <<- jsonlite::parse_json(getFromNamespace("req_body_render", "httr2")(
      req
    ))
    cosmos_response()
  })
  odb_test_domain(function(session) {
    api <- cosmos_test_api(odb_test_authorization(session)$connection)
    api$query(
      "SELECT * FROM c",
      list(
        empty = NULL,
        array = c(1, 2),
        object = list(x = NULL, flag = TRUE),
        date = as.Date("2026-11-09"),
        time = as.POSIXct("2026-11-09 12:00:00", tz = "UTC"),
        number = 1.0000000000000002
      )
    )
    values <- lapply(sent$parameters, `[[`, "value")
    expect_identical(
      values,
      list(
        NULL,
        list(1L, 2L),
        list(x = NULL, flag = TRUE),
        "2026-11-09",
        "2026-11-09T12:00:00.000000Z",
        1.0000000000000002
      )
    )
    api$query("SELECT * FROM c")
    expect_identical(sent$parameters, list())
  })
})

test_that("Cosmos operations stay with their starting account and reject retired clients", {
  selected <- auth <- NULL
  mode <- "ok"
  requests <- 0L
  httr2::local_mocked_responses(function(req) {
    requests <<- requests + 1L
    if (mode == "switch") {
      selected(auth$connection)
    }
    if (mode == "logout") {
      selected(NULL)
    }
    if (mode == "close") {
      session_ref$close()
    }
    cosmos_response('[{"id":"ok"}]', 1L)
  })
  retained <- session_ref <- NULL
  odb_test_domain(function(session) {
    session_ref <<- session
    a <- odb_test_authorization(session)
    auth <<- odb_test_authorization(session, id = "B")
    selected <<- shiny::reactiveVal(NULL)
    api <- cosmos_test_api(selected)
    expect_error(api$query("SELECT * FROM c"), class = "shiny.silent.error")
    expect_identical(requests, 0L)
    selected(a$connection)
    expect_identical(api$query("SELECT * FROM c")$id, "ok")
    mode <<- "switch"
    expect_error(
      api$query("SELECT * FROM c"),
      class = "shinyOAuthDB_authorization_unavailable"
    )
    mode <<- "logout"
    expect_error(
      api$query("SELECT * FROM c"),
      class = "shinyOAuthDB_authorization_unavailable"
    )
    retained <<- api
  })
  odb_test_domain(function(session) {
    expect_error(
      retained$query("SELECT * FROM c"),
      class = "shinyOAuthDB_authorization_unavailable"
    )
  })
})

test_that("Cosmos applies one deadline to a query and discards results after session end", {
  clock <- 0
  requests <- list()
  local_mocked_bindings(.odb_http_time = function() clock)
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    clock <<- clock + 3
    cosmos_response(headers = list("x-ms-continuation" = "next"))
  })
  odb_test_domain(function(session) {
    api <- cosmos_test_api(
      odb_test_authorization(session)$connection,
      timeout = 5
    )
    expect_error(api$query("SELECT * FROM c"), class = "shinyOAuthDB_timeout")
  })
  expect_length(requests, 2L)
  expect_true(
    requests[[2L]]$options$timeout_ms < requests[[1L]]$options$timeout_ms
  )

  session_ref <- NULL
  httr2::local_mocked_responses(function(req) {
    session_ref$close()
    cosmos_response()
  })
  odb_test_domain(function(session) {
    session_ref <<- session
    api <- cosmos_test_api(odb_test_authorization(session)$connection)
    expect_error(
      api$query("SELECT * FROM c"),
      class = "shinyOAuthDB_authorization_unavailable"
    )
  })
})

test_that("Cosmos keeps independent sessions, targets and permission requirements separate", {
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    cosmos_response()
  })
  sessions <- list(shiny::MockShinySession$new(), shiny::MockShinySession$new())
  on.exit(lapply(sessions, function(session) session$close()), add = TRUE)
  clients <- lapply(seq_along(sessions), function(index) {
    shiny::withReactiveDomain(
      sessions[[index]],
      shiny::isolate({
        auth <- odb_test_authorization(
          sessions[[index]],
          id = as.character(index)
        )
        list(
          auth = auth,
          api = cosmos_test_api(auth$connection, required_scopes = "read")
        )
      })
    )
  })
  for (index in seq_along(sessions)) {
    shiny::withReactiveDomain(
      sessions[[index]],
      shiny::isolate({
        expect_identical(
          clients[[index]]$api$query("SELECT * FROM c"),
          data.frame()
        )
        other <- 3L - index
        expect_error(
          clients[[other]]$api$query("SELECT * FROM c"),
          class = "shinyOAuthDB_authorization_unavailable"
        )
        clients[[index]]$auth$token(clients[[index]]$auth$make_token(
          "lost",
          permissions = character()
        ))
        expect_error(
          clients[[index]]$api$query("SELECT * FROM c"),
          class = "shiny.silent.error"
        )
      })
    )
  }
  expect_length(requests, 2L)
  expect_identical(
    vapply(
      requests,
      function(req) {
        utils::URLdecode(
          httr2::req_get_headers(req, redacted = "reveal")$Authorization
        )
      },
      ""
    ),
    c("type=aad&ver=1.0&sig=fixture-1", "type=aad&ver=1.0&sig=fixture-2")
  )
})

test_that("Cosmos reads refresh once after 401 and fail closed on all other errors", {
  requests <- list()
  status <- 401L
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    if (length(requests) == 2L) {
      return(cosmos_response())
    }
    odb_http_response('{"message":"private-response fixture-A"}', status)
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, refresh_token = "fixture-refresh")
    api <- cosmos_test_api(auth$connection)
    expect_identical(api$query("SELECT * FROM c"), data.frame())
    expect_identical(auth$calls$acquire, 1L)
    expect_identical(
      utils::URLdecode(
        httr2::req_get_headers(
          requests[[2L]],
          redacted = "reveal"
        )$Authorization
      ),
      "type=aad&ver=1.0&sig=fixture-A-acquired"
    )
    for (code in c(403L, 429L, 500L, 302L)) {
      status <<- code
      error <- tryCatch(api$query("SELECT * FROM c"), error = identity)
      expect_s3_class(error, "shinyOAuthDB_request_failed")
      expect_identical(error$status, code)
      expect_false(grepl("private-response|fixture-A", conditionMessage(error)))
    }
    status <<- 401L
    expect_error(
      api$query("SELECT * FROM c"),
      class = "shinyOAuthDB_request_failed"
    )
    expect_identical(auth$calls$acquire, 2L)
  })
  expect_length(requests, 8L)
})

test_that("Cosmos malformed pages, counts and response headers fail without disclosure", {
  response <- NULL
  httr2::local_mocked_responses(function(req) response)
  odb_test_domain(function(session) {
    api <- cosmos_test_api(odb_test_authorization(session)$connection)
    for (body in c(
      "not JSON",
      "17",
      "[]",
      "{}",
      '{"Documents":{},"_count":0}',
      '{"Documents":[],"_count":null}',
      '{"Documents":[],"_count":"0"}',
      '{"Documents":[{}],"_count":0}',
      '{"Documents":[],"_count":-1}',
      '{"Documents":[],"_count":0.5}'
    )) {
      response <<- odb_http_response(body)
      expect_error(
        api$query("SELECT * FROM c"),
        class = "shinyOAuthDB_invalid_response"
      )
    }
    for (headers in list(
      list("x-ms-continuation" = "secret\r\ninjection"),
      list("x-ms-session-token" = "secret\nvalue"),
      list("x-ms-request-charge" = "-1"),
      list("x-ms-request-charge" = "private-value")
    )) {
      response <<- cosmos_response(headers = headers)
      error <- tryCatch(api$query("SELECT * FROM c"), error = identity)
      expect_s3_class(error, "shinyOAuthDB_invalid_response")
      expect_false(grepl("secret|private-value", conditionMessage(error)))
    }
    response <<- cosmos_response(headers = list("x-ms-continuation" = "same"))
    expect_error(api$query("SELECT * FROM c"), "repeated a continuation")
    response <<- cosmos_response(headers = list("x-ms-continuation" = ""))
    expect_identical(api$query("SELECT * FROM c"), data.frame())
    response <<- odb_http_response("[]")
    expect_error(api$read("id", "NL"), class = "shinyOAuthDB_invalid_response")
  })
})

test_that("Cosmos validates configuration and JSON inputs before making requests", {
  for (url in c(
    "http://account.documents.azure.com",
    "https://user:pass@account.example",
    "https://account.example/dbs/x",
    "https://account.example?key=secret",
    "https://account.example/#secret"
  )) {
    expect_error(
      oauth_db_cosmos_api(NULL, url, "db", "container"),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  for (id in c("..", "a/b", "a\\b", "a?b", "a#b", "trailing ", "")) {
    expect_error(
      oauth_db_cosmos_api(NULL, "https://account.example", id, "c"),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  for (size in list(0, -2, 1.5, NA, Inf, "10", c(1, 2))) {
    expect_error(
      cosmos_test_api(NULL, page_size = size),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  expect_error(
    cosmos_test_api(NULL, api_version = "bad\r\nheader"),
    class = "shinyOAuthDB_invalid_configuration"
  )
  odb_test_domain(function(session) {
    api <- cosmos_test_api(odb_test_authorization(session)$connection)
    for (parameters in list(
      1,
      list("unnamed"),
      list(`@id` = "one"),
      list(id = Inf),
      list(id = NA),
      list(id = NaN),
      list(id = factor("x")),
      list(id = matrix(1)),
      list(id = 1i),
      list(id = new.env()),
      list(id = as.Date(NA))
    )) {
      expect_error(
        api$query("SELECT * FROM c", parameters),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
    for (key in list(
      c("one", "two"),
      list(x = "one"),
      list(),
      rep(list(1), 4L),
      list(list(1)),
      NA
    )) {
      expect_error(
        api$query("SELECT * FROM c", partition_key = key),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
    expect_error(
      api$read("id", NULL),
      class = "shinyOAuthDB_invalid_configuration"
    )
    expect_error(
      api$query_page("SELECT * FROM c", continuation = "a\nb"),
      class = "shinyOAuthDB_invalid_configuration"
    )
    expect_error(
      api$query_page("SELECT * FROM c", session_token = ""),
      class = "shinyOAuthDB_invalid_configuration"
    )
  })
})

test_that("Cosmos sign-in declares only the documented resource and consent marker", {
  client <- oauth_db_cosmos_client(
    "organizations",
    "app",
    "http://localhost:8100"
  )
  expect_s3_class(client, "shinyOAuth::OAuthClient")
  expect_identical(client@token_target_default, "cosmos")
  expect_identical(
    client@token_targets$cosmos$resource,
    "https://cosmos.azure.com"
  )
  expect_identical(
    client@token_targets$cosmos$scopes,
    "https://cosmos.azure.com/.default"
  )
  expect_identical(client@token_targets$cosmos$required_scopes, character())
  expect_setequal(
    client@scopes,
    c(
      "openid",
      "profile",
      "offline_access",
      "https://cosmos.azure.com/.default"
    )
  )
  expect_true(client@provider@id_token_validation)
  expect_false(client@provider@userinfo_required)
  other <- oauth_db_cosmos_client(
    "organizations",
    "app",
    "http://localhost:8100",
    resource = "https://account.example/"
  )
  expect_identical(
    other@token_targets$cosmos$resource,
    "https://account.example"
  )
  expect_identical(
    other@token_targets$cosmos$scopes,
    "https://account.example/.default"
  )
  expect_error(
    oauth_db_cosmos_client(
      "organizations",
      "app",
      "http://localhost:8100",
      resource = "http://cosmos.example"
    ),
    class = "shinyOAuthDB_invalid_configuration"
  )
})

test_that("Cosmos default target works without treating .default as a granted scope", {
  httr2::local_mocked_responses(function(req) cosmos_response())
  odb_test_domain(function(session) {
    client <- oauth_db_cosmos_client(
      "organizations",
      "app",
      "http://localhost:8100"
    )
    auth <- odb_test_authorization(
      session,
      client = client,
      scopes = character()
    )
    api <- oauth_db_cosmos_api(
      auth$connection,
      "https://account.example",
      "db",
      "c"
    )
    expect_identical(api$query("SELECT * FROM c"), data.frame())
    strict <- cosmos_test_api(
      auth$connection,
      required_scopes = "https://cosmos.azure.com/read"
    )
    expect_error(strict$query("SELECT * FROM c"), class = "shiny.silent.error")
  })
})
