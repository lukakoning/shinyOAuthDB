core_connect <- function(token) {
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  DBI::dbWriteTable(con, "identity", data.frame(token = token))
  con
}

test_that("the bridge returns native connections and preserves them through token refresh", {
  skip_if_not_installed("RSQLite")
  last <- NULL
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    selected <- shiny::reactiveVal(a$connection)
    con <- oauth_db_connect(selected, core_connect, scopes = "read")
    expect_type(con, "closure")
    first <- con()
    expect_s4_class(first, "DBIConnection")
    expect_identical(con(), first)
    DBI::dbBegin(first)
    DBI::dbExecute(first, "CREATE TEMP TABLE pending (value INTEGER)")
    a$token(a$make_token("rotated"))
    session$flushReact()
    expect_identical(con(), first)
    expect_true(DBI::dbExistsTable(con(), "pending"))
    DBI::dbRollback(first)
    DBI::dbDisconnect(first)
    reopened <- con()
    expect_false(identical(reopened, first))
    expect_equal(DBI::dbReadTable(reopened, "identity")$token, "rotated")
    selected(NULL)
    session$flushReact()
    expect_false(DBI::dbIsValid(reopened))
    expect_error(con(), class = "shiny.silent.error")
    selected(a$connection)
    session$flushReact()
    last <<- con()
  })
  expect_false(DBI::dbIsValid(last))
})

test_that("normal Shiny reads track authorization and input changes without query wrappers", {
  skip_if_not_installed("RSQLite")
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    b <- odb_test_authorization(session, "B")
    selected <- shiny::reactiveVal(NULL)
    parameter <- shiny::reactiveVal(1L)
    con <- oauth_db_connect(selected, core_connect, scopes = "read")
    calls <- 0L
    rows <- shiny::reactive({
      native <- con()
      calls <<- calls + 1L
      list(user = DBI::dbReadTable(native, "identity")$token, parameter = parameter())
    })
    session$flushReact()
    expect_error(rows(), class = "shiny.silent.error")
    selected(a$connection)
    session$flushReact()
    expect_equal(rows(), list(user = "fixture-A", parameter = 1L))
    a$token(a$make_token("rotated"))
    session$flushReact()
    expect_equal(rows()$user, "fixture-A")
    expect_equal(calls, 1L)
    parameter(2L)
    session$flushReact()
    expect_equal(rows()$parameter, 2L)
    selected(b$connection)
    session$flushReact()
    expect_equal(rows()$user, "fixture-B")
    selected(NULL)
    session$flushReact()
    expect_error(rows(), class = "shiny.silent.error")
  })
})

test_that("token access is fresh and native providers stay pinned to their grant", {
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    b <- odb_test_authorization(session, "A") # Even the same ID cannot revive a provider.
    selected <- shiny::reactiveVal(a$connection)
    token <- oauth_db_token(selected, scopes = "read")
    provider <- .odb_bind(selected, identity, scopes = "read")
    saved <- provider()
    expect_equal(token(), "fixture-A")
    a$token(a$make_token("rotated"))
    session$flushReact()
    expect_equal(token(), "rotated")
    expect_identical(provider(), saved)
    expect_equal(saved(), "rotated")
    selected(b$connection)
    session$flushReact()
    expect_error(saved(), class = "shinyOAuthDB_authorization_unavailable")
    expect_equal(token(), "fixture-A")
    selected(a$connection)
    session$flushReact()
    expect_error(saved(), class = "shinyOAuthDB_authorization_unavailable")
  })
})

test_that("required permission loss and req-gated selectors retire native connections", {
  skip_if_not_installed("RSQLite")
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    gate <- shiny::reactiveVal(TRUE)
    con <- oauth_db_connect(function() { shiny::req(gate()); a$connection }, core_connect, scopes = "read")
    rows <- shiny::reactive({
      connection <- con()
      DBI::dbReadTable(connection, "identity")
    })
    first <- con()
    expect_equal(rows()$token, "fixture-A")
    a$token(a$make_token("denied", "other"))
    session$flushReact()
    expect_false(DBI::dbIsValid(first))
    expect_error(rows(), class = "shiny.silent.error")
    a$token(a$make_token("restored"))
    session$flushReact()
    expect_equal(rows()$token, "restored")
    second <- con()
    gate(FALSE)
    session$flushReact()
    expect_false(DBI::dbIsValid(second))
    expect_error(rows(), class = "shiny.silent.error")
    gate(TRUE)
    session$flushReact()
    expect_equal(rows()$token, "restored")
  })
})

test_that("first declared token targets acquire lazily", {
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session, target = "data", unacquired = TRUE)
    token <- oauth_db_token(a$connection, target = "data", scopes = a$scopes[[1L]])
    expect_equal(a$calls$acquire, 0L)
    expect_match(token(), "acquired")
    expect_equal(a$calls$acquire, 1L)
    expect_match(token(), "acquired")
  })
})

test_that("accessors enforce ownership on every call, including cached native values", {
  skip_if_not_installed("RSQLite")
  closed_con <- NULL
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    con <- oauth_db_connect(a$connection, core_connect)
    con()
    other <- shiny::MockShinySession$new()
    on.exit(other$close(), add = TRUE)
    shiny::withReactiveDomain(other, {
      expect_error(con(), class = "shinyOAuthDB_authorization_unavailable")
    })
    closed_con <<- con
  })
  expect_error(closed_con(), class = "shinyOAuthDB_authorization_unavailable")
})

test_that("native arguments and errors stay native, tokens are clean and explicit", {
  odb_test_domain(function(session) {
    raw <- shiny::reactiveVal(structure("valid-token", secret = new.env()))
    grant <- list(id = "A", has_scopes = function(scopes) TRUE,
      access_token = function(required_scopes, min_valid_for, force_refresh, async) raw())
    token <- oauth_db_token(grant)
    expect_identical(token(), "valid-token")
    raw("token;UID=other")
    expect_error(token(), class = "shinyOAuthDB_invalid_credential")
    raw("valid-token")
    client <- oauth_db_connect(grant, function(host, password) list(host = host, credential = password),
                               host = "example", token_arg = "password")
    expect_equal(client(), list(host = "example", credential = "valid-token"))
    expect_error(oauth_db_connect(grant, password = "ambient", token_arg = "password"), "omit")
    native_error <- oauth_db_connect(grant, function(token) stop("native failure"))
    expect_error(native_error(), "native failure")
  })
})

test_that("configuration errors point to the public arguments the caller can fix", {
  odb_test_domain(function(session) {
    auth <- list(connection = function() NULL)
    expect_error(oauth_db_token(auth), "Pass auth\\$connection",
                  class = "shinyOAuthDB_invalid_authorization")
    expect_error(oauth_db_token(auth$connection, scopes = "read write"), "scopes must",
                  class = "shinyOAuthDB_invalid_configuration")
    expect_error(oauth_db_connect(auth$connection, timeout = 1, timeout = 2),
      "Native configuration.*unique names", class = "shinyOAuthDB_invalid_configuration")
  })
})
