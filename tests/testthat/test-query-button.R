test_that("button queries clear stored results on authorization and permission changes", {
  skip_if_not_installed("RSQLite")
  withr::local_envvar(playground_env())
  app <- playground_load_example("example-query-button.R")
  expect_equal(app$ui(playground_request())$status, 200L)
  calls <- new.env(parent = emptyenv())
  calls$queries <- 0L
  calls$fail <- FALSE
  app$oauth_module_server <- function(id, client, ...) {
    session <- shiny::getDefaultReactiveDomain()
    calls$a <- odb_test_authorization(session, "A", "user_impersonation", "sql",
      resource = "https://database.windows.net/")
    calls$b <- odb_test_authorization(session, "B", "user_impersonation", "sql",
      resource = "https://database.windows.net/")
    selected <- shiny::reactiveVal(NULL)
    calls$select <- selected
    list(connection = selected, request_login = function() NULL, logout = function() selected(NULL))
  }
  app$oauth_db_azure_sql <- function(authorization, required_scopes, ...) {
    oauth_db_connect(authorization, required_scopes = required_scopes, target = "sql", connect = function(token) {
      con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
      DBI::dbWriteTable(con, "identity", data.frame(user = sub("^fixture-", "", token)))
      con
    })
  }
  native_query <- DBI::dbGetQuery
  local_mocked_bindings(dbGetQuery = function(conn, statement, ...) {
    calls$queries <- calls$queries + 1L
    if (calls$fail) stop("Query failed")
    native_query(conn, "SELECT * FROM identity")
  }, .package = "DBI")
  saved <- NULL
  shiny::testServer(app$server, {
    expect_error(output$rows, class = "shiny.silent.error")
    calls$select(calls$a$connection)
    session$flushReact()
    expect_error(output$rows, class = "shiny.silent.error")
    expect_identical(calls$queries, 0L)
    session$setInputs(run = 1L)
    expect_match(output$rows, ">\\s*A\\s*<")
    first <- con()
    calls$a$token(calls$a$make_token("fixture-A-refreshed"))
    session$flushReact()
    expect_match(output$rows, ">\\s*A\\s*<")
    expect_identical(calls$queries, 1L)
    expect_identical(con(), first)

    calls$select(calls$b$connection)
    session$flushReact()
    expect_false(DBI::dbIsValid(first))
    expect_null(rows())
    expect_error(output$rows, class = "shiny.silent.error")
    session$setInputs(run = 2L)
    expect_match(output$rows, ">\\s*B\\s*<")
    second <- con()
    calls$b$token(calls$b$make_token("fixture-B", permissions = character()))
    session$flushReact()
    expect_null(rows())
    expect_false(DBI::dbIsValid(second))
    calls$b$token(calls$b$make_token("fixture-B"))
    session$flushReact()
    expect_null(rows())
    expect_error(output$rows, class = "shiny.silent.error")
    expect_identical(calls$queries, 2L)

    calls$fail <- TRUE
    session$setInputs(run = 3L)
    expect_error(output$rows, "Query failed")
    expect_false(session$isClosed())
    calls$fail <- FALSE
    session$setInputs(run = 4L)
    expect_match(output$rows, ">\\s*B\\s*<")
    saved <<- con()
    session$setInputs(logout = 1L)
    expect_null(rows())
    expect_error(output$rows, class = "shiny.silent.error")
    expect_false(DBI::dbIsValid(saved))
    calls$select(calls$a$connection)
    session$flushReact()
    expect_error(output$rows, class = "shiny.silent.error")
    expect_identical(calls$queries, 4L)
  })
})
