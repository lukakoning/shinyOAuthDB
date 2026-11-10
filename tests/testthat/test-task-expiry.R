test_that("expired task credentials renew asynchronously before dispatch", {
  skip_if_not_installed("mirai", "2.5.1")
  for (target in list(NULL, "data")) {
    for (lifetime in c(-1, NA_real_)) {
      local({
        calls <- new.env(parent = emptyenv())
        task_mock_workers(calls)
        odb_test_domain(function(session) {
          resolve <- NULL
          auth <- odb_test_authorization(
            session,
            target = target,
            refresh_token = "fixture-refresh",
            acquire = function(async = FALSE, ...) {
              expect_true(async)
              promises::promise(function(fulfilled, rejected) {
                resolve <<- fulfilled
              })
            }
          )
          auth$token(auth$make_token("expired", lifetime = lifetime))
          rows <- oauth_db_task(oauth_db_connect(
            auth$connection,
            task_sqlite_connect,
            target = target
          ))
          expect_true(rows$invoke("SELECT 1"))
          task_app_flush(session)
          expect_true(is.function(resolve))
          expect_identical(rows$status(), "running")
          expect_length(calls$pending, 0L)
          auth$token(auth$make_token("renewed"))
          resolve(TRUE)
          task_app_flush(session)
          expect_length(calls$pending, 1L)
          expect_identical(
            calls$pending[[1L]]$arguments$tokens,
            list("renewed")
          )
          calls$pending[[1L]]$resolve(data.frame(value = 1L))
          task_app_flush(session)
          expect_identical(rows$result(), data.frame(value = 1L))
        })
      })
    }
  }
})

test_that("pending expiry validation waits without losing completed or arriving results", {
  skip_if_not_installed("mirai", "2.5.1")
  for (completed in c(TRUE, FALSE)) {
    local({
      calls <- new.env(parent = emptyenv())
      task_mock_workers(calls)
      odb_test_domain(function(session) {
        resolve <- NULL
        auth <- odb_test_authorization(
          session,
          refresh_token = "fixture-refresh",
          acquire = function(async = FALSE, ...) {
            expect_true(async)
            promises::promise(function(fulfilled, rejected) {
              resolve <<- fulfilled
            })
          }
        )
        rows <- oauth_db_task(oauth_db_connect(
          auth$connection,
          task_sqlite_connect
        ))
        expect_true(rows$invoke("SELECT 1"))
        task_app_flush(session)
        value <- data.frame(value = "original result")
        if (completed) {
          calls$pending[[1L]]$resolve(value)
          task_app_flush(session)
          expect_identical(rows$result(), value)
        }
        auth$token(auth$make_token("expired", lifetime = -1))
        expect_error(rows$result(), class = "shiny.silent.error")
        expect_identical(rows$status(), "initial")
        task_app_flush(session)
        expect_true(is.function(resolve))
        expect_identical(calls$stopped, 0L)
        if (!completed) {
          calls$pending[[1L]]$resolve(value)
          task_app_flush(session)
        }
        expect_error(rows$result(), class = "shiny.silent.error")
        auth$token(auth$make_token("renewed"))
        resolve(TRUE)
        task_app_flush(session)
        expect_identical(rows$status(), "success")
        expect_identical(rows$result(), value)
        expect_length(calls$pending, 1L)
      })
    })
  }
})

test_that("asynchronous expiry validation still retires missing client and target permissions", {
  skip_if_not_installed("mirai", "2.5.1")
  for (target in list(NULL, "data")) {
    for (lifetime in c(-1, NA_real_)) {
      local({
        calls <- new.env(parent = emptyenv())
        task_mock_workers(calls)
        odb_test_domain(function(session) {
          auth <- odb_test_authorization(
            session,
            scopes = c("essential", "read"),
            target = target,
            client_required_scopes = if (is.null(target)) {
              "essential"
            } else {
              character()
            },
            refresh_token = "fixture-refresh",
            acquire = function(...) stop("Denied permissions must not renew")
          )
          rows <- oauth_db_task(oauth_db_connect(
            auth$connection,
            task_sqlite_connect,
            target = target,
            required_scopes = auth$scopes[[2L]]
          ))
          rows$invoke("SELECT 1")
          task_app_flush(session)
          calls$pending[[1L]]$resolve(data.frame(value = 1L))
          task_app_flush(session)
          expect_identical(rows$status(), "success")
          auth$token(auth$make_token(
            "denied",
            auth$scopes[[2L]],
            lifetime = lifetime
          ))
          expect_error(rows$result(), class = "shiny.silent.error")
          task_app_flush(session)
          expect_identical(rows$status(), "initial")
          expect_identical(auth$calls$acquire, 0L)
          auth$token(auth$make_token("restored"))
          task_app_flush(session)
          expect_error(rows$result(), class = "shiny.silent.error")
        })
      })
    }
  }
})
