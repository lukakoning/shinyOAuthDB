test_that("a failed write check remains retryable and isn't reported as a permission denial", {
  task_app_workers()
  local_mocked_bindings(
    oauth_provider_oidc_discover = function(issuer, ...) {
      shinyOAuth::oauth_provider(
        name = "fixture",
        auth_url = "https://fixture.example/auth",
        token_url = "https://fixture.example/token"
      )
    },
    .package = "shinyOAuth"
  )
  app <- new.env(parent = globalenv())
  eval(
    parse(system.file("docker", "libsql", "app.R", package = "shinyOAuthDB")),
    app
  )
  control <- new.env(parent = emptyenv())
  control$denied <- FALSE
  app$oauth_module_server <- function(...) {
    grant <- odb_test_authorization(
      shiny::getDefaultReactiveDomain(),
      scopes = "sqlite.read"
    )
    state <- shiny::reactiveValues(
      error = NULL,
      token = shinyOAuth::OAuthToken(
        access_token = "fixture-A",
        userinfo = list(preferred_username = "alice")
      )
    )
    state$connection <- function() {
      if (is.null(state$token)) NULL else grant$connection
    }
    state$request_login <- function() NULL
    state$logout <- function() {
      state$token <- NULL
      grant$current(FALSE)
    }
    state
  }
  app$oauth_db_libsql_api <- function(authorization, ...) {
    oauth_db_libsql_api(
      authorization,
      "https://data.example",
      required_scopes = "sqlite.read"
    )
  }
  httr2::local_mocked_responses(function(req) {
    body <- req$body$data
    if (startsWith(body$requests[[1L]]$stmt$sql, "INSERT")) {
      if (control$denied) {
        return(odb_http_response("{}", status = 403L))
      }
      stop("Temporary connection failure")
    }
    odb_http_response(paste0(
      '{"baton":null,"results":[{"type":"ok","response":{"type":"execute",',
      '"result":{"cols":[{"name":"marker"}],"rows":[[{"type":"text",',
      '"value":"sample row"}]],"affected_row_count":0,"last_insert_rowid":null}}},',
      '{"type":"ok","response":{"type":"close"}}]}'
    ))
  })
  shiny::testServer(app$server, {
    session$flushReact()
    session$setInputs(load = 1L, probe = 1L)
    task_app_flush(session)
    expect_match(
      output$permission,
      "Could not check write access",
      fixed = TRUE
    )
    expect_match(output$rows, "sample row", fixed = TRUE)
    expect_false(session$isClosed())
    control$denied <- TRUE
    session$setInputs(probe = 2L)
    task_app_flush(session)
    expect_identical(output$permission, "Write rejected by database")
    session$setInputs(logout = 1L)
    expect_error(output$permission, class = "shiny.silent.error")
  })
})
