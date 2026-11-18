async_signal_await <- function(pending) {
  result <- new.env(parent = emptyenv())
  result$done <- FALSE
  pending$then(
    function(value, .visible) {
      result$value <- value
      result$visible <- .visible
      result$done <- TRUE
      NULL
    },
    function(error) {
      result$error <- error
      result$done <- TRUE
      NULL
    }
  )
  deadline <- proc.time()[["elapsed"]] + 5
  while (!result$done && proc.time()[["elapsed"]] < deadline) {
    later::run_now(0.01)
  }
  expect_true(result$done)
  as.list(result)
}

async_signal_client <- function(session, backend) {
  skip_if_not_installed(
    if (backend == "fabric") "fabricQueryR" else "brickster",
    if (backend == "fabric") "1.0.1" else "0.2.14"
  )
  if (backend == "fabric") {
    auth <- odb_test_fabric_authorization(session, services = "fabric")
    oauth_db_fabric_api(auth$connection, targets = c(fabric = "fabric"))
  } else {
    auth <- odb_test_authorization(session)
    oauth_db_databricks_api(auth$connection, "workspace.example")
  }
}

test_that("deferred native diagnostics stay redacted in their owning Shiny session", {
  for (backend in c("databricks", "fabric")) {
    for (kind in c("warning", "message")) {
      for (branch in c("fulfilled", "rejected")) {
        session <- shiny::MockShinySession$new()
        tryCatch(
          {
            observed_domains <- list()
            pending <- shiny::withReactiveDomain(
              session,
              shiny::isolate({
                api <- async_signal_client(session, backend)
                api$call(function(token, ...) {
                  initial <- if (branch == "fulfilled") {
                    promises::promise_resolve(NULL)
                  } else {
                    promises::promise_reject(simpleError("Native retry"))
                  }
                  continue <- function(...) {
                    observed_domains[[1L]] <<- shiny::getDefaultReactiveDomain()
                    promises::then(
                      promises::promise_resolve(NULL),
                      function(...) {
                        observed_domains[[
                          2L
                        ]] <<- shiny::getDefaultReactiveDomain()
                        value <- if (is.function(token)) {
                          token("https://api.fabric.microsoft.com/.default")
                        } else {
                          token
                        }
                        diagnostic <- structure(
                          list(
                            message = paste("Deferred diagnostic", value),
                            call = call("native", value),
                            body = charToRaw(value),
                            nested = list(credential = value),
                            frame = environment(),
                            status = 7L
                          ),
                          class = c(paste0("native_", kind), kind, "condition")
                        )
                        if (kind == "warning") {
                          warning(diagnostic)
                        } else {
                          message(diagnostic)
                        }
                        invisible(list(ok = TRUE))
                      }
                    )
                  }
                  promises::then(
                    initial,
                    onFulfilled = if (branch == "fulfilled") continue,
                    onRejected = if (branch == "rejected") continue
                  )
                })
              })
            )
            diagnostics <- list()
            capture <- function(condition) {
              diagnostics[[length(diagnostics) + 1L]] <<- condition
              invokeRestart(
                if (kind == "warning") "muffleWarning" else "muffleMessage"
              )
            }
            result <- withCallingHandlers(
              async_signal_await(pending),
              warning = capture,
              message = capture
            )
            expect_null(result$error)
            expect_identical(result$value, list(ok = TRUE))
            expect_false(result$visible)
            expect_identical(observed_domains, list(session, session))
            expect_length(diagnostics, 1L)
            diagnostic <- diagnostics[[1L]]
            expect_s3_class(diagnostic, paste0("native_", kind))
            expect_identical(diagnostic$status, 7L)
            expect_match(
              conditionMessage(diagnostic),
              "[REDACTED]",
              fixed = TRUE
            )
            expect_identical(
              conditionCall(diagnostic),
              call("native", "[REDACTED]")
            )
            expect_null(diagnostic$frame)
            credential <- if (backend == "fabric") "A-fabric" else "fixture-A"
            expect_false(grepl(
              credential,
              rawToChar(serialize(diagnostic, NULL, ascii = TRUE)),
              fixed = TRUE
            ))
          },
          finally = session$close()
        )
      }
    }
  }
})

test_that("deferred native warnings converted to errors stay redacted", {
  withr::local_options(warn = 2L)
  for (backend in c("databricks", "fabric")) {
    odb_test_domain(function(session) {
      api <- async_signal_client(session, backend)
      pending <- api$call(function(token, ...) {
        promises::then(promises::promise_resolve(NULL), function(...) {
          value <- if (is.function(token)) {
            token("https://api.fabric.microsoft.com/.default")
          } else {
            token
          }
          warning(paste("Deferred diagnostic", value))
        })
      })
      result <- async_signal_await(pending)
      expect_s3_class(result$error, "error")
      expect_match(conditionMessage(result$error), "[REDACTED]", fixed = TRUE)
      credential <- if (backend == "fabric") "A-fabric" else "fixture-A"
      expect_false(grepl(
        credential,
        rawToChar(serialize(result$error, NULL, ascii = TRUE)),
        fixed = TRUE
      ))
    })
  }
})
