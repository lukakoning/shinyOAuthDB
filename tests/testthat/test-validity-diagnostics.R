test_that("cached validity diagnostics cannot disclose earlier credentials", {
  skip_if_not_installed("RSQLite")
  for (custom in c(TRUE, FALSE)) {
    for (warn in c(0L, 2L)) {
      local({
        diagnostics <- list()
        checked <- 0L
        probe <- function(native) {
          checked <<- checked + 1L
          credential <- attr(native, "fixture_credential")
          warning(paste("Validity warning", credential), call. = FALSE)
          message(paste("Validity message", credential))
          TRUE
        }
        if (!custom) {
          local_mocked_bindings(dbIsValid = probe, .package = "DBI")
        }
        odb_test_domain(function(session) {
          auth <- odb_test_authorization(session)
          con <- .odb_bind(
            auth$connection,
            connect = function(token) {
              native <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
              attr(native, "fixture_credential") <- token()
              native
            },
            is_valid = if (custom) probe else NULL
          )
          first <- con()
          auth$token(auth$make_token("replacement-token"))
          session$flushReact()
          capture <- function(condition) {
            diagnostics[[length(diagnostics) + 1L]] <<- condition
            invokeRestart(
              if (inherits(condition, "warning")) {
                "muffleWarning"
              } else {
                "muffleMessage"
              }
            )
          }
          reused <- withr::with_options(
            list(warn = warn),
            withCallingHandlers(con(), warning = capture, message = capture)
          )
          expect_identical(reused, first)
          expect_identical(checked, 1L)
          expect_identical(diagnostics, list())
          expect_identical(attr(first, "fixture_credential"), "fixture-A")
        })
      })
    }
  }
})

test_that("unmufflable validity diagnostics retire the handle without escaping", {
  for (kind in c("warning", "message")) {
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session)
      opened <- 0L
      closed <- integer()
      diagnostics <- list()
      con <- oauth_db_connect(
        auth$connection,
        connect = function(token) {
          opened <<- opened + 1L
          list(id = opened, credential = token)
        },
        disconnect = function(native) {
          closed <<- c(closed, native$id)
        },
        is_valid = function(native) {
          signalCondition(structure(
            list(message = native$credential, call = NULL),
            class = c(paste0("native_", kind), kind, "condition")
          ))
          TRUE
        }
      )
      first <- con()
      auth$token(auth$make_token("replacement-token"))
      session$flushReact()
      capture <- function(condition) {
        diagnostics[[length(diagnostics) + 1L]] <<- condition
      }
      replacement <- withCallingHandlers(
        con(),
        warning = capture,
        message = capture
      )
      expect_identical(replacement$credential, "replacement-token")
      expect_false(identical(replacement, first))
      expect_identical(opened, 2L)
      expect_identical(closed, 1L)
      expect_identical(diagnostics, list())
    })
  }
})
