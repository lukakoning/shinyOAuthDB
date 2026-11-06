test_that("the cloud app lists on sign-in but runs SQL only on a click and clears old output", {
  path <- cloud_demo_path()
  oauth_db_cloud_demo(host = "workspace.example", client_id = "client", path = path,
    action = "files", prompt = FALSE)
  control <- new.env(parent = emptyenv())
  control$list_calls <- control$connect_calls <- control$query_calls <- 0L
  local_mocked_bindings(oauth_db_databricks_client = function(...) {
    shinyOAuth::oauth_client(shinyOAuth::oauth_provider(name = "fixture",
      auth_url = "https://fixture.example/authorize", token_url = "https://fixture.example/token", token_auth_style = "public"),
      client_id = "fixture", redirect_uri = "http://localhost:8100")
  })
  local_mocked_bindings(dbGetQuery = function(conn, statement, ...) {
    control$query_calls <- control$query_calls + 1L
    expect_identical(statement, "SELECT current_user() AS signed_in_user")
    data.frame(signed_in_user = conn$user)
  }, .package = "DBI")
  envir <- new.env(parent = globalenv())
  old <- setwd(path)
  on.exit(setwd(old), add = TRUE)
  app <- eval(parse("app.R"), envir)
  expect_s3_class(app, "shiny.appobj")
  envir$oauth_module_server <- function(...) {
    session <- shiny::getDefaultReactiveDomain()
    a <- odb_test_authorization(session, id = "A", scopes = "sql")
    b <- odb_test_authorization(session, id = "B", scopes = "sql")
    control$a <- a
    selected <- shiny::reactiveVal(NULL)
    control$choose <- function(id) {
      a$current(id == "A")
      b$current(id == "B")
      selected(if (id == "A") a$connection else b$connection)
    }
    list(connection = selected, request_login = function() control$choose("A"),
      logout = function() { a$current(FALSE); b$current(FALSE); selected(NULL) })
  }
  envir$oauth_db_databricks_api <- function(authorization, ...) list(warehouses = function() {
    shiny::req(authorization())
    control$list_calls <- control$list_calls + 1L
    data.frame(id = "warehouse", name = "Reporting", state = "RUNNING")
  })
  envir$oauth_db_databricks <- function(authorization, ...) {
    control$connect_calls <- control$connect_calls + 1L
    function() list(user = shiny::req(authorization())$id)
  }
  shiny::testServer(envir$server, {
    session$flushReact()
    expect_identical(control$list_calls, 0L)
    expect_identical(control$connect_calls, 0L)
    expect_error(output$rows, class = "shiny.silent.error")
    control$choose("A")
    session$flushReact()
    expect_identical(control$list_calls, 1L)
    expect_identical(control$query_calls, 0L)
    expect_identical(control$connect_calls, 0L)
    session$setInputs(manual_warehouse = "", warehouse = "warehouse", run = 1L)
    expect_identical(control$query_calls, 1L)
    expect_match(output$rows, ">[[:space:]]*A[[:space:]]*<")
    session$setInputs(refresh = 1L)
    expect_identical(control$query_calls, 1L)
    control$a$token(control$a$make_token("fixture-A", permissions = character()))
    session$flushReact()
    expect_error(output$rows, class = "shiny.silent.error")
    control$a$token(control$a$make_token("fixture-A", permissions = "sql"))
    session$flushReact()
    expect_error(output$rows, class = "shiny.silent.error")
    expect_identical(control$query_calls, 1L)
    session$setInputs(logout = 1L)
    expect_error(output$rows, class = "shiny.silent.error")
    control$choose("B")
    session$flushReact()
    expect_error(output$rows, class = "shiny.silent.error")
    expect_identical(control$query_calls, 1L)
    session$setInputs(manual_warehouse = "/sql/1.0/warehouses/warehouse", run = 2L)
    expect_match(output$rows, ">[[:space:]]*B[[:space:]]*<")
    expect_false(grepl(">[[:space:]]*A[[:space:]]*<", output$rows))
    expect_identical(control$query_calls, 2L)
  })
})
