test_that("client and selected-target permission denial retire cached SQL connections", {
  skip_if_not_installed("RSQLite")
  for (target in list(NULL, "data")) {
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(
        session,
        scopes = c("essential", "read"),
        target = target,
        client_required_scopes = if (is.null(target)) {
          "essential"
        } else {
          character()
        }
      )
      con <- oauth_db_connect(
        auth$connection,
        connect = function(token) DBI::dbConnect(RSQLite::SQLite(), ":memory:"),
        target = target,
        required_scopes = auth$scopes[[2L]]
      )
      first <- con()
      session$flushReact()
      auth$token(auth$make_token("denied", auth$scopes[[2L]]))
      session$flushReact()
      expect_true(auth$connection$has_scopes(
        auth$scopes[[2L]],
        target = target
      ))
      expect_false(DBI::dbIsValid(first))
      expect_error(
        con(),
        "lacks the required permissions",
        class = "shiny.silent.error"
      )

      # Expiry can mask insufficient_scope in upstream's status ordering.
      auth$token(auth$make_token(
        "denied-expired",
        auth$scopes[[2L]],
        lifetime = -1
      ))
      session$flushReact()
      expect_error(con(), class = "shiny.silent.error")
      auth$token(auth$make_token("restored"))
      session$flushReact()
      expect_true(DBI::dbIsValid(con()))
      expect_identical(auth$calls$acquire, 0L)
    })
  }
})

test_that("credential expiry alone preserves established SQL sessions", {
  skip_if_not_installed("RSQLite")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, client_required_scopes = "read")
    con <- oauth_db_connect(auth$connection, connect = function(token) {
      DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    })
    first <- con()
    DBI::dbBegin(first)
    DBI::dbExecute(first, "CREATE TEMP TABLE pending (value INTEGER)")
    auth$token(auth$make_token("expired", lifetime = -1))
    session$flushReact()
    expect_identical(con(), first)
    expect_true(DBI::dbExistsTable(first, "pending"))
    expect_identical(auth$calls$acquire, 0L)
    DBI::dbRollback(first)
  })
})

test_that("refresh ending an authorization closes its cached SQL connection immediately", {
  skip_if_not_installed("RSQLite")
  for (target in list(NULL, "data")) {
    for (lifetime in c(-1, NA_real_)) {
      odb_test_domain(function(session) {
        auth <- odb_test_authorization(
          session,
          target = target,
          refresh_token = "fixture-refresh",
          acquire = function(...) {
            auth$current(FALSE)
            stop("Fixture refresh rejection")
          }
        )
        con <- oauth_db_connect(
          auth$connection,
          target = target,
          connect = function(token) {
            DBI::dbConnect(RSQLite::SQLite(), ":memory:")
          }
        )
        first <- con()
        session$flushReact()
        auth$token(auth$make_token("expired", lifetime = lifetime))
        expect_error(con(), class = "shiny.silent.error")
        expect_false(auth$current())
        expect_false(DBI::dbIsValid(first))
        expect_identical(auth$calls$acquire, 1L)
        session$flushReact()
        expect_error(con(), class = "shiny.silent.error")
      })
    }
  }
})

test_that("expired and unknown lifetimes cannot hide client or target permission loss", {
  skip_if_not_installed("RSQLite")
  for (target in list(NULL, "data")) {
    for (lifetime in c(-1, NA_real_)) {
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
          refresh_token = "fixture-refresh"
        )
        con <- oauth_db_connect(
          auth$connection,
          connect = function(token) {
            DBI::dbConnect(RSQLite::SQLite(), ":memory:")
          },
          target = target,
          required_scopes = auth$scopes[[2L]]
        )
        first <- con()
        session$flushReact()
        auth$token(auth$make_token(
          "denied",
          auth$scopes[[2L]],
          lifetime = lifetime
        ))
        session$flushReact()
        expect_false(DBI::dbIsValid(first))
        expect_error(
          con(),
          "lacks the required permissions",
          class = "shiny.silent.error"
        )
        expect_identical(auth$calls$acquire, 0L)
        auth$token(auth$make_token("restored"))
        session$flushReact()
        expect_true(DBI::dbIsValid(con()))
      })
    }
  }
})

test_that("unknown expiry alone preserves SQL sessions without a refresh credential", {
  skip_if_not_installed("RSQLite")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, client_required_scopes = "read")
    con <- oauth_db_connect(auth$connection, connect = function(token) {
      DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    })
    first <- con()
    session$flushReact()
    auth$token(auth$make_token("unknown-expiry", lifetime = NA_real_))
    session$flushReact()
    expect_identical(con(), first)
    expect_identical(auth$calls$acquire, 0L)
  })
})

test_that("permission validation cannot return a cached connection after access becomes uncertain", {
  skip_if_not_installed("RSQLite")
  for (expiry in c("expired", "expiry_unknown")) {
    odb_test_domain(function(session) {
      status <- shiny::reactiveVal("active")
      grant <- list(
        id = "state-transition",
        summary = function() list(status = status()),
        has_scopes = function(scopes, target = NULL) {
          status() %in% c("active", "expired", "expiry_unknown")
        },
        access_token = function(...) {
          if (status() %in% c("expired", "expiry_unknown")) {
            status("uncertain")
            getFromNamespace("connection_access_error", "shinyOAuth")(
              "interaction_required"
            )
          }
          "fixture-token"
        }
      )
      con <- oauth_db_connect(grant, connect = function(token) {
        DBI::dbConnect(RSQLite::SQLite(), ":memory:")
      })
      first <- con()
      status(expiry)
      expect_error(con(), class = "shiny.silent.error")
      expect_false(DBI::dbIsValid(first))
    })
  }
})

test_that("permission observers do not renew repeatedly when expiry stays unknown", {
  odb_test_domain(function(session) {
    generation <- shiny::reactiveVal(0L)
    renewals <- 0L
    grant <- list(
      id = "unknown-expiry",
      has_scopes = function(scopes, target = NULL) TRUE,
      summary = function() {
        generation()
        list(status = "expiry_unknown")
      },
      access_token = function(...) {
        renewals <<- renewals + 1L
        if (renewals > 3L) {
          stop("Repeated renewal")
        }
        generation(renewals)
        getFromNamespace("connection_access_error", "shinyOAuth")(
          "lifetime_unavailable"
        )
      }
    )
    oauth_db_connect(grant, connect = function(token) stop("Must remain lazy"))
    session$flushReact()
    expect_identical(renewals, 1L)
    generation(10L)
    session$flushReact()
    expect_identical(renewals, 1L)
  })
})

test_that("a confirmed denial survives refresh uncertainty and recovers when permission status is valid", {
  skip_if_not_installed("RSQLite")
  for (restored_status in c("active", "limited")) {
    odb_test_domain(function(session) {
      status <- shiny::reactiveVal("active")
      opened <- token_reads <- 0L
      token_value <- "initial-token"
      grant <- list(
        id = "denial-recovery",
        has_scopes = function(...) TRUE,
        summary = function() list(status = status()),
        access_token = function(...) {
          token_reads <<- token_reads + 1L
          token_value
        }
      )
      con <- oauth_db_connect(grant, connect = function(token) {
        opened <<- opened + 1L
        native <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
        DBI::dbWriteTable(native, "identity", data.frame(token = token))
        native
      })
      first <- con()
      status("insufficient_scope")
      session$flushReact()
      expect_false(DBI::dbIsValid(first))
      expect_error(con(), class = "shiny.silent.error")
      for (uncertain in c("refreshing", "not_acquired")) {
        status(uncertain)
        session$flushReact()
        expect_error(con(), class = "shiny.silent.error")
        expect_identical(c(opened, token_reads), c(1L, 1L))
      }
      token_value <- "restored-token"
      status(restored_status)
      session$flushReact()
      replacement <- tryCatch(con(), error = identity)
      expect_s4_class(replacement, "DBIConnection")
      if (inherits(replacement, "DBIConnection")) {
        expect_identical(
          DBI::dbReadTable(replacement, "identity")$token,
          "restored-token"
        )
        expect_identical(con(), replacement)
      }
      expect_identical(c(opened, token_reads), c(2L, 2L))
    })
  }
})

test_that("zero minimum lifetime accepts live tokens but still refreshes expired ones", {
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    auth$token(auth$make_token("short-lived", lifetime = 30))
    bearer <- oauth_db_token(auth$connection, min_valid_for = 0)
    expect_identical(bearer(), "short-lived")
    expect_identical(auth$calls$acquire, 0L)
    expired <- auth$make_token("expired", lifetime = -1)
    expired@refresh_token <- "fixture-refresh"
    auth$token(expired)
    expect_identical(bearer(), "fixture-A-acquired")
    expect_identical(auth$calls$acquire, 1L)
    for (invalid in list(-1, Inf, NA_real_, numeric(), "0")) {
      expect_error(
        oauth_db_token(auth$connection, min_valid_for = invalid),
        "min_valid_for"
      )
    }
  })
})

test_that("pending bearer acquisition resumes reactive consumers without replaying completed work", {
  for (target in list(NULL, "data")) {
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session, target = target)
      bearer <- oauth_db_token(auth$connection, target = target)
      session$flushReact()
      auth$status("refreshing")
      session$flushReact()
      calls <- 0L
      rows <- shiny::reactive({
        value <- bearer()
        calls <<- calls + 1L
        value
      })
      expect_error(rows(), class = "shiny.silent.error")
      expect_identical(calls, 0L)
      auth$token(auth$make_token("ready"))
      auth$status("active")
      session$flushReact()
      expect_identical(rows(), "ready")
      expect_identical(calls, 1L)
      auth$status("refreshing")
      session$flushReact()
      auth$token(auth$make_token("rotated"))
      auth$status("active")
      session$flushReact()
      expect_identical(rows(), "ready")
      expect_identical(calls, 1L)
      expect_identical(bearer(), "rotated")
    })
  }
})

test_that("pending connection acquisition cannot reuse a replaced authorization", {
  skip_if_not_installed("RSQLite")
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    b <- odb_test_authorization(session, "B")
    selected <- shiny::reactiveVal(a$connection)
    calls <- character()
    con <- oauth_db_connect(selected, connect = function(token) {
      calls <<- c(calls, token)
      DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    })
    session$flushReact()
    a$status("refreshing")
    session$flushReact()
    rows <- shiny::reactive({
      connection <- con()
      DBI::dbGetQuery(connection, "SELECT 1 AS value")
    })
    expect_error(rows(), class = "shiny.silent.error")
    expect_length(calls, 0L)
    selected(b$connection)
    session$flushReact()
    expect_equal(rows(), data.frame(value = 1L))
    expect_identical(calls, "fixture-B")
    a$status("active")
    session$flushReact()
    expect_equal(rows(), data.frame(value = 1L))
    expect_identical(calls, "fixture-B")
    selected(NULL)
    session$flushReact()
    expect_error(rows(), class = "shiny.silent.error")
  })
})

test_that("Fabric preflight waits but errors after callback handoff never schedule a replay", {
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(
      session,
      scopes = .odb_fabric_profile("kql")$scopes
    )
    credential <- oauth_db_fabric(auth$connection, "kql", target = NULL)
    session$flushReact()
    auth$status("refreshing")
    session$flushReact()
    accessor <- shiny::reactive(credential())
    expect_error(accessor(), class = "shiny.silent.error")
    auth$status("active")
    session$flushReact()
    callback <- accessor()
    calls <- 0L
    operation <- shiny::reactive({
      calls <<- calls + 1L
      auth$status("refreshing")
      callback("https://api.kusto.windows.net/.default", force_refresh = TRUE)
    })
    expect_error(operation(), class = "shinyOAuth_access_error")
    auth$status("active")
    session$flushReact()
    expect_error(operation(), class = "shinyOAuth_access_error")
    expect_identical(calls, 1L)
  })
})
