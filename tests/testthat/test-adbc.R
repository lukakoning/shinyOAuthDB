test_that("ADBC cleanup closes outstanding DBI and Arrow results", {
  skip_if_not_installed("adbi")
  skip_if_not_installed("duckdb")
  withr::local_options(adbi.force_close_results = FALSE)

  for (send in list(DBI::dbSendQuery, DBI::dbSendQueryArrow)) {
    for (transition in c("replace", "logout", "permissions", "session_end")) {
      odb_test_domain(function(session) {
        a <- odb_test_authorization(session)
        b <- odb_test_authorization(session, "B")
        selected <- shiny::reactiveVal(a$connection)
        con <- oauth_db_connect(
          selected,
          required_scopes = "read",
          connect = function(token) {
            DBI::dbConnect(adbi::adbi(duckdb::duckdb_adbc()))
          }
        )
        native <- con()
        on.exit({
          if (DBI::dbIsValid(native)) {
            suppressWarnings(DBI::dbDisconnect(native, force = TRUE))
          }
        }, add = TRUE)
        result <- send(native, "SELECT 42 AS answer")
        expect_true(DBI::dbIsValid(result))

        switch(
          transition,
          replace = selected(b$connection),
          logout = selected(NULL),
          permissions = a$token(a$make_token("denied", "write")),
          session_end = session$close()
        )
        if (transition != "session_end") {
          session$flushReact()
        }
        expect_false(DBI::dbIsValid(native), info = transition)
        expect_false(DBI::dbIsValid(result), info = transition)
      })
    }
  }
})

test_that("custom cleanup still owns ADBC connections", {
  skip_if_not_installed("adbi")
  skip_if_not_installed("duckdb")
  native <- DBI::dbConnect(adbi::adbi(duckdb::duckdb_adbc()))
  on.exit(DBI::dbDisconnect(native, force = TRUE), add = TRUE)
  cleaned <- NULL
  .odb_disconnect(native, function(value) cleaned <<- value)
  expect_identical(cleaned, native)
  expect_true(DBI::dbIsValid(native))
})
