test_that("generic DBI connectors and methods work in task worker snapshots", {
  skip_if_not_installed("RSQLite")
  task_app_workers()
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    for (method in list("query", DBI::dbGetQuery)) {
      con <- oauth_db_connect(
        auth$connection,
        drv = RSQLite::SQLite(),
        dbname = ":memory:",
        disconnect = DBI::dbDisconnect
      )
      rows <- oauth_db_task(con, method = method)
      expect_true(rows$invoke("SELECT 42 AS value"))
      task_app_flush(session)
      expect_identical(rows$status(), "success")
      expect_identical(rows$result(), data.frame(value = 42L))
    }
  })
})

test_that("modified DBI generics cannot carry app state into workers", {
  generic <- DBI::dbConnect
  attr(generic, "session") <- new.env(parent = emptyenv())
  expect_error(
    .odb_task_snapshot(generic),
    class = "shinyOAuthDB_invalid_configuration"
  )
})
