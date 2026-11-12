mongodb_fixture <- function() {
  state <- new.env(parent = emptyenv())
  state$clients <- list()
  state$calls <- list()
  state$result <- list(ok = TRUE, json = '[{"total":12}]')
  state$after <- function() NULL
  state$open <- function(
    token,
    url,
    db,
    issuer,
    user,
    client_id,
    hosts,
    timeout,
    ca_bundle
  ) {
    client <- new.env(parent = emptyenv())
    client$closed <- FALSE
    client$token <- token
    client$user <- user
    client$hosts <- hosts
    client$execute <- function(operation, args) {
      state$calls[[length(state$calls) + 1L]] <- list(
        token = token,
        operation = operation,
        args = args
      )
      state$after()
      state$result
    }
    client$close <- function() client$closed <- TRUE
    state$clients[[length(state$clients) + 1L]] <- client
    client
  }
  state
}

test_that("MongoDB uses current visitor credentials and keeps native JSON arguments", {
  state <- mongodb_fixture()
  local_mocked_bindings(.odb_mongodb_open = state$open)
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    mongo <- oauth_db_mongodb(
      auth$connection,
      "mongodb://mongo.example.org",
      "reports",
      "https://login.example.org"
    )
    expect_identical(
      mongo$find("orders", '{"country":"NL"}'),
      data.frame(total = 12L)
    )
    expect_identical(
      mongo$find("orders", simplify = FALSE),
      list(list(total = 12L))
    )
    expect_length(state$clients, 1L)
    expect_identical(state$clients[[1L]]$hosts, "mongo.example.org")
    expect_identical(state$calls[[1L]]$args$filter, '{"country":"NL"}')
    expect_identical(state$calls[[1L]]$args$limit, 100L)
    auth$token(auth$make_token("renewed.jwt.signature"))
    mongo$find("orders")
    expect_length(state$clients, 2L)
    expect_true(state$clients[[1L]]$closed)
    expect_identical(state$clients[[2L]]$token, "renewed.jwt.signature")
    expect_output(print(mongo), "^<OAuthMongoDBClient>")
  })
  expect_true(state$clients[[2L]]$closed)
})

test_that("MongoDB reads preserve BSON types, large integers and empty results", {
  state <- mongodb_fixture()
  local_mocked_bindings(.odb_mongodb_open = state$open)
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    mongo <- oauth_db_mongodb(
      auth$connection,
      "mongodb://mongo.example.org",
      "reports",
      "https://login.example.org"
    )
    state$result$json <- '[{"id":9223372036854775807,"oid":{"$oid":"abc"},"null":null}]'
    rows <- mongo$find("orders", simplify = FALSE)
    expect_identical(rows[[1L]]$id, "9223372036854775807")
    expect_identical(rows[[1L]]$oid, list(`$oid` = "abc"))
    expect_null(rows[[1L]]$null)
    state$result$json <- "[]"
    expect_identical(mongo$find("orders"), data.frame())
    expect_identical(mongo$aggregate("orders", "[]", simplify = FALSE), list())
    state$result$json <- "9223372036854775807"
    expect_identical(mongo$count("orders"), "9223372036854775807")
    state$result$json <- '{"ok":1,"n":2}'
    expect_identical(
      mongo$run('{"insert":"orders","documents":[]}'),
      list(ok = 1L, n = 2L)
    )
    expect_identical(state$calls[[3L]]$operation, "aggregate")
    expect_identical(state$calls[[4L]]$operation, "count")
  })
})

test_that("MongoDB separates visitors and rejects retained clients after sign-out", {
  state <- mongodb_fixture()
  local_mocked_bindings(.odb_mongodb_open = state$open)
  retained <- NULL
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session, id = "A")
    b <- odb_test_authorization(session, id = "B")
    selected <- shiny::reactiveVal(a$connection)
    mongo <- oauth_db_mongodb(
      selected,
      "mongodb://mongo.example.org",
      "reports",
      "https://login.example.org"
    )
    mongo$find("orders")
    selected(b$connection)
    mongo$find("orders")
    expect_true(state$clients[[1L]]$closed)
    expect_identical(
      vapply(state$calls, `[[`, "", "token"),
      c("fixture-A", "fixture-B")
    )
    selected(NULL)
    expect_error(mongo$find("orders"), class = "shiny.silent.error")
    expect_true(state$clients[[2L]]$closed)
    retained <<- mongo
  })
  expect_error(
    retained$count("orders"),
    class = "shinyOAuthDB_authorization_unavailable"
  )
  expect_length(state$calls, 2L)
})

test_that("MongoDB discards responses when access changes during an operation", {
  for (change in c("account", "permissions", "session")) {
    state <- mongodb_fixture()
    local_mocked_bindings(.odb_mongodb_open = state$open)
    odb_test_domain(function(session) {
      a <- odb_test_authorization(session)
      b <- odb_test_authorization(session, id = "B")
      selected <- shiny::reactiveVal(a$connection)
      mongo <- oauth_db_mongodb(
        selected,
        "mongodb://mongo.example.org",
        "reports",
        "https://login.example.org",
        required_scopes = "read"
      )
      state$after <- switch(
        change,
        account = function() selected(b$connection),
        permissions = function() a$token(a$make_token("changed", "write")),
        session = function() session$close()
      )
      expect_error(
        mongo$find("orders"),
        class = "shinyOAuthDB_authorization_unavailable"
      )
      expect_true(state$clients[[1L]]$closed)
    })
  }
})

test_that("MongoDB validates operation inputs before acquiring credentials", {
  state <- mongodb_fixture()
  local_mocked_bindings(.odb_mongodb_open = state$open)
  odb_test_domain(function(session) {
    mongo <- oauth_db_mongodb(
      function() NULL,
      "mongodb://mongo.example.org",
      "reports",
      "https://login.example.org"
    )
    for (value in c("[]", "null", "{", '"filter"')) {
      expect_error(
        mongo$find("orders", value),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
    expect_error(mongo$aggregate("orders", "{}"), "JSON array")
    expect_error(mongo$run("[]"), "JSON object")
    for (value in list(-1, NA_real_, Inf, 0.5, 2^32, "2", c(1, 2))) {
      expect_error(mongo$find("orders", limit = value), "32-bit integers")
    }
    expect_error(mongo$find("bad$collection"), "collection name")
    expect_error(mongo$find("orders", simplify = NA), "TRUE or FALSE")
    expect_error(mongo$count("orders"), class = "shiny.silent.error")
  })
  expect_length(state$clients, 0L)
})

test_that("MongoDB restricts endpoints, authentication and TLS configuration", {
  expect_identical(
    .odb_mongodb_url("mongodb://one.example:27017,two.example:27018", NULL),
    c("one.example", "two.example")
  )
  expect_identical(
    .odb_mongodb_url("mongodb+srv://cluster0.abc.mongodb.net", NULL),
    "*.abc.mongodb.net"
  )
  expect_identical(
    .odb_mongodb_url("mongodb+srv://cluster.example", "*.cluster.example"),
    "*.cluster.example"
  )
  for (url in c(
    "https://mongo.example",
    "mongodb://user:password@mongo.example",
    "mongodb://user%40mongo.example",
    "mongodb://mongo.example/reports",
    "mongodb://mongo.example/?tls=false",
    "mongodb://mongo.example/?ssl=false",
    "mongodb://mongo.example/?authMechanism=SCRAM-SHA-256",
    "mongodb://mongo.example/?authMechanismProperties=ENVIRONMENT:azure",
    "mongodb://mongo.example/?retryWrites=true",
    "mongodb://mongo.example/?tlsInsecure=true",
    "mongodb://mongo.example/?replicaSet=a&replicaset=b",
    "mongodb+srv://custom.example",
    "mongodb://mongo.example/#fragment"
  )) {
    expect_error(
      .odb_mongodb_url(url, NULL),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  for (hosts in list(
    "*",
    "*.com",
    NA_character_,
    character(),
    "https://mongo.example"
  )) {
    expect_error(
      .odb_mongodb_url("mongodb://mongo.example", hosts),
      "allowed_hosts"
    )
  }
  odb_test_domain(function(session) {
    for (issuer in c(
      "http://login.example",
      "https://user:pass@login.example",
      "https://login.example?token=x"
    )) {
      expect_error(
        oauth_db_mongodb(
          function() NULL,
          "mongodb://mongo.example",
          "reports",
          issuer
        ),
        "HTTPS issuer"
      )
    }
    expect_error(
      oauth_db_mongodb(
        function() NULL,
        "mongodb://mongo.example",
        "reports",
        "https://login.example",
        timeout = 0
      ),
      "positive"
    )
  })
})

test_that("MongoDB accepts compressed IPv6 hosts without broadening allowlists", {
  for (host in c("::1", "::", "::ffff:192.0.2.10", "2001:db8::1")) {
    expect_identical(
      .odb_mongodb_url(paste0("mongodb://[", host, "]:27017"), NULL),
      host
    )
    expect_identical(.odb_mongodb_url("mongodb://mongo.example", host), host)
  }
  expect_identical(
    .odb_mongodb_url("mongodb://[::1]:27017,mongo.example:27018", NULL),
    c("::1", "mongo.example")
  )
  for (host in c(":", ":::1", "2001::db8::1", "::gg", "::ffff:999.1.1.1")) {
    expect_error(
      .odb_mongodb_url(paste0("mongodb://[", host, "]:27017"), NULL),
      "allowed_hosts"
    )
  }
  for (host in c("*::1", "*.::1", "[::1]", "::1/path", "::1@mongo.example")) {
    expect_error(
      .odb_mongodb_url("mongodb://mongo.example", host),
      "allowed_hosts"
    )
  }
})

test_that("MongoDB passes IPv6 loopback allowlists to the native client", {
  state <- mongodb_fixture()
  local_mocked_bindings(.odb_mongodb_open = state$open)
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    for (hosts in list(NULL, "::1")) {
      mongo <- oauth_db_mongodb(
        auth$connection,
        "mongodb://[::1]:27017",
        "reports",
        "https://login.example.org",
        allowed_hosts = hosts
      )
      expect_identical(mongo$find("orders"), data.frame(total = 12L))
      expect_identical(state$clients[[length(state$clients)]]$hosts, "::1")
    }
  })
})

test_that("MongoDB checks literal scopes and named token targets", {
  state <- mongodb_fixture()
  local_mocked_bindings(.odb_mongodb_open = state$open)
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, target = "mongo")
    mongo <- oauth_db_mongodb(
      auth$connection,
      "mongodb://mongo.example",
      "reports",
      "https://login.example",
      target = "mongo",
      required_scopes = auth$scopes[[1L]]
    )
    mongo$count("orders")
    expect_identical(state$clients[[1L]]$token, "fixture-A")
    denied <- oauth_db_mongodb(
      auth$connection,
      "mongodb://mongo.example",
      "reports",
      "https://login.example",
      target = "mongo",
      required_scopes = "read"
    )
    expect_error(denied$count("orders"), class = "shiny.silent.error")
    expect_length(state$clients, 1L)
  })
})

test_that("MongoDB errors do not retain server text or replay failed commands", {
  state <- mongodb_fixture()
  state$result <- list(ok = FALSE, code = 13L, message = "secret-jwt-and-query")
  local_mocked_bindings(.odb_mongodb_open = state$open)
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    mongo <- oauth_db_mongodb(
      auth$connection,
      "mongodb://mongo.example",
      "reports",
      "https://login.example"
    )
    error <- tryCatch(
      mongo$run('{"insert":"orders","documents":[]}'),
      error = identity
    )
    expect_s3_class(error, "shinyOAuthDB_query_failed")
    expect_match(conditionMessage(error), "server code 13", fixed = TRUE)
    expect_false(grepl(
      "secret-jwt",
      paste(capture.output(str(error)), collapse = ""),
      fixed = TRUE
    ))
    expect_length(state$calls, 1L)
  })
})
