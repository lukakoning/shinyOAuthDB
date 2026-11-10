test_that("the Fabric Lakehouse recipe looks up its item and returns worker data", {
  skip_if_not_installed("fabricQueryR", "1.0.1")
  skip_if_not_installed("mirai", "2.5.1")
  task_app_workers()
  chunk <- vignette_recipe_chunk("fabric", "lakehouse")
  requests <- character()
  httr2::local_mocked_responses(function(req) {
    requests <<- c(requests, req$url)
    path <- httr2::url_parse(req$url)$path
    workspace <- list(
      id = "11111111-1111-1111-1111-111111111111",
      displayName = "workspace-guid"
    )
    item <- list(
      id = "22222222-2222-2222-2222-222222222222",
      workspaceId = workspace$id,
      displayName = "lakehouse-guid",
      type = "Lakehouse"
    )
    body <- if (grepl("/items", path, fixed = TRUE)) {
      list(value = list(item))
    } else if (endsWith(path, "/workspaces")) {
      list(value = list(workspace))
    } else if (endsWith(path, paste0("/workspaces/", workspace$id))) {
      workspace
    } else {
      item
    }
    odb_http_response(as.character(jsonlite::toJSON(body, auto_unbox = TRUE)))
  })
  local_mocked_bindings(
    fabric_lakehouse_read_table = function(lakehouse, table, limit, ...) {
      expect_s3_class(lakehouse, "FabricLakehouse")
      expect_identical(table, "Orders")
      expect_identical(limit, 100L)
      data.frame(order_id = 42L)
    },
    .package = "fabricQueryR"
  )
  server <- function(input, output, session) {
    auth <- odb_test_fabric_authorization(
      session,
      services = c("fabric", "onelake")
    )
    observeEvent <- shiny::observeEvent
    renderTable <- shiny::renderTable
    eval(chunk)
  }
  shiny::testServer(server, {
    session$setInputs(load = 1L)
    task_app_flush(session)
    expect_identical(lakehouse_task$result(), data.frame(order_id = 42L))
  })
  expect_true(length(requests) > 0L)
})
