test_that("Azure PostgreSQL replaces fixed credentials without replaying queries", {
  skip_if_not_installed("RPostgres")
  skip_if_not_installed("RSQLite")
  opened <- list()
  local_mocked_bindings(
    .odb_backend_postgres = function(token, ...) {
      connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
      DBI::dbWriteTable(
        connection,
        "identity",
        data.frame(credential = token())
      )
      opened[[length(opened) + 1L]] <<- connection
      connection
    }
  )
  for (target in list(NULL, "postgres")) {
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session, target = target)
      con <- oauth_db_azure_postgres(
        auth$connection,
        "postgres.example",
        "reporting",
        "readers",
        target = target
      )
      runs <- 0L
      rows <- shiny::reactive({
        runs <<- runs + 1L
        connection <- con()
        DBI::dbGetQuery(connection, "SELECT credential FROM identity")
      })
      expect_identical(rows()$credential, "fixture-A")
      first <- con()
      expect_identical(con(), first)
      auth$token(auth$make_token("replacement-A"))
      session$flushReact()
      expect_identical(rows()$credential, "fixture-A")
      expect_identical(runs, 1L)

      second <- con()
      expect_false(DBI::dbIsValid(first))
      expect_identical(
        DBI::dbGetQuery(second, "SELECT credential FROM identity")$credential,
        "replacement-A"
      )
      expect_identical(con(), second)
      expect_identical(runs, 1L)

      auth$current(FALSE)
      expect_error(con(), class = "shiny.silent.error")
      expect_false(DBI::dbIsValid(second))
    })
  }
  expect_length(opened, 4L)
  expect_true(all(vapply(opened, function(x) !DBI::dbIsValid(x), logical(1))))
})
