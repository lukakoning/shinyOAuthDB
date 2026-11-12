test_that("the Fabric workspace recipe returns nonempty worker data and clears on sign-out", {
  skip_if_not_installed("fabricQueryR", "1.0.1")
  task_app_workers()
  chunk <- vignette_recipe_chunk("fabric", "workspaces")
  requests <- 0L
  httr2::local_mocked_responses(function(req) {
    requests <<- requests + 1L
    expect_identical(
      httr2::req_get_headers(req, redacted = "reveal")$Authorization,
      "Bearer A-fabric"
    )
    odb_http_response(paste0(
      '{"value":[{"id":"11111111-1111-1111-1111-111111111111",',
      '"displayName":"Reporting"}]}'
    ))
  })
  server <- function(input, output, session) {
    grant <- odb_test_fabric_authorization(session, services = "fabric")
    selected <- shiny::reactiveVal(grant$connection)
    auth <- list(connection = function() selected())
    observeEvent <- shiny::observeEvent
    renderPrint <- shiny::renderPrint
    eval(chunk)
  }
  shiny::testServer(server, {
    expect_identical(workspace_task$status(), "initial")
    session$setInputs(load = 1L)
    task_app_flush(session)
    result <- workspace_task$result()
    expect_identical(workspace_task$status(), "success")
    expect_s3_class(result[[1L]], "fabric_workspace")
    expect_identical(result[[1L]]$displayName, "Reporting")
    expect_match(output$workspaces, "Reporting", fixed = TRUE)
    selected(NULL)
    task_app_flush(session)
    expect_identical(workspace_task$status(), "initial")
    expect_error(workspace_task$result(), class = "shiny.silent.error")
    expect_error(output$workspaces, class = "shiny.silent.error")
  })
  expect_identical(requests, 1L)
})
