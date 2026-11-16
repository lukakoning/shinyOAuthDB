test_that("generic RPostgres connections retire failed native reconnects", {
  skip_if_not_installed("RPostgres")
  loadNamespace("RPostgres")
  closed <- logical()
  opened <- character()
  broken <- FALSE
  probes <- 0L
  local_mocked_bindings(
    dbIsValid = function(conn, ...) !isTRUE(closed[attr(conn, "fixture")]),
    dbGetInfo = function(dbObj, ...) {
      probes <<- probes + 1L
      if (broken && attr(dbObj, "fixture") == 1L) {
        stop("Lost connection: the driver's copied credential expired")
      }
      list(pid = attr(dbObj, "fixture"))
    },
    dbDisconnect = function(conn, ...) {
      closed[attr(conn, "fixture")] <<- TRUE
      invisible(TRUE)
    },
    .package = "DBI"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    con <- oauth_db_connect(auth$connection, connect = function(token) {
      opened <<- c(opened, token)
      native <- methods::new("PqConnection")
      attr(native, "fixture") <- length(opened)
      native
    })
    first <- con()
    expect_identical(con(), first)
    auth$token(auth$make_token("replacement-token"))
    session$flushReact()
    expect_identical(con(), first)
    expect_length(opened, 1L)
    broken <<- TRUE
    expect_true(DBI::dbIsValid(first))
    replacement <- con()
    expect_false(identical(replacement, first))
    expect_false(DBI::dbIsValid(first))
    expect_identical(opened, c("fixture-A", "replacement-token"))
    expect_identical(con(), replacement)
    expect_identical(probes, 4L)
  })
  expect_identical(closed, c(TRUE, TRUE))
})

test_that("generic drivers can supply a validity check without replacing healthy clients", {
  for (failure in c("false", "error")) {
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session)
      healthy <- TRUE
      closed <- integer()
      opened <- 0L
      con <- oauth_db_connect(
        auth$connection,
        connect = function(token) {
          opened <<- opened + 1L
          healthy <<- TRUE
          list(id = opened, credential = token)
        },
        is_valid = function(value) {
          expect_type(value, "list")
          if (!healthy && failure == "error") {
            stop("Native validity failure")
          }
          healthy
        },
        disconnect = function(value) {
          closed <<- c(closed, value$id)
        }
      )
      first <- con()
      auth$token(auth$make_token("replacement-token"))
      session$flushReact()
      expect_identical(con(), first)
      expect_length(closed, 0L)
      healthy <- FALSE
      replacement <- con()
      expect_identical(replacement$credential, "replacement-token")
      expect_identical(closed, 1L)
      expect_identical(con(), replacement)
      expect_identical(opened, 2L)
    })
  }
})

test_that("generic validity checks must be functions or NULL", {
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    expect_error(
      oauth_db_connect(auth$connection, is_valid = TRUE),
      "is_valid must be functions",
      class = "shinyOAuthDB_invalid_configuration"
    )
  })
})
