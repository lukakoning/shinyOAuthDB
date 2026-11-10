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

test_that("identity refresh does not replay completed native queries", {
  skip_if_not_installed("RTrino", "0.1.0")
  httr2::local_mocked_responses(function(req) trino_test_response(req))
  odb_test_domain(function(session) {
    auth <- odb_test_identity(session)
    con <- oauth_db_trino(
      auth$connection,
      "https://trino.example",
      "lake",
      "reports",
      user = auth$user
    )
    queries <- 0L
    rows <- shiny::reactive({
      native <- con()
      queries <<- queries + 1L
      DBI::dbGetQuery(native, "SELECT current_user")
    })
    first <- rows()
    auth$status("refreshing")
    session$flushReact()
    renewed <- auth$identity_token()
    renewed@access_token <- "renewed-identity"
    auth$token(renewed)
    auth$status("active")
    session$flushReact()
    expect_identical(rows(), first)
    expect_identical(queries, 1L)
  })
})
