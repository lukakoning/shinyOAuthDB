native_signal_protocol_call <- function(session, backend, operation) {
  auth <- if (backend == "fabric") {
    odb_test_fabric_authorization(session, services = "fabric")
  } else {
    odb_test_authorization(session)
  }
  if (backend == "connection") {
    return(oauth_db_connect(auth$connection, connect = operation))
  }
  api <- if (backend == "fabric") {
    skip_if_not_installed("fabricQueryR", "1.0.1")
    oauth_db_fabric_api(auth$connection, targets = c(fabric = "fabric"))
  } else {
    skip_if_not_installed("brickster", "0.2.14")
    oauth_db_databricks_api(auth$connection, "workspace.example")
  }
  function() api$call(operation)
}

test_that("raw safe diagnostics preserve native continuation and signaling semantics", {
  skip_if_not_installed("callr")
  skip_if_not_installed("pkgload")
  skip_if_not_installed("brickster", "0.2.14")
  skip_if_not_installed("fabricQueryR", "1.0.1")
  # A child process has no testthat warning handler, which itself cannot muffle
  # a raw signal. This checks continuation without adding an artificial restart.
  results <- callr::r(
    function(path, helpers) {
      if (is.null(path)) {
        loadNamespace("shinyOAuthDB")
      } else {
        pkgload::load_all(path, quiet = TRUE, helpers = FALSE)
      }
      fixtures <- new.env(parent = asNamespace("shinyOAuthDB"))
      sys.source(file.path(helpers, "helper-authorization.R"), envir = fixtures)
      sys.source(file.path(helpers, "helper-api.R"), envir = fixtures)
      results <- list()
      resolve <- function(invoke) {
        result <- withVisible(invoke())
        if (!promises::is.promising(result$value)) {
          return(result)
        }
        settled <- NULL
        promises::then(
          result$value,
          function(value, .visible) {
            settled <<- list(value = value, visible = .visible)
            NULL
          },
          function(error) {
            settled <<- list(error = conditionMessage(error))
            NULL
          }
        )
        deadline <- proc.time()[["elapsed"]] + 5
        while (is.null(settled) && proc.time()[["elapsed"]] < deadline) {
          later::run_now(0.01)
        }
        if (is.null(settled)) {
          stop("Native promise did not settle.")
        }
        settled
      }
      for (backend in c("connection", "databricks", "fabric")) {
        modes <- if (backend == "connection") "sync" else c("sync", "async")
        for (mode in modes) {
          for (kind in c("warning", "message")) {
            for (warn in c(0L, 2L)) {
              options(warn = warn)
              fixtures$odb_test_domain(function(session) {
                auth <- suppressWarnings(
                  if (backend == "fabric") {
                    fixtures$odb_test_fabric_authorization(
                      session,
                      services = "fabric"
                    )
                  } else {
                    fixtures$odb_test_authorization(session)
                  }
                )
                diagnostic <- structure(
                  list(
                    message = "Native notification",
                    call = NULL,
                    status = 7L
                  ),
                  class = c(paste0("native_", kind), kind, "condition")
                )
                operation <- function(token, ...) {
                  run <- function() {
                    if (is.function(token)) {
                      token("https://api.fabric.microsoft.com/.default")
                    }
                    signalCondition(diagnostic)
                    invisible(list(ok = TRUE))
                  }
                  if (mode == "async") {
                    promises::then(
                      promises::promise_resolve(NULL),
                      function(...) run()
                    )
                  } else {
                    run()
                  }
                }
                invoke <- if (backend == "connection") {
                  shinyOAuthDB::oauth_db_connect(
                    auth$connection,
                    connect = operation
                  )
                } else {
                  api <- if (backend == "fabric") {
                    shinyOAuthDB::oauth_db_fabric_api(
                      auth$connection,
                      targets = c(fabric = "fabric")
                    )
                  } else {
                    shinyOAuthDB::oauth_db_databricks_api(
                      auth$connection,
                      "workspace.example"
                    )
                  }
                  function() api$call(operation)
                }
                diagnostics <- list()
                capture <- function(condition) {
                  diagnostics[[length(diagnostics) + 1L]] <<- condition
                }
                result <- tryCatch(
                  withCallingHandlers(
                    resolve(invoke),
                    warning = capture,
                    message = capture
                  ),
                  error = function(error) list(error = conditionMessage(error))
                )
                results[[paste(backend, mode, kind, warn, sep = "/")]] <<- list(
                  result = result,
                  unchanged = identical(diagnostics, list(diagnostic))
                )
              })
            }
          }
        }
      }
      results
    },
    args = list(
      path = if (pkgload::is_dev_package("shinyOAuthDB")) {
        normalizePath(test_path("..", ".."), winslash = "/")
      },
      helpers = normalizePath(test_path(), winslash = "/")
    ),
    libpath = .libPaths(),
    user_profile = FALSE,
    system_profile = FALSE
  )
  expect_length(results, 20L)
  for (name in names(results)) {
    result <- results[[name]]
    expect_identical(result$result$value, list(ok = TRUE), info = name)
    expect_true(result$unchanged, info = name)
    if (!startsWith(name, "connection/")) {
      expect_false(result$result$visible, info = name)
    }
  }
})

test_that("raw diagnostics needing redaction stop safely without reaching callers", {
  for (backend in c("connection", "databricks", "fabric")) {
    for (kind in c("warning", "message")) {
      for (payload in c("message", "nested", "environment", "trace")) {
        odb_test_domain(function(session) {
          continued <- FALSE
          operation <- function(token, ...) {
            value <- if (is.function(token)) {
              token("https://api.fabric.microsoft.com/.default")
            } else {
              token
            }
            diagnostic <- structure(
              list(message = "Native notification", call = NULL, status = 7L),
              class = c(paste0("native_", kind), kind, "condition")
            )
            if (payload == "message") {
              diagnostic$message <- paste("Native notification", value)
            } else if (payload == "nested") {
              diagnostic$nested <- list(body = charToRaw(value))
            } else if (payload == "environment") {
              diagnostic$frame <- environment()
            } else {
              attr(diagnostic, "stack.trace") <- list(call("native", value))
            }
            signalCondition(diagnostic)
            continued <<- TRUE
            list(ok = TRUE)
          }
          invoke <- native_signal_protocol_call(session, backend, operation)
          diagnostics <- list()
          capture <- function(condition) {
            diagnostics[[length(diagnostics) + 1L]] <<- condition
            tryInvokeRestart(
              if (kind == "warning") "muffleWarning" else "muffleMessage"
            )
          }
          error <- tryCatch(
            withCallingHandlers(
              shiny::captureStackTraces(invoke()),
              warning = capture,
              message = capture
            ),
            error = identity
          )
          expect_s3_class(error, "shinyOAuthDB_unmufflable_diagnostic")
          expect_identical(error$reason, "unmufflable_diagnostic")
          expect_s3_class(error$parent, paste0("native_", kind))
          expect_identical(error$parent$status, 7L)
          expect_false(continued)
          expect_length(diagnostics, 0L)
          credential <- if (backend == "fabric") "A-fabric" else "fixture-A"
          expect_false(grepl(
            credential,
            rawToChar(serialize(error, NULL, ascii = TRUE)),
            fixed = TRUE
          ))
        })
      }
    }
  }
})

test_that("caller-provided muffling restarts still forward sanitized diagnostics", {
  for (kind in c("warning", "message")) {
    odb_test_domain(function(session) {
      operation <- function(token) {
        diagnostic <- if (kind == "warning") {
          simpleWarning(paste("Native notification", token))
        } else {
          simpleMessage(paste("Native notification", token))
        }
        restarts <- setNames(
          list(function() NULL),
          if (kind == "warning") {
            "muffleWarning"
          } else {
            "muffleMessage"
          }
        )
        do.call(
          withRestarts,
          c(list(expr = quote(signalCondition(diagnostic))), restarts)
        )
        list(ok = TRUE)
      }
      invoke <- native_signal_protocol_call(session, "connection", operation)
      diagnostics <- list()
      capture <- function(condition) {
        diagnostics[[length(diagnostics) + 1L]] <<- condition
        invokeRestart(
          if (kind == "warning") "muffleWarning" else "muffleMessage"
        )
      }
      result <- withCallingHandlers(
        invoke(),
        warning = capture,
        message = capture
      )
      expect_identical(result, list(ok = TRUE))
      expect_length(diagnostics, 1L)
      expect_identical(
        conditionMessage(diagnostics[[1L]]),
        "Native notification [REDACTED]"
      )
      expect_false(grepl(
        "fixture-A",
        rawToChar(serialize(diagnostics[[1L]], NULL, ascii = TRUE)),
        fixed = TRUE
      ))
    })
  }
})
