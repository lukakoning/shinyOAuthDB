test_that("the self-hosted PostgreSQL example queries through the public helper", {
  skip_if_not_installed("RSQLite")
  withr::local_envvar(playground_env())
  local_mocked_bindings(
    oauth_provider_oidc_discover = function(issuer, ...) {
      shinyOAuth::oauth_provider(
        name = "postgres",
        auth_url = paste0(issuer, "/authorize"),
        token_url = paste0(issuer, "/token"),
        issuer = issuer,
        jwks_uri = paste0(issuer, "/jwks"),
        id_token_validation = TRUE,
        use_nonce = TRUE
      )
    },
    .package = "shinyOAuth"
  )
  calls <- list()
  handles <- list()
  local_mocked_bindings(
    .odb_postgres_runtime = function() TRUE,
    .odb_postgres_connection_valid = DBI::dbIsValid,
    .odb_postgres_connect_bearer = function(token, user, issuer, scope, ...) {
      calls[[length(calls) + 1L]] <<- list(
        token = token,
        user = user,
        issuer = issuer,
        scope = scope
      )
      native <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
      attr(native, "selected_credential") <- token
      handles[[length(handles) + 1L]] <<- native
      native
    }
  )
  local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      expect_match(statement, "information_schema.tables", fixed = TRUE)
      data.frame(database_user = attr(conn, "selected_credential"))
    },
    .package = "DBI"
  )
  app <- playground_load_example("example-postgres.R")
  expect_s3_class(app$app, "shiny.appobj")
  expect_identical(
    app$client@provider@issuer,
    playground_env()[["OAUTHDB_POSTGRES_ISSUER"]]
  )
  expect_match(app$ui(playground_request())$content, 'id="rows"', fixed = TRUE)
  actions <- new.env(parent = emptyenv())
  actions$login <- 0L
  app$oauth_module_server <- playground_module(actions)
  shiny::testServer(app$server, {
    session$setInputs(load = 1L)
    task_app_flush(session)
    expect_match(output$rows, "fixture-A", fixed = TRUE)
    session$setInputs(login = 1L)
    expect_identical(actions$login, 1L)
    actions$select("B")
    session$flushReact()
    expect_false(DBI::dbIsValid(handles[[1L]]))
    expect_error(output$rows, class = "shiny.silent.error")
    session$setInputs(load = 2L)
    task_app_flush(session)
    expect_match(output$rows, "fixture-B", fixed = TRUE)
    expect_false(grepl("fixture-A", output$rows, fixed = TRUE))
    session$setInputs(logout = 1L)
    expect_error(output$rows, class = "shiny.silent.error")
  })
  expect_identical(lapply(calls, `[[`, "token"), list("fixture-A", "fixture-B"))
  expect_identical(
    calls[[1L]]$issuer,
    playground_env()[["OAUTHDB_POSTGRES_ISSUER"]]
  )
  expect_identical(calls[[1L]]$scope, "database.read")
  expect_identical(lapply(calls, `[[`, "user"), list("A", "B"))
  expect_true(all(vapply(
    handles,
    function(native) !DBI::dbIsValid(native),
    logical(1)
  )))
})
