test_that("the two-provider example builds separate clients and callback routes", {
  withr::local_envvar(playground_env())
  local_mocked_bindings(oauth_db_databricks_provider = playground_databricks_provider)
  app <- playground_load_example("example-two-authorizations.R")
  expect_equal(app$ui(playground_request())$status, 200L)
  expect_identical(app$sql_client@client_id, "sql-client")
  expect_identical(app$databricks_client@client_id, "databricks-client")
  expect_identical(app$sql_client@redirect_uri, "http://localhost:8100/callback/sql")
  expect_identical(app$databricks_client@redirect_uri, "http://localhost:8100/callback/databricks")
  expect_false(identical(app$sql_client@provider, app$databricks_client@provider))
})

test_that("the two-provider app queries and disconnects each authorization independently", {
  skip_if_not_installed("RSQLite")
  withr::local_envvar(playground_env())
  local_mocked_bindings(oauth_db_databricks_provider = playground_databricks_provider)
  app <- playground_load_example("example-two-authorizations.R")
  fixture <- multiple_fixture(second_database = TRUE, different_providers = TRUE,
    labels = c(login = "login", database = "Azure SQL", warehouse = "Databricks"))
  app$manager <- fixture$manager
  connect <- function(token) {
    con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    DBI::dbWriteTable(con, "identity", data.frame(user = sub("^fixture-", "", token)))
    con
  }
  app$oauth_db_azure_sql <- function(authorization, ...) {
    oauth_db_connect(authorization, connect, scopes = "demo.read")
  }
  app$oauth_db_databricks <- function(authorization, ...) {
    oauth_db_connect(authorization, connect, scopes = "warehouse.read")
  }
  native_query <- DBI::dbGetQuery
  local_mocked_bindings(dbGetQuery = function(conn, statement, ...) {
    native_query(conn, "SELECT * FROM identity")
  }, .package = "DBI")
  saved <- NULL
  shiny::testServer(app$server, session = multiple_session(fixture$cookie), {
    expect_error(output$sql_rows, class = "shiny.silent.error")
    expect_error(output$databricks_rows, class = "shiny.silent.error")
    session$setInputs(sql_id = fixture$ids$a, databricks_id = fixture$ids$warehouse)
    expect_match(output$sql_rows, ">\\s*A\\s*<")
    expect_match(output$databricks_rows, ">\\s*WAREHOUSE\\s*<")
    sql_a <- sql()
    saved <<- databricks()
    session$setInputs(sql_id = fixture$ids$b)
    expect_false(DBI::dbIsValid(sql_a))
    expect_match(output$sql_rows, ">\\s*B\\s*<")
    expect_identical(databricks(), saved)
    session$setInputs(disconnect_sql = 1L)
    expect_error(output$sql_rows, class = "shiny.silent.error")
    expect_match(output$databricks_rows, ">\\s*WAREHOUSE\\s*<")
    expect_identical(databricks(), saved)
    session$setInputs(disconnect_databricks = 1L)
    expect_error(output$databricks_rows, class = "shiny.silent.error")
    expect_false(DBI::dbIsValid(saved))
    expect_false(session$isClosed())
    expect_true(auth$connection(fixture$ids$a)$has_scopes("demo.read"))
  })
})
