test_that("new tasks do not wait on the previous account's credential validation", {
  skip_if_not_installed("mirai", "2.5.1")
  for (sign_out in c(TRUE, FALSE)) {
    local({
      calls <- new.env(parent = emptyenv())
      task_mock_workers(calls)
      odb_test_domain(function(session) {
        resolve <- NULL
        a <- odb_test_authorization(
          session,
          "A",
          refresh_token = "fixture-refresh",
          acquire = function(async = FALSE, ...) {
            expect_true(async)
            promises::promise(function(yes, no) {
              resolve <<- yes
            })
          }
        )
        b <- odb_test_authorization(session, "B")
        a$token(a$make_token("expired-A", lifetime = -1))
        selected <- shiny::reactiveVal(a$connection)
        source <- oauth_db_connect(selected, task_sqlite_connect)
        first <- oauth_db_task(source)
        expect_true(first$invoke("SELECT 1"))
        task_app_flush(session)
        expect_length(calls$pending, 0L)
        if (sign_out) {
          selected(NULL)
          session$flushReact()
        }
        selected(b$connection)
        session$flushReact()
        second <- oauth_db_task(source)
        expect_true(second$invoke("SELECT 2"))
        task_app_flush(session)
        expect_length(calls$pending, 1L)
        expect_identical(
          calls$pending[[1L]]$arguments$tokens,
          list("fixture-B")
        )
        result <- data.frame(account = "B")
        calls$pending[[1L]]$resolve(result)
        task_app_flush(session)
        expect_identical(second$result(), result)
        a$token(a$make_token("renewed-A"))
        resolve(TRUE)
        task_app_flush(session)
        expect_length(calls$pending, 1L)
        expect_identical(second$result(), result)
        expect_identical(first$status(), "initial")
      })
    })
  }
})
