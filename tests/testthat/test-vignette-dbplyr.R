test_that("the Azure SQL dbplyr recipe runs as a task worker", {
  skip_if_not_installed("dplyr")
  skip_if_not_installed("dbplyr")
  skip_if_not_installed("RSQLite")
  skip_if_not_installed("mirai", "2.5.1")
  task_app_workers()
  chunk <- vignette_recipe_chunk("azure-sql", "dbplyr-query")
  connect <- function(token) {
    connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    DBI::dbWriteTable(
      connection,
      "Orders",
      data.frame(amount = c(50, 100, 101, 200))
    )
    connection
  }
  server <- function(input, output, session) {
    auth <- odb_test_authorization(session)
    con <- oauth_db_connect(auth$connection, connect = connect)
    observeEvent <- shiny::observeEvent
    renderTable <- shiny::renderTable
    eval(chunk)
  }
  shiny::testServer(server, {
    session$setInputs(load = 1L)
    task_app_flush(session)
    expect_identical(query_task$result()$amount, c(101, 200))
  })
})
