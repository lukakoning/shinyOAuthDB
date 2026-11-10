neo4j_response <- function() {
  odb_http_response(
    paste0(
      '{"data":{"fields":["name","n","active","large","node","mixed"],',
      '"values":[["Alice",42,true,9223372036854775807,',
      '{"elementId":"n1","labels":["Person"],"properties":{"id":9007199254740993}},1],',
      '[null,null,null,null,null,"one"]]},"bookmarks":["bookmark-1"],',
      '"notifications":[],"counters":{"nodesCreated":1,"containsUpdates":true}}'
    ),
    status = 202L
  )
}

test_that("Neo4j uses the Query API, bound parameters, current tokens and verified HTTPS", {
  requests <- list()
  httr2::local_mocked_responses(function(req) {
    requests[[length(requests) + 1L]] <<- req
    neo4j_response()
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    graph <- oauth_db_neo4j_api(
      auth$connection,
      "https://graph.example:7473/proxy/",
      database = "sales graph",
      ca_bundle = "ca.pem"
    )
    expect_identical(auth$calls$acquire, 0L)
    statement <- "MATCH (p:Person) WHERE p.name = $name RETURN p"
    parameters <- list(
      name = "Alice'; DETACH DELETE p; //",
      extra = NULL,
      properties = list(country = "NL", tags = list("one")),
      values = c(1, 2)
    )
    result <- graph$query(statement, parameters)
    expect_s3_class(result, "data.frame")
    expect_identical(result$name, c("Alice", NA_character_))
    expect_identical(result$n, c(42, NA_real_))
    expect_identical(result$active, c(TRUE, NA))
    expect_identical(result$large, c("9223372036854775807", NA_character_))
    expect_identical(result$node[[1L]]$properties$id, "9007199254740993")
    expect_null(result$node[[2L]])
    expect_identical(result$mixed, list(1L, "one"))
    expect_identical(requests[[1L]]$body$data$statement, statement)
    expect_identical(requests[[1L]]$body$data$parameters$name, parameters$name)
    render <- getFromNamespace("req_body_render", "httr2")
    body <- jsonlite::parse_json(render(requests[[1L]]))
    expect_null(body$parameters$extra)
    expect_identical(body$parameters$properties$tags, list("one"))
    expect_identical(body$parameters$values, list(1L, 2L))
    expect_identical(
      requests[[1L]]$url,
      "https://graph.example:7473/proxy/db/sales%20graph/query/v2"
    )
    expect_identical(httr2::req_get_method(requests[[1L]]), "POST")
    expect_identical(
      httr2::req_get_headers(requests[[1L]], redacted = "reveal")$Authorization,
      "Bearer fixture-A"
    )
    expect_identical(
      httr2::req_get_headers(requests[[1L]])$Accept,
      "application/json"
    )
    expect_null(httr2::req_get_headers(requests[[1L]])$Authorization)
    expect_false(requests[[1L]]$options$followlocation)
    expect_true(requests[[1L]]$options$fresh_connect)
    expect_true(requests[[1L]]$options$forbid_reuse)
    expect_identical(requests[[1L]]$options$cainfo, "ca.pem")
    expect_false(grepl(
      "fixture-A",
      paste(capture.output(print(graph)), collapse = "\n")
    ))
    expect_output(print(graph), "OAuthNeo4jAPI")
    auth$token(auth$make_token("renewed"))
    native <- graph$query("RETURN 1", raw = TRUE)
    expect_identical(native$bookmarks, list("bookmark-1"))
    expect_identical(native$data$values[[1L]][[4L]], "9223372036854775807")
    expect_identical(
      httr2::req_get_headers(requests[[2L]], redacted = "reveal")$Authorization,
      "Bearer renewed"
    )
    expect_named(requests[[2L]]$body$data, "statement")
    counters <- withVisible(graph$execute(
      "CREATE (:Person {name: $name})",
      list(name = "Bob")
    ))
    expect_false(counters$visible)
    expect_identical(counters$value$nodesCreated, 1L)
    expect_true(requests[[3L]]$body$data$includeCounters)
  })
})

test_that("Neo4j never replays statements and sanitizes HTTP and Cypher failures", {
  count <- 0L
  status <- 401L
  body <- "PRIVATE_BODY fixture-A"
  httr2::local_mocked_responses(function(req) {
    count <<- count + 1L
    odb_http_response(body, status)
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, refresh_token = "fixture-refresh")
    graph <- oauth_db_neo4j_api(auth$connection, "https://graph.example")
    operations <- list(
      function() graph$query("RETURN 1"),
      function() graph$query("RETURN 1", raw = TRUE),
      function() graph$execute("CREATE (:Person)")
    )
    for (code in c(401L, 403L, 429L, 503L, 302L)) {
      status <<- code
      for (operation in operations) {
        before <- count
        error <- expect_error(
          operation(),
          class = "shinyOAuthDB_request_failed"
        )
        expect_identical(error$status, code)
        expect_null(error$parent)
        expect_false(grepl("PRIVATE_BODY|fixture-A", conditionMessage(error)))
        expect_identical(count, before + 1L)
      }
    }
    expect_identical(auth$calls$acquire, 0L)
    status <<- 202L
    body <<- '{"data":{"fields":["name"],"values":[["partial"]]},"errors":[{"code":"Neo.ClientError.Security.Forbidden","message":"PRIVATE_BODY fixture-A"}]}'
    for (operation in operations) {
      before <- count
      error <- expect_error(operation(), class = "shinyOAuthDB_query_failed")
      expect_null(error$parent)
      expect_false(grepl(
        "PRIVATE_BODY|fixture-A|partial",
        conditionMessage(error)
      ))
      expect_identical(count, before + 1L)
    }
  })
})

test_that("Neo4j keeps targets, selected accounts and retained clients in their owning session", {
  requests <- character()
  during <- function() NULL
  saved <- NULL
  httr2::local_mocked_responses(function(req) {
    requests <<- c(
      requests,
      httr2::req_get_headers(req, redacted = "reveal")$Authorization
    )
    during()
    neo4j_response()
  })
  odb_test_domain(function(session) {
    a <- odb_test_authorization(
      session,
      target = "graph",
      scopes = "read",
      unacquired = TRUE
    )
    b <- odb_test_authorization(
      session,
      id = "B",
      target = "graph",
      scopes = "read"
    )
    selected <- shiny::reactiveVal(NULL)
    graph <- oauth_db_neo4j_api(
      selected,
      "https://graph.example",
      target = "graph",
      required_scopes = a$scopes
    )
    expect_error(graph$query("RETURN 1"), class = "shiny.silent.error")
    expect_length(requests, 0L)
    selected(a$connection)
    graph$query("RETURN 1")
    expect_identical(tail(requests, 1L), "Bearer fixture-A-acquired")
    expect_identical(a$calls$acquire, 1L)
    selected(b$connection)
    graph$query("RETURN 1")
    expect_identical(tail(requests, 1L), "Bearer fixture-B")
    during <<- function() selected(a$connection)
    expect_error(
      graph$query("RETURN 1"),
      class = "shinyOAuthDB_authorization_unavailable"
    )
    during <<- function() NULL
    graph$query("RETURN 1")
    expect_identical(tail(requests, 1L), "Bearer fixture-A-acquired")
    during <<- function() {
      a$token(a$make_token("less-access", permissions = character()))
    }
    expect_error(
      graph$query("RETURN 1"),
      class = "shinyOAuthDB_authorization_unavailable"
    )
    during <<- function() NULL
    a$token(a$make_token("renewed"))
    during <<- function() selected(NULL)
    expect_error(
      graph$query("RETURN 1", raw = TRUE),
      class = "shinyOAuthDB_authorization_unavailable"
    )
    during <<- function() NULL
    before <- length(requests)
    expect_error(graph$query("RETURN 1"), class = "shiny.silent.error")
    expect_length(requests, before)
    selected(a$connection)
    saved <<- graph
  })
  odb_test_domain(function(session) {
    expect_error(
      saved$query("RETURN 1"),
      class = "shinyOAuthDB_authorization_unavailable"
    )
  })
})

test_that("Neo4j rejects unsafe configuration and ambiguous parameters before sending requests", {
  for (url in c(
    "http://graph.example",
    "bolt://graph.example",
    "neo4j+s://graph.example",
    "https://user:secret@graph.example",
    "https://graph.example?token=x",
    "https://graph.example/../proxy",
    "https://graph.example#fragment"
  )) {
    expect_error(
      oauth_db_neo4j_api(NULL, url),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  for (database in list(
    NULL,
    character(),
    c("one", "two"),
    NA_character_,
    "",
    42,
    "../system",
    "a/b",
    "a\\b",
    "..",
    "a\nInjected: yes"
  )) {
    expect_error(
      oauth_db_neo4j_api(NULL, "https://graph.example", database),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  count <- 0L
  httr2::local_mocked_responses(function(req) {
    count <<- count + 1L
    neo4j_response()
  })
  odb_test_domain(function(session) {
    graph <- oauth_db_neo4j_api(
      odb_test_response_authorization()$connection,
      "https://graph.example"
    )
    for (parameters in list(
      42,
      NULL,
      list(1),
      data.frame(x = 1),
      stats::setNames(list(1, 2), c("x", "x")),
      stats::setNames(list(1), ""),
      list(x = Inf),
      list(x = -Inf),
      list(x = NaN),
      list(x = factor("a")),
      list(x = matrix(1)),
      list(x = as.raw(1)),
      list(x = 1i),
      list(x = structure(list(1, 2), names = c("a", "a")))
    )) {
      expect_error(
        graph$query("RETURN $x", parameters),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
    expect_error(graph$query("RETURN 1", raw = NA), "TRUE or FALSE")
    expect_error(graph$query(""), "non-empty")
    expect_identical(count, 0L)
  })
})

test_that("Neo4j preserves floating parameters, nulls, nested maps and temporal strings", {
  sent <- NULL
  httr2::local_mocked_responses(function(req) {
    render <- getFromNamespace("req_body_render", "httr2")
    sent <<- jsonlite::parse_json(render(req))
    neo4j_response()
  })
  odb_test_domain(function(session) {
    graph <- oauth_db_neo4j_api(
      odb_test_response_authorization()$connection,
      "https://graph.example"
    )
    values <- c(
      1.0000000000000002,
      1.2345678901234567,
      9007199254740991,
      1e-100
    )
    graph$query(
      "RETURN $values",
      list(
        values = values,
        nullable = list(NULL, NA, NA_real_, NA_character_),
        day = as.Date("2026-11-09"),
        at = as.POSIXct("2026-11-09 13:00:00.125", tz = "Europe/Amsterdam"),
        missing = as.Date(NA),
        map = list(empty = list(), flag = TRUE)
      )
    )
    expect_identical(unlist(sent$parameters$values), values)
    expect_identical(sent$parameters$nullable, rep(list(NULL), 4L))
    expect_identical(sent$parameters$day, "2026-11-09")
    expect_identical(sent$parameters$at, "2026-11-09T12:00:00.125000Z")
    expect_null(sent$parameters$missing)
    expect_identical(sent$parameters$map, list(empty = list(), flag = TRUE))
  })
})

test_that("Neo4j validates complete result envelopes even for raw results and writes", {
  body <- NULL
  httr2::local_mocked_responses(function(req) odb_http_response(body, 202L))
  odb_test_domain(function(session) {
    graph <- oauth_db_neo4j_api(
      odb_test_response_authorization()$connection,
      "https://graph.example"
    )
    for (invalid in c(
      "{broken",
      "[]",
      "null",
      "{}",
      '{"data":[]}',
      '{"data":{"fields":[],"values":{}}}',
      '{"data":{"fields":{},"values":[]}}',
      '{"data":{"fields":[null],"values":[]}}',
      '{"data":{"fields":[1],"values":[]}}',
      '{"data":{"fields":["x"],"values":[[]]}}',
      '{"data":{"fields":["x"],"values":[{"x":1}]}}',
      '{"data":{"fields":["x"],"values":[[1,2]]}}',
      '{"errors":{},"data":{"fields":[],"values":[]}}',
      '{"errors":null,"data":{"fields":[],"values":[]}}',
      '{"data":{"fields":[],"values":[]},"data":{"fields":[],"values":[]}}'
    )) {
      body <<- invalid
      expect_error(
        graph$query("RETURN 1"),
        class = "shinyOAuthDB_invalid_response"
      )
      expect_error(
        graph$query("RETURN 1", raw = TRUE),
        class = "shinyOAuthDB_invalid_response"
      )
      expect_error(
        graph$execute("CREATE (:Person)"),
        class = "shinyOAuthDB_invalid_response"
      )
    }
    body <<- '{"data":{"fields":["x","x"],"values":[]},"errors":[]}'
    empty <- graph$query("RETURN null AS x, null AS x LIMIT 0")
    expect_named(empty, c("x", "x"))
    expect_identical(empty[[1L]], logical())
    expect_equal(nrow(empty), 0L)
    body <<- '{"data":{"fields":["x","x"],"values":[[null,null],[null,null]]}}'
    expect_identical(
      graph$query("RETURN null AS x, null AS x")[[1L]],
      c(NA, NA)
    )
    body <<- '{"data":{"fields":[],"values":[]},"counters":{}}'
    expect_equal(dim(graph$query("CREATE (:Person)")), c(0L, 0L))
    expect_identical(
      graph$execute("CREATE (:Person)"),
      stats::setNames(list(), character())
    )
    body <<- '{"data":{"fields":[],"values":[]}}'
    expect_error(graph$execute("CREATE (:Person)"), "counters")
  })
})
