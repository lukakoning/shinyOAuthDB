test_that("credential acquisition starts a fresh worker budget and queueing consumes it", {
  skip_if_not_installed("mirai", "2.5.1")
  skip_if_not_installed("RSQLite")
  now <- 1000
  local_mocked_bindings(.odb_task_time = function() now)
  calls <- new.env(parent = emptyenv())
  task_mock_workers(calls)
  odb_test_domain(function(session) {
    resolve <- NULL
    auth <- odb_test_authorization(
      session,
      refresh_token = "fixture-refresh",
      acquire = function(async = FALSE, ...) {
        expect_true(async)
        promises::promise(function(yes, no) {
          resolve <<- yes
        })
      }
    )
    auth$token(auth$make_token("expired", lifetime = -1))
    con <- oauth_db_connect(
      auth$connection,
      task_sqlite_connect,
      min_valid_for = 0
    )
    rows <- oauth_db_task(con, min_valid_for = 3)
    rows$invoke("SELECT 1 AS value")
    task_app_flush(session)
    expect_length(calls$pending, 0L)
    now <<- now + 10
    auth$token(auth$make_token("fresh", lifetime = 3600))
    resolve(TRUE)
    task_app_flush(session)
    expect_length(calls$pending, 1L)
    worker <- calls$pending[[1L]]
    expect_identical(worker$arguments$until, 1013)
    expect_identical(worker$run(), data.frame(value = 1L))
    now <<- 1012
    expect_identical(worker$run(), data.frame(value = 1L))
    now <<- 1013
    expect_error(
      worker$run(),
      "token lifetime budget expired",
      class = "shinyOAuthDB_authorization_unavailable"
    )
  })
})

test_that("multi-service tasks budget each token from its own delivery time", {
  skip_if_not_installed("mirai", "2.5.1")
  skip_if_not_installed("fabricQueryR", "1.0.1")
  now <- 1000
  local_mocked_bindings(.odb_task_time = function() now)
  calls <- new.env(parent = emptyenv())
  task_mock_workers(calls)
  odb_test_domain(function(session) {
    resolve <- list()
    grant <- list(
      id = "pending-services",
      has_scopes = function(...) TRUE,
      summary = function() list(status = "active"),
      targets = function() {
        list(
          fabric = list(status = "active"),
          sql = list(status = "active")
        )
      },
      access_token = function(target, ...) {
        promises::promise(function(yes, no) {
          resolve[[target]] <<- yes
        })
      }
    )
    api <- oauth_db_fabric_api(
      grant,
      targets = c(fabric = "fabric", sql = "sql"),
      min_valid_for = 0
    )
    rows <- oauth_db_task(api, min_valid_for = 20)
    rows$invoke()
    task_app_flush(session)
    now <<- 1005
    resolve$fabric("first-token")
    task_app_flush(session)
    expect_length(calls$pending, 0L)
    now <<- 1010
    resolve$sql("second-token")
    task_app_flush(session)
    expect_length(calls$pending, 1L)
    expect_identical(calls$pending[[1L]]$arguments$until, c(1025, 1030))
  })
})

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
