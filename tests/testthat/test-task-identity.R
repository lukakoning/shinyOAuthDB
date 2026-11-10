test_that("identity refresh withholds tasks without losing completed or arriving results", {
  skip_if_not_installed("mirai", "2.5.1")
  skip_if_not_installed("RTrino", "0.1.0")
  for (completed in c(TRUE, FALSE)) {
    for (user in c("alice", "alice-alias")) {
      local({
        calls <- new.env(parent = emptyenv())
        task_mock_workers(calls)
        odb_test_domain(function(session) {
          auth <- odb_test_identity(session)
          rows <- oauth_db_task(oauth_db_trino(
            auth$connection,
            "https://trino.example",
            "lake",
            "reports",
            user = auth$user
          ))
          expect_true(rows$invoke("SELECT 1"))
          task_app_flush(session)
          value <- data.frame(user = "alice")
          if (completed) {
            calls$pending[[1L]]$resolve(value)
            task_app_flush(session)
            expect_identical(rows$result(), value)
          }
          auth$status("refreshing")
          session$flushReact()
          expect_false(is.null(auth$token()))
          expect_identical(rows$status(), "initial")
          expect_error(rows$result(), class = "shiny.silent.error")
          expect_identical(calls$stopped, 0L)
          if (!completed) {
            calls$pending[[1L]]$resolve(value)
            task_app_flush(session)
          }
          auth$token(auth$identity_token(user))
          auth$status("active")
          task_app_flush(session)
          if (user == "alice") {
            expect_identical(rows$status(), "success")
            expect_identical(rows$result(), value)
          } else {
            expect_identical(rows$status(), "initial")
            expect_error(rows$result(), class = "shiny.silent.error")
          }
          expect_length(calls$pending, 1L)
        })
      })
    }
  }
})

test_that("sign-out during identity refresh still cancels a running task", {
  skip_if_not_installed("mirai", "2.5.1")
  skip_if_not_installed("RTrino", "0.1.0")
  calls <- new.env(parent = emptyenv())
  task_mock_workers(calls)
  odb_test_domain(function(session) {
    auth <- odb_test_identity(session)
    rows <- oauth_db_task(oauth_db_trino(
      auth$connection,
      "https://trino.example",
      "lake",
      "reports",
      user = auth$user
    ))
    rows$invoke("SELECT 1")
    task_app_flush(session)
    auth$status("refreshing")
    session$flushReact()
    expect_identical(calls$stopped, 0L)
    auth$current(FALSE)
    session$flushReact()
    expect_identical(calls$stopped, 1L)
    calls$pending[[1L]]$resolve(data.frame(user = "alice"))
    auth$current(TRUE)
    auth$status("active")
    task_app_flush(session)
    expect_identical(rows$status(), "initial")
    expect_error(rows$result(), class = "shiny.silent.error")
  })
})
