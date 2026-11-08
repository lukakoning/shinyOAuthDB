test_that("custom cleanup runs once per native object through replacement, logout and session end", {
  cleaned <- list()
  retained <- NULL
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    b <- odb_test_authorization(session, "B")
    selected <- shiny::reactiveVal(a$connection)
    con <- oauth_db_connect(
      selected,
      connect = function(token) new.env(),
      disconnect = function(value) {
        cleaned[[length(cleaned) + 1L]] <<- value
      }
    )
    first <- con()
    expect_identical(con(), first)
    a$token(a$make_token("renewed"))
    session$flushReact()
    expect_length(cleaned, 0L)
    selected(b$connection)
    session$flushReact()
    expect_identical(cleaned, list(first))
    second <- con()
    expect_false(identical(first, second))
    selected(NULL)
    session$flushReact()
    expect_identical(cleaned, list(first, second))
    expect_error(con(), class = "shiny.silent.error")
    session$flushReact()
    expect_length(cleaned, 2L)
    selected(a$connection)
    retained <<- con()
  })
  expect_identical(cleaned[[3L]], retained)
  expect_length(cleaned, 3L)
})

test_that("cleanup errors cannot revive a retired object or provider", {
  cleaned <- list()
  retained <- NULL
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    b <- odb_test_authorization(session, "B")
    selected <- shiny::reactiveVal(a$connection)
    con <- .odb_bind(
      selected,
      connect = function(token) list(token = token, native = new.env()),
      disconnect = function(value) {
        cleaned[[length(cleaned) + 1L]] <<- value$native
        stop("fixture cleanup failed")
      }
    )
    first <- con()
    selected(b$connection)
    session$flushReact()
    second <- con()
    expect_identical(cleaned, list(first$native))
    expect_error(
      first$token(),
      class = "shinyOAuthDB_authorization_unavailable"
    )
    expect_identical(second$token(), "fixture-B")
    selected(NULL)
    session$flushReact()
    expect_error(con(), class = "shiny.silent.error")
    expect_error(
      second$token(),
      class = "shinyOAuthDB_authorization_unavailable"
    )
    expect_identical(cleaned, list(first$native, second$native))
    retained <<- con
  })
  expect_length(cleaned, 2L)
  expect_error(retained(), class = "shinyOAuthDB_authorization_unavailable")
})

test_that("cleanup diagnostics omit native credentials and do not interrupt retirement", {
  reported <- list()
  withr::local_options(shinyOAuthDB.on_cleanup_error = function(error) {
    reported[[length(reported) + 1L]] <<- error
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    selected <- shiny::reactiveVal(auth$connection)
    con <- .odb_bind(
      selected,
      function(token) token,
      disconnect = function(value) stop("PRIVATE_TOKEN_AND_DRIVER_DETAILS")
    )
    provider <- con()
    selected(NULL)
    session$flushReact()
    expect_length(reported, 1L)
    expect_s3_class(reported[[1L]], "shinyOAuthDB_cleanup_failed")
    expect_identical(reported[[1L]]$reason, "cleanup_failed")
    expect_null(reported[[1L]]$parent)
    expect_null(reported[[1L]]$call)
    expect_false(grepl(
      "PRIVATE_",
      paste(capture.output(dput(reported)), collapse = "")
    ))
    expect_error(provider(), class = "shinyOAuthDB_authorization_unavailable")
    expect_error(con(), class = "shiny.silent.error")
    selected(auth$connection)
    con()
    session$close()
    expect_length(reported, 2L)
  })
})

test_that("default and failing cleanup loggers emit only a fixed diagnostic", {
  for (handler in list(NULL, function(error) stop("PRIVATE_LOGGER_DETAILS"))) {
    withr::local_options(shinyOAuthDB.on_cleanup_error = handler)
    text <- capture.output(
      odb_test_domain(function(session) {
        auth <- odb_test_authorization(session)
        selected <- shiny::reactiveVal(auth$connection)
        con <- oauth_db_connect(
          selected,
          function(token) new.env(),
          disconnect = function(value) stop("PRIVATE_DRIVER_DETAILS")
        )
        con()
        selected(NULL)
        session$flushReact()
        expect_error(con(), class = "shiny.silent.error")
      }),
      type = "message"
    )
    expect_identical(text, "shinyOAuthDB could not close a native connection.")
  }
})

test_that("cleanup failures after an authorization change during opening are reported", {
  reports <- 0L
  withr::local_options(shinyOAuthDB.on_cleanup_error = function(error) {
    reports <<- reports + 1L
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    selected <- shiny::reactiveVal(auth$connection)
    con <- oauth_db_connect(
      selected,
      function(token) {
        selected(NULL)
        new.env()
      },
      disconnect = function(value) stop("PRIVATE_DRIVER_DETAILS")
    )
    expect_error(con(), class = "shinyOAuthDB_authorization_unavailable")
    expect_identical(reports, 1L)
    expect_error(con(), class = "shiny.silent.error")
  })
})

test_that("an authorization change during opening closes the new handle before returning it", {
  skip_if_not_installed("RSQLite")
  for (transition in c("replace", "logout", "permissions", "session_end")) {
    odb_test_domain(function(session) {
      a <- odb_test_authorization(session)
      b <- odb_test_authorization(session, "B")
      selected <- shiny::reactiveVal(a$connection)
      opened <- NULL
      cleaned <- 0L
      once <- TRUE
      con <- oauth_db_connect(
        selected,
        required_scopes = "read",
        connect = function(token) {
          opened <<- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
          DBI::dbWriteTable(opened, "identity", data.frame(token = token))
          if (once) {
            once <<- FALSE
            switch(
              transition,
              replace = selected(b$connection),
              logout = selected(NULL),
              permissions = a$token(a$make_token("denied", "write")),
              session_end = session$close()
            )
          }
          opened
        },
        disconnect = function(value) {
          cleaned <<- cleaned + 1L
          DBI::dbDisconnect(value)
        }
      )
      expect_error(
        con(),
        class = "shinyOAuthDB_authorization_unavailable",
        info = transition
      )
      expect_false(DBI::dbIsValid(opened), info = transition)
      expect_identical(cleaned, 1L, info = transition)
      if (transition == "session_end") {
        expect_error(con(), class = "shinyOAuthDB_authorization_unavailable")
      } else {
        selected(b$connection)
        session$flushReact()
        replacement <- con()
        expect_identical(
          DBI::dbReadTable(replacement, "identity")$token,
          "fixture-B"
        )
        expect_identical(cleaned, 1L)
      }
    })
  }
})

test_that("failed native validation closes the old handle and reconnects with the current token", {
  skip_if_not_installed("RSQLite")
  for (invalid in c("error", "missing", "empty", "false", "vector")) {
    local({
      replacement <- NULL
      odb_test_domain(function(session) {
        auth <- odb_test_authorization(session)
        mode <- "valid"
        opened <- 0L
        con <- .odb_bind(
          auth$connection,
          connect = function(token) {
            value <- token()
            opened <<- opened + 1L
            mode <<- "valid"
            native <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
            DBI::dbWriteTable(native, "identity", data.frame(token = value))
            native
          },
          is_valid = function(value) {
            switch(
              mode,
              valid = DBI::dbIsValid(value),
              error = stop("Fixture driver validation failed"),
              missing = NA,
              empty = NULL,
              false = FALSE,
              vector = c(TRUE, FALSE)
            )
          }
        )
        first <- con()
        expect_identical(con(), first)
        auth$token(auth$make_token("current-token"))
        session$flushReact()
        expect_identical(con(), first)
        mode <- invalid
        replacement <<- con()
        expect_false(DBI::dbIsValid(first))
        expect_s4_class(replacement, "DBIConnection")
        expect_identical(
          DBI::dbReadTable(replacement, "identity")$token,
          "current-token"
        )
        expect_identical(con(), replacement)
        expect_identical(opened, 2L)
      })
      expect_false(DBI::dbIsValid(replacement))
    })
  }
})
