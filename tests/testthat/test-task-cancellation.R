test_that("tasks can restart before obsolete credential acquisition settles", {
  for (cancel in c(FALSE, TRUE)) {
    for (reject in c(FALSE, TRUE)) {
      local({
        calls <- new.env(parent = emptyenv())
        task_mock_workers(calls)
        odb_test_domain(function(session) {
          settle <- NULL
          a <- odb_test_authorization(
            session,
            "A",
            refresh_token = "fixture-refresh",
            acquire = function(async = FALSE, ...) {
              expect_true(async)
              promises::promise(function(resolve, reject) {
                settle <<- list(resolve = resolve, reject = reject)
              })
            }
          )
          a$token(a$make_token("expired-A", lifetime = -1))
          b <- odb_test_authorization(session, "B")
          selected <- shiny::reactiveVal(a$connection)
          rows <- oauth_db_task(oauth_db_connect(selected, task_sqlite_connect))
          expect_true(rows$invoke("SELECT 1"))
          task_app_flush(session)
          expect_length(calls$pending, 0L)
          expect_identical(rows$status(), "running")
          if (cancel) {
            rows$cancel()
            expect_identical(rows$status(), "initial")
          }
          selected(b$connection)
          expect_true(rows$invoke("SELECT 2"))
          task_app_flush(session)
          expect_length(calls$pending, 1L)
          expect_identical(
            calls$pending[[1L]]$arguments$tokens,
            list("fixture-B")
          )
          if (reject) {
            settle$reject(simpleError("obsolete credential failure"))
          } else {
            a$token(a$make_token("renewed-A"))
            settle$resolve(TRUE)
          }
          task_app_flush(session)
          expect_identical(rows$status(), "running")
          expect_length(calls$pending, 1L)
          result <- data.frame(account = "B")
          calls$pending[[1L]]$resolve(result)
          task_app_flush(session)
          expect_identical(rows$result(), result)
        })
      })
    }
  }
})

test_that("obsolete worker completions cannot replace or cancel newer work", {
  for (reject in c(FALSE, TRUE)) {
    local({
      calls <- new.env(parent = emptyenv())
      task_mock_workers(calls)
      odb_test_domain(function(session) {
        auth <- odb_test_authorization(session)
        rows <- oauth_db_task(oauth_db_connect(
          auth$connection,
          task_sqlite_connect
        ))
        expect_true(rows$invoke("SELECT 1"))
        task_app_flush(session)
        rows$cancel()
        expect_equal(calls$stopped, 1L)
        expect_true(rows$invoke("SELECT 2"))
        task_app_flush(session)
        expect_length(calls$pending, 2L)
        if (reject) {
          calls$pending[[1L]]$reject(simpleError("obsolete worker failure"))
        } else {
          calls$pending[[1L]]$resolve(data.frame(value = "obsolete"))
        }
        task_app_flush(session)
        expect_identical(rows$status(), "running")
        rows$cancel()
        expect_equal(calls$stopped, 2L)
        expect_true(rows$invoke("SELECT 3"))
        task_app_flush(session)
        expect_length(calls$pending, 3L)
        result <- data.frame(value = "current")
        calls$pending[[3L]]$resolve(result)
        task_app_flush(session)
        calls$pending[[2L]]$resolve(data.frame(value = "cancelled"))
        task_app_flush(session)
        expect_identical(rows$result(), result)
      })
    })
  }
})
