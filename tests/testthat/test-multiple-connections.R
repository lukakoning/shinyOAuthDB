test_that("the manager example selects a database grant explicitly", {
  skip_if_not_installed("RSQLite")
  fixture <- multiple_fixture()
  app <- multiple_app(fixture)
  shiny::testServer(app$server, session = multiple_session(fixture$cookie), {
    expect_length(auth$connections(), 3L)
    expect_error(auth$connection(), class = "shinyOAuth_access_error")
    expect_error(output$rows, class = "shiny.silent.error")
    session$setInputs(authorization_id = fixture$ids$login)
    expect_error(output$rows, class = "shiny.silent.error")
    session$setInputs(authorization_id = fixture$ids$a)
    expect_match(output$rows, ">\\s*A\\s*<")
    con_a <- con()

    session$setInputs(authorization_id = fixture$ids$b)
    expect_false(DBI::dbIsValid(con_a))
    expect_match(output$rows, ">\\s*B\\s*<")

    session$setInputs(disconnect = 1L)
    expect_error(output$rows, class = "shiny.silent.error")
    active <- Filter(function(x) x$status != "disconnected", auth$connections())
    expect_length(active, 2L)
  })
})

test_that("retained manager grants restore without restoring a result or selection", {
  skip_if_not_installed("RSQLite")
  fixture <- multiple_fixture()
  app <- multiple_app(fixture)
  previous <- NULL
  shiny::testServer(app$server, session = multiple_session(fixture$cookie), {
    session$setInputs(authorization_id = fixture$ids$a)
    expect_match(output$rows, ">\\s*A\\s*<")
    previous <<- con()
  })
  expect_false(DBI::dbIsValid(previous))
  shiny::testServer(app$server, session = multiple_session(fixture$cookie), {
    expect_length(auth$connections(), 3L)
    expect_error(output$rows, class = "shiny.silent.error")
    session$setInputs(authorization_id = fixture$ids$b)
    expect_match(output$rows, ">\\s*B\\s*<")
    expect_false(identical(con(), previous))
  })
})

test_that("the bridge preserves ambiguous manager selection errors", {
  fixture <- multiple_fixture()
  shiny::testServer(
    function(input, output, session) {
      auth <- shinyOAuth::oauth_connections_server(
        "authorizations",
        fixture$manager
      )
      token <- oauth_db_token(auth$connection, required_scopes = "demo.read")
    },
    session = multiple_session(fixture$cookie),
    {
      expect_error(session$flushReact(), NA)
      error <- expect_error(token(), class = "shinyOAuth_access_error")
      expect_identical(error$context$reason, "selection_required")
      expect_false(session$isClosed())
      auth$disconnect(fixture$ids$login, revoke = FALSE)
      auth$disconnect(fixture$ids$b, revoke = FALSE)
      session$flushReact()
      expect_identical(token(), "fixture-A")
    }
  )
})

test_that("two native accessors use separate client registrations independently", {
  skip_if_not_installed("RSQLite")
  fixture <- multiple_fixture(
    second_database = TRUE,
    different_providers = TRUE
  )
  expect_false(identical(
    fixture$clients$database@provider,
    fixture$clients$warehouse@provider
  ))
  expect_false(identical(
    fixture$clients$database@client_id,
    fixture$clients$warehouse@client_id
  ))
  expect_false(identical(
    fixture$clients$database@scopes,
    fixture$clients$warehouse@scopes
  ))
  connect <- function(token) {
    native <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    DBI::dbWriteTable(
      native,
      "identity",
      data.frame(user = sub("^fixture-", "", token))
    )
    native
  }
  warehouse_native <- NULL
  shiny::testServer(
    function(input, output, session) {
      auth <- shinyOAuth::oauth_connections_server(
        "authorizations",
        fixture$manager
      )
      database <- oauth_db_connect(
        function() auth$connection(fixture$ids$a),
        connect = connect,
        required_scopes = "demo.read"
      )
      warehouse <- oauth_db_connect(
        function() auth$connection(fixture$ids$warehouse),
        connect = connect,
        required_scopes = "warehouse.read"
      )
      wrong_grant <- oauth_db_connect(
        function() auth$connection(fixture$ids$a),
        connect = connect,
        required_scopes = "warehouse.read"
      )
    },
    session = multiple_session(fixture$cookie),
    {
      database_native <- database()
      warehouse_native <<- warehouse()
      expect_false(identical(database_native, warehouse_native))
      expect_identical(
        DBI::dbGetQuery(database_native, "SELECT * FROM identity")$user,
        "A"
      )
      expect_identical(
        DBI::dbGetQuery(warehouse_native, "SELECT * FROM identity")$user,
        "WAREHOUSE"
      )
      expect_error(wrong_grant(), class = "shiny.silent.error")

      # Removing one registration's grant must not borrow another available grant
      # or retire the other registration's established native connection.
      auth$disconnect(fixture$ids$a, revoke = FALSE)
      session$flushReact()
      expect_false(DBI::dbIsValid(database_native))
      expect_error(database(), class = "shiny.silent.error")
      expect_identical(warehouse(), warehouse_native)
      expect_true(DBI::dbIsValid(warehouse_native))
      expect_identical(
        DBI::dbGetQuery(warehouse_native, "SELECT * FROM identity")$user,
        "WAREHOUSE"
      )
      expect_true(auth$connection(fixture$ids$b)$has_scopes("demo.read"))

      auth$disconnect(fixture$ids$warehouse, revoke = FALSE)
      session$flushReact()
      expect_false(DBI::dbIsValid(warehouse_native))
      expect_error(warehouse(), class = "shiny.silent.error")
    }
  )
})
