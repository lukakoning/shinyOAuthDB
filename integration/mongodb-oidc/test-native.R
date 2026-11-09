library(testthat)
library(shinyOAuthDB)
root <- Sys.getenv("OAUTHDB_MONGODB_ROOT")
source(file.path(root, "tests/testthat/helper-authorization.R"))
config <- jsonlite::read_json(Sys.getenv("OAUTHDB_MONGODB_FIXTURE"))

test_that("real MongoDB workforce tokens preserve visitor permissions and BSON values", {
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    auth$token(auth$make_token(config$alice))
    mongo <- oauth_db_mongodb(
      auth$connection,
      config$url,
      config$db,
      config$issuer,
      client_id = "shiny-db",
      ca_bundle = config$ca,
      timeout = 8
    )
    rows <- mongo$find("alice_orders", filter = '{"country":"NL"}')
    expect_identical(rows$owner, "alice")
    expect_identical(rows$total, "9007199254740993")
    expect_identical(mongo$count("alice_orders"), 2L)
    expect_equal(nrow(mongo$find("alice_pages")), 100L)
    expect_equal(nrow(mongo$find("alice_pages", limit = 0)), 250L)
    expect_equal(nrow(mongo$aggregate("alice_pages", "[]")), 250L)
    expect_identical(
      mongo$aggregate("alice_orders", '[{"$count":"n"}]'),
      data.frame(n = 2L)
    )
    expect_identical(
      mongo$find("alice_orders", '{"country":"missing"}'),
      data.frame()
    )
    expect_error(mongo$find("bob_orders"), class = "shinyOAuthDB_query_failed")
    expect_error(
      mongo$run('{"insert":"alice_orders","documents":[{"x":1}]}'),
      class = "shinyOAuthDB_query_failed"
    )
    status <- mongo$run('{"connectionStatus":1}')
    expect_identical(
      status$authInfo$authenticatedUsers[[1L]]$user,
      "shiny/alice"
    )
    auth$token(auth$make_token(config$renewed))
    expect_identical(mongo$count("alice_orders"), 2L)
    auth$current(FALSE)
    expect_error(
      mongo$count("alice_orders"),
      class = "shiny.silent.error"
    )
  })
})

test_that("real MongoDB separates account changes and closes on sign-out", {
  retained <- NULL
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    b <- odb_test_authorization(session, id = "B")
    a$token(a$make_token(config$alice))
    b$token(b$make_token(config$bob))
    selected <- shiny::reactiveVal(a$connection)
    mongo <- oauth_db_mongodb(
      selected,
      config$url,
      config$db,
      config$issuer,
      ca_bundle = config$ca,
      timeout = 8
    )
    expect_identical(mongo$count("alice_orders"), 2L)
    selected(b$connection)
    expect_equal(
      mongo$run('{"insert":"bob_orders","documents":[{"country":"DE"}]}')$n,
      1
    )
    expect_identical(mongo$count("bob_orders"), 3L)
    expect_identical(mongo$find("bob_orders", '{"country":"NL"}')$owner, "bob")
    expect_error(
      mongo$count("alice_orders"),
      class = "shinyOAuthDB_query_failed"
    )
    selected(NULL)
    expect_error(mongo$count("bob_orders"), class = "shiny.silent.error")
    retained <<- mongo
  })
  expect_error(
    retained$count("bob_orders"),
    class = "shinyOAuthDB_authorization_unavailable"
  )
})

test_that("real MongoDB rejects invalid JWTs, unexpected challenges and TLS trust", {
  for (kind in c("expired", "audience", "issuer_token", "signature")) {
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session)
      auth$token(auth$make_token(config[[kind]]))
      mongo <- oauth_db_mongodb(
        auth$connection,
        config$url,
        config$db,
        config$issuer,
        ca_bundle = config$ca,
        timeout = 4
      )
      expect_error(
        mongo$count("alice_orders"),
        class = "shinyOAuthDB_query_failed"
      )
    })
  }
  for (kind in c("issuer", "client", "host", "ca", "hostname")) {
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session)
      auth$token(auth$make_token(config$alice))
      mongo <- oauth_db_mongodb(
        auth$connection,
        if (kind == "hostname") {
          sub("localhost", "127.0.0.1", config$url)
        } else {
          config$url
        },
        config$db,
        issuer = if (kind == "issuer") {
          "https://wrong.invalid"
        } else {
          config$issuer
        },
        client_id = if (kind == "client") "wrong-client" else "shiny-db",
        allowed_hosts = if (kind == "host") {
          "wrong.invalid"
        } else {
          c("localhost", "127.0.0.1")
        },
        ca_bundle = if (kind == "ca") NULL else config$ca,
        timeout = 2
      )
      expect_error(
        mongo$count("alice_orders"),
        class = "shinyOAuthDB_query_failed"
      )
    })
  }
})

test_that("MongoDB excludes managed authentication, transactions and cursor commands", {
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    auth$token(auth$make_token(config$alice))
    mongo <- oauth_db_mongodb(
      auth$connection,
      config$url,
      config$db,
      config$issuer,
      ca_bundle = config$ca,
      timeout = 4
    )
    for (command in c(
      '{"saslStart":1}',
      '{"find":"alice_orders"}',
      '{"getMore":1}',
      '{"ping":1,"lsid":{"id":"x"}}'
    )) {
      expect_error(mongo$run(command), class = "shinyOAuthDB_query_failed")
    }
    expect_identical(mongo$count("alice_orders"), 2L)
  })
})
