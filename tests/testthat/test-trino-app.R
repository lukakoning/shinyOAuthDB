test_that("the Trino playground uses each selected profile and clears on sign-out", {
  skip_if_not_installed("RTrino", "0.1.0")
  withr::local_envvar(playground_env())
  local_mocked_bindings(
    oauth_provider_oidc_discover = function(issuer, ...) {
      shinyOAuth::oauth_provider(
        name = "trino",
        auth_url = paste0(issuer, "/authorize"),
        token_url = paste0(issuer, "/token"),
        userinfo_url = paste0(issuer, "/userinfo"),
        issuer = issuer,
        jwks_uri = paste0(issuer, "/jwks"),
        id_token_validation = TRUE,
        userinfo_required = TRUE,
        use_nonce = TRUE
      )
    },
    .package = "shinyOAuth"
  )
  app <- playground_load_example("example-trino.R")
  expect_s3_class(app$app, "shiny.appobj")
  expect_identical(
    app$client@provider@issuer,
    playground_env()[["OAUTHDB_TRINO_ISSUER"]]
  )
  expect_match(app$ui(playground_request())$content, 'id="rows"', fixed = TRUE)
  calls <- new.env(parent = emptyenv())
  calls$login <- 0L
  make_module <- playground_module(calls)
  app$oauth_module_server <- function(...) {
    original <- make_module(...)
    auth <- list2env(original, parent = emptyenv())
    makeActiveBinding(
      "token",
      function() {
        grant <- original$connection()
        if (is.null(grant)) {
          return(NULL)
        }
        value <- grant$access_token()
        shinyOAuth::OAuthToken(
          access_token = value,
          token_type = "Bearer",
          expires_at = as.numeric(Sys.time()) + 3600,
          userinfo = list(
            email = paste0(sub("^fixture-", "", value), "@example.org")
          )
        )
      },
      auth
    )
    auth
  }
  tokens <- character()
  httr2::local_mocked_responses(function(req) {
    tokens <<- c(
      tokens,
      httr2::req_get_headers(req, redacted = "reveal")$Authorization
    )
    trino_test_response(req)
  })
  retained <- NULL
  shiny::testServer(app$server, {
    session$flushReact()
    expect_match(output$rows, "A@example.org", fixed = TRUE)
    first <- con()
    calls$select("B")
    session$flushReact()
    expect_false(DBI::dbIsValid(first))
    expect_match(output$rows, "B@example.org", fixed = TRUE)
    expect_false(grepl("A@example.org", output$rows, fixed = TRUE))
    retained <<- con()
    session$setInputs(logout = 1L)
    expect_error(output$rows, class = "shiny.silent.error")
    expect_false(DBI::dbIsValid(retained))
  })
  expect_identical(
    tokens,
    c(
      "Bearer fixture-A",
      "Bearer fixture-A",
      "Bearer fixture-B",
      "Bearer fixture-B"
    )
  )
})
