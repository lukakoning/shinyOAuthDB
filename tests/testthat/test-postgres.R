postgres_test_settings <- function(...) {
  c(list(host = "postgres.example.org", dbname = "reporting", user = "alice",
    issuer = "https://login.example.org/realms/reporting", scope = "database.read"), list(...))
}

test_that("PostgreSQL rejects ambiguous identities and authentication overrides before login", {
  local_mocked_bindings(.odb_postgres_runtime = function() TRUE)
  base <- postgres_test_settings()
  invalid <- list(
    list(host = "host,other"), list(host = "/tmp"), list(host = "@socket"),
    list(host = "host\nother"), list(issuer = "http://login.example.org"),
    list(issuer = "https://user@login.example.org"),
    list(issuer = "https://login.example.org/"),
    list(issuer = "https://login.example.org/.well-known/openid-configuration"),
    list(scope = "database.read  other"), list(scope = "database.read "),
    list(scope = " database.read"), list(scope = "database.read database.read"),
    list(scope = "database.read\tother"), list(port = 5432.5), list(port = "5432"),
    list(port = 0), list(port = 65536), list(connect_timeout = 1),
    list(connect_timeout = Inf), list(connect_timeout = 1e50), list(user = "alice\nbob"),
    list(password = "secret"), list(token = "other"), list(service = "ambient"),
    list(sslmode = "disable"), list(oauth_client_secret = "secret"),
    list(hostaddr = "192.0.2.1"), list(require_auth = "password"),
    list(SSLMode = "disable"), list(oauth_issuer = "https://other.example.org")
  )
  for (replacement in invalid) {
    args <- utils::modifyList(base, replacement)
    error <- expect_error(do.call(oauth_db_postgres, c(list(NULL), args)),
      class = "shinyOAuthDB_invalid_configuration")
    expect_false(grepl("secret", conditionMessage(error), fixed = TRUE))
  }
})

test_that("PostgreSQL connections follow roles, permissions and the owning session", {
  skip_if_not_installed("RSQLite")
  opened <- list()
  live_at_session_end <- NULL
  local_mocked_bindings(
    .odb_postgres_runtime = function() TRUE,
    .odb_postgres_connection_valid = DBI::dbIsValid,
    .odb_postgres_connect_bearer = function(token, user, ...) {
      native <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
      DBI::dbWriteTable(native, "identity", data.frame(role = user, credential = token))
      opened[[length(opened) + 1L]] <<- native
      native
    }
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = c("database.read", "extra.read"))
    role <- shiny::reactiveVal("alice")
    args <- postgres_test_settings(required_scopes = "extra.read")
    args$user <- role
    con <- do.call(oauth_db_postgres, c(list(auth$connection), args))
    first <- con()
    expect_identical(DBI::dbGetQuery(first, "SELECT role FROM identity")$role, "alice")
    expect_identical(con(), first)
    expect_length(opened, 1L)

    auth$token(auth$make_token("refreshed-A"))
    expect_identical(con(), first)
    role("bob")
    second <- con()
    expect_false(DBI::dbIsValid(first))
    expect_identical(DBI::dbGetQuery(second, "SELECT * FROM identity"),
      data.frame(role = "bob", credential = "refreshed-A"))

    DBI::dbDisconnect(second)
    third <- con()
    expect_true(DBI::dbIsValid(third))
    expect_length(opened, 3L)
    auth$token(auth$make_token("reduced-A", permissions = "database.read"))
    expect_error(con(), class = "shiny.silent.error")
    expect_false(DBI::dbIsValid(third))
    expect_length(opened, 3L)

    auth$token(auth$make_token("restored-A"))
    fourth <- con()
    auth$current(FALSE)
    expect_error(con(), class = "shiny.silent.error")
    expect_false(DBI::dbIsValid(fourth))
    auth$current(TRUE)
    live_at_session_end <<- con()
    expect_true(DBI::dbIsValid(live_at_session_end))
  })
  expect_false(DBI::dbIsValid(live_at_session_end))
  expect_true(all(vapply(opened, function(con) !DBI::dbIsValid(con), logical(1))))
})

test_that("PostgreSQL checks the server scope and never resolves a role before authorization", {
  local_mocked_bindings(.odb_postgres_runtime = function() TRUE)
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, scopes = "openid")
    role_calls <- 0L
    args <- postgres_test_settings()
    args$user <- function() { role_calls <<- role_calls + 1L; "alice" }
    con <- do.call(oauth_db_postgres, c(list(auth$connection), args))
    expect_error(con(), class = "shiny.silent.error")
    expect_identical(role_calls, 0L)
  })
})

test_that("PostgreSQL refuses ambient OAuth service configuration without opening a driver", {
  args <- postgres_test_settings()
  for (variable in c("PGSERVICE", "PGSERVICEFILE", "PGOAUTHDEBUG")) {
    withr::with_envvar(stats::setNames("ambient", variable), {
      expect_error(do.call(.odb_postgres_connect_bearer,
        c(list(token = "fixture-A"), args)), "Unset PGSERVICE", fixed = TRUE)
    })
  }
})

test_that("unsupported builds explain how to run native PostgreSQL OAuth", {
  if (isTRUE(.Call(C_pg_bearer_available))) return(invisible(NULL))
  expect_error(.odb_postgres_runtime(), "Linux", fixed = TRUE)
  expect_error(do.call(oauth_db_postgres, c(list(NULL), postgres_test_settings())),
    "Docker playground", fixed = TRUE)
})
