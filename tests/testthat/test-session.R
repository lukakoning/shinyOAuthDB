test_that("a session reuses its native connection and retires it on replacement", {
  skip_if_not_installed("RSQLite")

  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    auth <- shiny::reactiveVal(a$connection)
    db <- oauth_db_session(odb_test_source(), auth)
    first <- db$connection()

    expect_identical(db$connection(), first)
    expect_equal(
      oauth_db_query(db, "SELECT ? AS value", params = list(7L))$value,
      7L
    )

    # Rotation reconnects the driver without invalidating the authorization epoch.
    provider <- db$token_provider()
    generation <- db$generation()
    a$token(a$make_token("fixture-rotated"))
    session$flushReact()

    expect_identical(db$generation(), generation)
    expect_identical(provider(), "fixture-rotated")

    rotated <- db$connection()

    expect_false(DBI::dbIsValid(first))
    expect_false(identical(rotated, first))
    expect_identical(db$connection(), rotated)

    # Replacing the grant invalidates both the connection and captured providers.
    b <- odb_test_authorization(session, id = "B")
    auth(b$connection)
    session$flushReact()

    expect_false(DBI::dbIsValid(rotated))
    expect_gt(db$generation(), generation)
    expect_error(provider(), class = "shinyOAuthDB_authorization_unavailable")
    expect_identical(db$token_provider()(), "fixture-B")

    # Logout closes the remaining connection and prevents further acquisition.
    current <- db$connection()
    auth(NULL)
    session$flushReact()

    expect_false(DBI::dbIsValid(current))
    expect_identical(db$status()$status, "waiting_for_authorization")
    expect_error(
      db$connection(),
      class = "shinyOAuthDB_authorization_unavailable"
    )
  })
})

test_that("permission loss invalidates cached connections and extra-scope generations", {
  skip_if_not_installed("RSQLite")

  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    db <- oauth_db_session(odb_test_source(), shiny::reactive(a$connection))
    conn <- db$connection()
    generation <- db$generation(required_scopes = "write")
    a$token(a$make_token("fixture-narrow", "read"))
    session$flushReact()

    expect_gt(db$generation(), generation)
    expect_false(DBI::dbIsValid(conn))
    expect_silent(db$connection())

    a$token(a$make_token("fixture-no-read", character()))
    session$flushReact()

    expect_identical(db$status()$status, "needs_authorization")
    expect_error(
      db$connection(),
      class = "shinyOAuthDB_authorization_unavailable"
    )
  })
})

test_that("first token-target acquisition is allowed without assuming denied consent", {
  skip_if_not_installed("RSQLite")

  odb_test_domain(function(session) {
    a <- odb_test_authorization(session, target = "data", unacquired = TRUE)
    db <- oauth_db_session(
      odb_test_source(target = "data", scopes = a$scopes[[1L]]),
      shiny::reactive(a$connection)
    )

    expect_identical(db$status()$status, "not_acquired")
    expect_silent(db$connection())
    expect_equal(a$calls$acquire, 1L)
    expect_identical(db$status()$status, "ready")
  })
})

test_that("connection lifetimes follow operation and session ownership", {
  skip_if_not_installed("RSQLite")

  ended <- NULL
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    db <- oauth_db_session(
      odb_test_source(),
      shiny::reactive(a$connection),
      connection_policy = "operation"
    )

    expect_error(db$connection(), class = "shinyOAuthDB_unsupported_operation")

    temporary <- NULL
    value <- oauth_db_with_connection(db, function(conn) {
      temporary <<- conn

      DBI::dbGetQuery(conn, "SELECT 12 AS value")
    })

    expect_equal(value$value, 12L)
    expect_false(DBI::dbIsValid(temporary))
    expect_error(
      oauth_db_with_connection(db, function(conn) stop("query failed")),
      "query failed"
    )

    reusable <- oauth_db_session(
      odb_test_source(),
      shiny::reactive(a$connection)
    )
    ended <<- reusable$connection()
    other <- shiny::MockShinySession$new()
    on.exit(other$close(), add = TRUE)
    shiny::withReactiveDomain(other, {
      expect_error(
        reusable$connection(),
        class = "shinyOAuthDB_authorization_unavailable"
      )
      expect_error(
        reusable$token_provider(),
        class = "shinyOAuthDB_authorization_unavailable"
      )
    })

    expect_true(DBI::dbIsValid(ended))
  })

  expect_false(DBI::dbIsValid(ended))
  expect_error(
    oauth_db_session(odb_test_source(), shiny::reactive(NULL)),
    class = "shinyOAuthDB_authorization_unavailable"
  )
})

test_that("managed scopes reject live objects and stale values or errors", {
  skip_if_not_installed("RSQLite")

  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)

    auth <- shiny::reactiveVal(a$connection)

    db <- oauth_db_session(odb_test_source(), auth)

    expect_error(
      oauth_db_with_connection(db, identity),
      class = "shinyOAuthDB_unsupported_result"
    )

    expect_error(
      oauth_db_with_connection(db, function(conn) {
        list(callback = function() conn)
      }),
      class = "shinyOAuthDB_unsupported_result"
    )

    expect_error(
      oauth_db_with_connection(db, function(conn) {
        structure(data.frame(value = 1L), callback = function() conn)
      }),
      class = "shinyOAuthDB_unsupported_result"
    )

    expect_error(
      oauth_db_with_connection(db, function(conn) {
        auth(NULL)

        "private-A-data"
      }),
      class = "shinyOAuthDB_invalidated_outcome"
    )

    auth(a$connection)

    expect_error(
      oauth_db_with_connection(db, function(conn) {
        auth(NULL)

        stop("private-A-error")
      }),
      class = "shinyOAuthDB_invalidated_outcome"
    )
  })
})

test_that("connection failures and public status do not expose tokens", {
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)

    source <- oauth_db_custom(
      "failure",
      scopes = "read",
      connect = function(config, token_provider) {
        stop(paste("password=", token_provider()))
      }
    )

    db <- oauth_db_session(source, shiny::reactive(a$connection))
    error <- tryCatch(db$connection(), error = identity)

    expect_s3_class(error, "shinyOAuthDB_connection_failure")
    expect_false(grepl("fixture-A", conditionMessage(error), fixed = TRUE))
    expect_false(grepl(
      "fixture-A",
      paste(capture.output(print(db)), collapse = ""),
      fixed = TRUE
    ))
    expect_false("token" %in% names(db$status()))

    db$close()

    expect_identical(db$status()$status, "closed")
  })
})

test_that("opening failures under operation policy are sanitized and pinned", {
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)

    auth <- shiny::reactiveVal(a$connection)

    source <- oauth_db_custom(
      "failure",
      scopes = "read",
      connect = function(config, token_provider) {
        warning(paste("password=", token_provider()))

        stop(paste("password=", token_provider()))
      }
    )

    db <- oauth_db_session(source, auth, connection_policy = "operation")

    expect_error(
      oauth_db_with_connection(db, identity),
      class = "shinyOAuthDB_connection_failure"
    )

    stale <- oauth_db_custom(
      "failure",
      scopes = "read",
      connect = function(config, token_provider) {
        auth(NULL)

        stop("private-A-error")
      }
    )

    db_stale <- oauth_db_session(stale, auth, connection_policy = "operation")

    expect_error(
      oauth_db_with_connection(db_stale, identity),
      class = "shinyOAuthDB_authorization_unavailable"
    )
  })
})
