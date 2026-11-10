test_that("same-identity refresh preserves native connections and pending transactions", {
  skip_if_not_installed("RSQLite")
  odb_test_domain(function(session) {
    auth <- odb_test_identity(session)
    broken <- shiny::reactiveVal(FALSE)
    con <- .odb_bind(
      auth$connection,
      function(token) DBI::dbConnect(RSQLite::SQLite(), ":memory:"),
      identity_key = function() {
        if (broken()) {
          stop("Username lookup failed")
        }
        auth$user()
      }
    )
    first <- con()
    DBI::dbBegin(first)
    DBI::dbExecute(first, "CREATE TEMP TABLE pending (value INTEGER)")
    auth$status("refreshing")
    session$flushReact()
    expect_true(DBI::dbIsValid(first))
    ready <- shiny::reactive(con())
    expect_error(ready(), class = "shiny.silent.error")
    auth$token(auth$identity_token())
    auth$status("active")
    session$flushReact()
    expect_identical(ready(), first)
    expect_true(DBI::dbExistsTable(first, "pending"))
    DBI::dbRollback(first)
    auth$token(auth$identity_token("alice-alias"))
    session$flushReact()
    expect_false(DBI::dbIsValid(first))
    replacement <- con()
    expect_true(DBI::dbIsValid(replacement))
    broken(TRUE)
    session$flushReact()
    expect_false(DBI::dbIsValid(replacement))
    expect_error(con(), "Username lookup failed", fixed = TRUE)
  })
})
