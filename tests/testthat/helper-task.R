task_sqlite_connect <- eval(
  quote(function(token) {
    con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    DBI::dbWriteTable(
      con,
      "identity",
      data.frame(token = token, pid = Sys.getpid())
    )
    con
  }),
  envir = globalenv()
)

task_flush <- function() {
  for (i in seq_len(15L)) {
    later::run_now(0.001)
  }
}

task_mock_workers <- function(calls, envir = parent.frame()) {
  calls$pending <- list()
  calls$stopped <- 0L
  testthat::local_mocked_bindings(
    daemons_set = function(...) TRUE,
    mirai = function(.expr, ..., .compute = NULL) {
      arguments <- list(...)
      promises::promise(function(resolve, reject) {
        calls$pending[[length(calls$pending) + 1L]] <- list(
          resolve = function(value) resolve(list(ok = TRUE, value = value)),
          reject = reject,
          arguments = arguments,
          run = function() do.call(.odb_task_run, arguments)
        )
      })
    },
    stop_mirai = function(job) {
      calls$stopped <- calls$stopped + 1L
    },
    .package = "mirai",
    .env = envir
  )
}


task_app_workers <- function(envir = parent.frame()) {
  testthat::local_mocked_bindings(
    daemons_set = function(...) TRUE,
    daemons = function(...) invisible(TRUE),
    mirai = function(.expr, ..., .compute = NULL) {
      expression <- substitute(.expr)
      arguments <- list(...)
      promises::then(promises::promise_resolve(NULL), function(...) {
        eval(expression, list2env(arguments, parent = baseenv()))
      })
    },
    stop_mirai = function(...) invisible(NULL),
    .package = "mirai",
    .env = envir
  )
}

task_app_flush <- function(session) {
  for (i in seq_len(25L)) {
    later::run_now(0.001)
    session$flushReact()
  }
}
