test_that("module accessors can be supplied outside a reactive consumer during server setup", {
  session <- shiny::MockShinySession$new()
  on.exit(session$close(), add = TRUE)
  shiny::withReactiveDomain(session, {
    grant <- odb_test_authorization(session)
    module <- shiny::reactiveValues(connection = function() grant$connection)
    con <- oauth_db_connect(module$connection, connect = function(token) {
      list(token = token)
    })
    expect_identical(shiny::isolate(con()), list(token = "fixture-A"))
    grant$current(FALSE)
    expect_error(shiny::isolate(con()), class = "shiny.silent.error")
  })
})
