test_that("native warnings and messages redact credentials without losing diagnostics", {
  for (backend in c("connection", "databricks", "fabric")) {
    if (backend == "databricks") {
      skip_if_not_installed("brickster", "0.2.14")
    }
    if (backend == "fabric") {
      skip_if_not_installed("fabricQueryR", "1.0.1")
    }
    for (kind in c("warning", "message")) {
      for (fail in c(FALSE, TRUE)) {
        odb_test_domain(function(session) {
          auth <- if (backend == "fabric") {
            odb_test_fabric_authorization(session, services = "fabric")
          } else {
            odb_test_authorization(session)
          }
          credential <- if (backend == "fabric") "A-fabric" else "fixture-A"
          operation <- function(token, ...) {
            value <- if (is.function(token)) {
              token("https://api.fabric.microsoft.com/.default")
            } else {
              token
            }
            diagnostic <- structure(
              list(
                message = paste("Driver diagnostic", value),
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
            if (fail) {
              stop("Failure after diagnostic")
            }
            invisible(list(ok = TRUE))
          }
          invoke <- if (backend == "connection") {
            oauth_db_connect(auth$connection, connect = operation)
          } else {
            api <- if (backend == "fabric") {
              oauth_db_fabric_api(
                auth$connection,
                targets = c(fabric = "fabric")
              )
            } else {
              oauth_db_databricks_api(auth$connection, "workspace.example")
            }
            function() api$call(operation)
          }
          diagnostics <- list()
          capture <- function(condition) {
            diagnostics[[length(diagnostics) + 1L]] <<- condition
            invokeRestart(
              if (kind == "warning") "muffleWarning" else "muffleMessage"
            )
          }
          result <- tryCatch(
            withCallingHandlers(
              withVisible(shiny::captureStackTraces(invoke())),
              warning = capture,
              message = capture
            ),
            error = identity
          )
          if (fail) {
            expect_s3_class(result, "error")
            expect_identical(
              conditionMessage(result),
              "Failure after diagnostic"
            )
          } else {
            expect_identical(result$value, list(ok = TRUE))
            if (backend != "connection") expect_false(result$visible)
          }
          expect_length(diagnostics, 1L)
          diagnostic <- diagnostics[[1L]]
          expect_s3_class(diagnostic, paste0("native_", kind))
          expect_identical(diagnostic$status, 7L)
          expect_identical(
            conditionMessage(diagnostic),
            "Driver diagnostic [REDACTED]"
          )
          expect_identical(
            conditionCall(diagnostic),
            call("native", "[REDACTED]")
          )
          expect_null(diagnostic$frame)
          expect_false(grepl(
            credential,
            rawToChar(serialize(diagnostic, NULL, ascii = TRUE)),
            fixed = TRUE
          ))
        })
      }
    }
  }
})

test_that("native warning redaction preserves warn-as-error behavior", {
  withr::local_options(warn = 2L)
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    credential <- paste(format(openssl::rand_bytes(24)), collapse = "")
    auth$token(auth$make_token(credential))
    con <- oauth_db_connect(auth$connection, function(token) {
      warning(paste("Driver diagnostic", token))
      list(ok = TRUE)
    })
    error <- tryCatch(shiny::captureStackTraces(con()), error = identity)
    expect_s3_class(error, "error")
    expect_match(conditionMessage(error), "[REDACTED]", fixed = TRUE)
    expect_false(grepl(
      credential,
      rawToChar(serialize(error, NULL, ascii = TRUE)),
      fixed = TRUE
    ))
  })
})

test_that("worker connection and operation diagnostics redact token snapshots", {
  for (kind in c("warning", "message")) {
    for (phase in c("connect", "query")) {
      credential <- paste(format(openssl::rand_bytes(24)), collapse = "")
      emit <- function(value) {
        diagnostic <- structure(
          list(
            message = paste("Worker diagnostic", value),
            body = charToRaw(value)
          ),
          class = c(paste0("native_", kind), kind, "condition")
        )
        if (kind == "warning") warning(diagnostic) else message(diagnostic)
      }
      worker <- list(
        type = "native",
        connect = function(token) {
          value <- token()
          if (phase == "connect") {
            emit(value)
          }
          list(token = value)
        },
        args = list(),
        disconnect = NULL,
        scopes = list(character())
      )
      diagnostic <- NULL
      capture <- function(condition) {
        diagnostic <<- condition
        invokeRestart(
          if (kind == "warning") "muffleWarning" else "muffleMessage"
        )
      }
      result <- withCallingHandlers(
        .odb_task_job(
          worker,
          list(credential),
          .odb_task_time() + 60,
          method = function(connection) {
            if (phase == "query") {
              emit(connection$token)
            }
            TRUE
          },
          arguments = list()
        ),
        warning = capture,
        message = capture
      )
      expect_identical(result, list(ok = TRUE, value = TRUE))
      expect_s3_class(diagnostic, paste0("native_", kind))
      expect_identical(
        conditionMessage(diagnostic),
        "Worker diagnostic [REDACTED]"
      )
      expect_false(grepl(
        credential,
        rawToChar(serialize(diagnostic, NULL, ascii = TRUE)),
        fixed = TRUE
      ))
    }
  }
})
