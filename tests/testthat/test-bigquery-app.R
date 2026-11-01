test_that("the BigQuery playground constructs a real Google client and follows sign-in", {
  withr::local_envvar(c(playground_env(), OAUTHDB_BIGQUERY_PROJECT = "billing"))
  app <- playground_load_example("example-bigquery.R")
  expect_s3_class(app$app, "shiny.appobj")
  expect_true("https://www.googleapis.com/auth/bigquery" %in% app$client@scopes)
  expect_match(app$ui(playground_request())$content, 'id="rows"', fixed = TRUE)
  calls <- new.env(parent = emptyenv())
  calls$login <- 0L
  app$oauth_module_server <- playground_module(calls)
  httr2::local_mocked_responses(function(req) {
    value <- httr2::req_get_headers(req, redacted = "reveal")$Authorization
    bq_test_response(bq_test_result(value))
  })
  shiny::testServer(app$server, {
    session$flushReact()
    expect_match(output$rows, "fixture-A", fixed = TRUE)
    calls$select("B")
    session$flushReact()
    expect_match(output$rows, "fixture-B", fixed = TRUE)
    expect_false(grepl("fixture-A", output$rows, fixed = TRUE))
    session$setInputs(logout = 1L)
    expect_error(output$rows, class = "shiny.silent.error")
  })
})
