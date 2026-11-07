test_that("DuckDB waits for sign-in and replaces token-bound connections", {
  skip_if_not_installed("duckdb", "1.5.3")
  opened <- tokens <- list()
  local_mocked_bindings(.odb_backend_duckdb = function(token, ...) {
    tokens[[length(tokens) + 1L]] <<- token()
    native <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
    opened[[length(opened) + 1L]] <<- native
    native
  })
  retained <- NULL
  odb_test_domain(function(session) {
    a <- odb_test_authorization(
      session,
      target = "analytics",
      scopes = "read",
      refresh_token = "fixture-refresh"
    )
    b <- odb_test_authorization(
      session,
      id = "B",
      target = "analytics",
      scopes = "read"
    )
    selected <- shiny::reactiveVal(NULL)
    con <- oauth_db_duckdb(
      selected,
      "duckdb.example.org",
      target = "analytics",
      required_scopes = a$scopes
    )
    expect_error(con(), class = "shiny.silent.error")
    expect_length(opened, 0L)
    selected(a$connection)
    first <- con()
    expect_identical(con(), first)
    DBI::dbExecute(first, "CREATE TABLE private_data AS SELECT 42 AS id")
    a$token(a$make_token("rotated-A"))
    rotated <- con()
    expect_false(DBI::dbIsValid(first))
    expect_false(DBI::dbExistsTable(rotated, "private_data"))
    expect_identical(con(), rotated)
    a$token(a$make_token("expired-A", lifetime = 0))
    refreshed <- con()
    expect_false(DBI::dbIsValid(rotated))
    expect_identical(a$calls$acquire, 1L)
    DBI::dbDisconnect(refreshed, shutdown = TRUE)
    expect_true(DBI::dbIsValid(con()))
    selected(b$connection)
    account_b <- con()
    b$token(b$make_token("denied-B", character()))
    session$flushReact()
    expect_false(DBI::dbIsValid(account_b))
    expect_error(con(), class = "shiny.silent.error")
    b$token(b$make_token("restored-B"))
    signed_in <- con()
    selected(NULL)
    session$flushReact()
    expect_false(DBI::dbIsValid(signed_in))
    expect_error(con(), class = "shiny.silent.error")
    selected(a$connection)
    retained <<- con()
    other <- shiny::MockShinySession$new()
    on.exit(other$close(), add = TRUE)
    shiny::withReactiveDomain(
      other,
      expect_error(con(), class = "shinyOAuthDB_authorization_unavailable")
    )
  })
  expect_false(DBI::dbIsValid(retained))
  expect_true(all(vapply(opened, function(x) !DBI::dbIsValid(x), logical(1))))
  expect_identical(
    unlist(tokens),
    c(
      "fixture-A",
      "rotated-A",
      "fixture-A-acquired",
      "fixture-A-acquired",
      "fixture-B",
      "restored-B",
      "fixture-A-acquired"
    )
  )
})

test_that("DuckDB validates destinations before opening a connection", {
  skip_if_not_installed("duckdb", "1.5.3")
  for (host in c(
    "https://duckdb.example.org",
    "quack:example.org",
    "example.org:443",
    "user:password@example.org",
    "example.org/path",
    "example.org?token=x",
    "example.org#fragment",
    "example.org\n",
    "example.org'; SELECT 1; --",
    ""
  )) {
    expect_error(
      oauth_db_duckdb(function() NULL, host),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  for (port in list(
    0,
    65536,
    1.5,
    NA_real_,
    Inf,
    numeric(),
    c(443, 9494),
    "443"
  )) {
    expect_error(
      oauth_db_duckdb(function() NULL, "example.org", port = port),
      "port must"
    )
  }
  for (flag in list(NA, 1, "true", logical())) {
    expect_error(
      oauth_db_duckdb(function() NULL, "localhost", allow_local_http = flag),
      "allow_local_http must"
    )
  }
  for (host in c(
    "example.org",
    "127.0.0.2",
    "localhost.example.org",
    "127.0.0.1.example.org"
  )) {
    expect_error(
      oauth_db_duckdb(function() NULL, host, allow_local_http = TRUE),
      "restricted to"
    )
  }
  expect_error(
    oauth_db_duckdb(function() NULL, "example.org", schema = ""),
    "schema must"
  )
  local_mocked_bindings(.odb_bind = function(..., uri, allow_local_http) {
    list(uri = uri, allow_local_http = allow_local_http)
  })
  for (host in c("localhost", "127.0.0.1", "[::1]")) {
    expect_identical(
      oauth_db_duckdb(NULL, host, allow_local_http = TRUE),
      list(uri = paste0("quack:", host, ":9494"), allow_local_http = TRUE)
    )
  }
  expect_identical(
    oauth_db_duckdb(NULL, "example.org", port = 443),
    list(uri = "quack:example.org:443", allow_local_http = FALSE)
  )
})

test_that("DuckDB setup quotes SQL, enforces TLS and shuts down failed instances", {
  skip_if_not_installed("duckdb", "1.5.3")
  native <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(
    if (DBI::dbIsValid(native)) DBI::dbDisconnect(native, shutdown = TRUE)
  )
  statements <- character()
  mode <- "ok"
  legacy_curl <- TRUE
  shutdown_flag <- NULL
  original_disconnect <- DBI::dbDisconnect
  local_mocked_bindings(
    dbConnect = function(...) native,
    dbGetQuery = function(...) {
      data.frame(
        name = if (legacy_curl) {
          "enable_curl_server_cert_verification"
        } else {
          character()
        }
      )
    },
    dbExecute = function(conn, statement, ...) {
      statements <<- c(statements, as.character(statement))
      if (startsWith(statement, mode)) {
        stop("native error containing secret-bearer-value")
      }
      0L
    },
    dbDisconnect = function(conn, shutdown, ...) {
      shutdown_flag <<- shutdown
      original_disconnect(conn, shutdown = shutdown)
    },
    .package = "DBI"
  )
  disconnected <- FALSE
  local_mocked_bindings(.odb_duckdb_disconnect = function(connection) {
    disconnected <<- TRUE
    DBI::dbDisconnect(connection, shutdown = TRUE)
  })
  con <- .odb_backend_duckdb(
    function() "secret-bearer-value",
    "quack:example.org:443",
    'reporting"; DROP TABLE x; --',
    FALSE,
    ca_bundle = "private'ca.pem"
  )
  expect_identical(con, native)
  expect_identical(
    statements,
    c(
      "LOAD quack",
      "LOAD httpfs",
      "SET enable_server_cert_verification = true",
      "SET enable_curl_server_cert_verification = true",
      "SET http_retries = 0",
      "SET ca_cert_file = 'private''ca.pem'",
      "ATTACH 'quack:example.org:443' AS oauth_remote (TYPE quack, TOKEN 'secret-bearer-value', DISABLE_SSL false)",
      'USE oauth_remote."reporting""; DROP TABLE x; --"'
    )
  )
  expect_false(disconnected)
  legacy_curl <- FALSE
  statements <- character()
  mode <- "ATTACH"
  failure <- tryCatch(
    .odb_backend_duckdb(
      function() "secret-bearer-value",
      "quack:example.org:443",
      "main",
      FALSE
    ),
    error = identity
  )
  expect_s3_class(failure, "shinyOAuthDB_connection_failed")
  expect_false(grepl(
    "secret-bearer-value",
    conditionMessage(failure),
    fixed = TRUE
  ))
  expect_null(failure$parent)
  expect_false(
    "SET enable_curl_server_cert_verification = true" %in% statements
  )
  expect_true(disconnected)
  expect_true(shutdown_flag)
  expect_false(DBI::dbIsValid(native))
})

test_that("DuckDB does not open a connection after sign-out", {
  skip_if_not_installed("duckdb", "1.5.3")
  calls <- 0L
  local_mocked_bindings(
    dbConnect = function(...) {
      calls <<- calls + 1L
      stop("driver failure")
    },
    .package = "DBI"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    con <- oauth_db_duckdb(auth$connection, "example.org")
    auth$current(FALSE)
    expect_error(con(), class = "shiny.silent.error")
    expect_identical(calls, 0L)
  })
})
