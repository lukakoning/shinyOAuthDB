test_that("client and selected-target permission denial retire cached SQL connections", {
  skip_if_not_installed("RSQLite")
  for (target in list(NULL, "data")) odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = c("essential", "read"),
      target = target, client_required_scopes = if (is.null(target)) "essential" else character())
    con <- oauth_db_connect(auth$connection,
      connect = function(token) DBI::dbConnect(RSQLite::SQLite(), ":memory:"),
      target = target, required_scopes = auth$scopes[[2L]])
    first <- con()
    session$flushReact()
    auth$token(auth$make_token("denied", auth$scopes[[2L]]))
    session$flushReact()
    expect_true(auth$connection$has_scopes(auth$scopes[[2L]], target = target))
    expect_false(DBI::dbIsValid(first))
    expect_error(con(), "lacks the required permissions", class = "shiny.silent.error")

    # Expiry can mask insufficient_scope in upstream's status ordering.
    auth$token(auth$make_token("denied-expired", auth$scopes[[2L]], lifetime = -1))
    session$flushReact()
    expect_error(con(), class = "shiny.silent.error")
    auth$token(auth$make_token("restored"))
    session$flushReact()
    expect_true(DBI::dbIsValid(con()))
    expect_identical(auth$calls$acquire, 0L)
  })
})

test_that("credential expiry alone preserves established SQL sessions", {
  skip_if_not_installed("RSQLite")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, client_required_scopes = "read")
    con <- oauth_db_connect(auth$connection,
      connect = function(token) DBI::dbConnect(RSQLite::SQLite(), ":memory:"))
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

test_that("pending bearer acquisition resumes reactive consumers without replaying completed work", {
  for (target in list(NULL, "data")) odb_test_domain(function(session) {
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
    rows <- shiny::reactive({ connection <- con(); DBI::dbGetQuery(connection, "SELECT 1 AS value") })
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
    auth <- odb_test_authorization(session, scopes = .odb_fabric_profile("kql")$scopes)
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
