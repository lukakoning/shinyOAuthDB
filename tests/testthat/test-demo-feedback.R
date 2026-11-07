test_that("a failed write check remains retryable and isn't reported as a permission denial", {
  local_mocked_bindings(oauth_provider_oidc_discover = function(issuer, ...) {
    shinyOAuth::oauth_provider(name = "fixture", auth_url = "https://fixture.example/auth",
      token_url = "https://fixture.example/token")
  }, .package = "shinyOAuth")
  app <- new.env(parent = globalenv())
  eval(parse(system.file("docker", "libsql", "app.R", package = "shinyOAuthDB")), app)
  control <- new.env(parent = emptyenv())
  control$denied <- FALSE
  app$oauth_module_server <- function(...) {
    grant <- odb_test_authorization(shiny::getDefaultReactiveDomain(), scopes = "sqlite.read")
    state <- shiny::reactiveValues(error = NULL,
      token = shinyOAuth::OAuthToken(access_token = "fixture-A", userinfo = list(preferred_username = "alice")))
    state$connection <- function() if (is.null(state$token)) NULL else grant$connection
    state$request_login <- function() NULL
    state$logout <- function() { state$token <- NULL; grant$current(FALSE) }
    state
  }
  app$oauth_db_libsql_api <- function(authorization, ...) list(
    query = function(...) { shiny::req(authorization()); data.frame(marker = "sample row") },
    execute = function(...) {
      shiny::req(authorization())
      if (control$denied) .odb_abort("Denied", "request_failed", status = 403L)
      stop("Temporary connection failure")
    }
  )
  shiny::testServer(app$server, {
    session$flushReact()
    session$setInputs(probe = 1L)
    expect_match(output$permission, "Could not check write access", fixed = TRUE)
    expect_match(output$rows, "sample row", fixed = TRUE)
    expect_false(session$isClosed())
    control$denied <- TRUE
    session$setInputs(probe = 2L)
    expect_identical(output$permission, "Write rejected by database")
    session$setInputs(logout = 1L)
    expect_error(output$permission, class = "shiny.silent.error")
  })
})
