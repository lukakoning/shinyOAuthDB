test_that("Dremio passes the visitor's bearer and verified TLS to the ADBC boundary", {
  skip_if_not_installed("adbi", "0.1.2")
  skip_if_not_installed("adbcdrivermanager", "0.25.0")
  loaded <- connections <- list()
  native_driver <- adbcdrivermanager::adbc_driver_monkey()
  local_mocked_bindings(
    adbc_driver = function(x, entrypoint) {
      loaded[[length(loaded) + 1L]] <<- list(x, entrypoint)
      native_driver
    },
    .package = "adbcdrivermanager"
  )
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      expect_s4_class(drv, "AdbiDriver")
      connections[[length(connections) + 1L]] <<- list(...)
      "native-connection"
    },
    .package = "DBI"
  )
  ca <- tempfile(fileext = ".pem")
  withr::defer(unlink(ca))
  pem <- c(
    "-----BEGIN CERTIFICATE-----",
    "fixture",
    "-----END CERTIFICATE-----"
  )
  writeLines(pem, ca)
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    selected <- shiny::reactiveVal(NULL)
    con <- oauth_db_dremio(
      selected,
      "dremio.example.org",
      port = 443L,
      driver = "C:/drivers/{team}/flightsql.dll",
      ca_bundle = ca,
      timeout = 12.5,
      bigint = "character"
    )
    expect_error(con(), class = "shiny.silent.error")
    expect_length(loaded, 0L)
    selected(auth$connection)
    expect_identical(con(), "native-connection")
    expect_identical(
      loaded[[1L]],
      list(
        "C:/drivers/{team}/flightsql.dll",
        "AdbcDriverFlightSQLInit"
      )
    )
    args <- connections[[1L]]
    expect_identical(args$uri, "grpc+tls://dremio.example.org:443")
    expect_identical(
      args$adbc.flight.sql.authorization_header,
      "Bearer fixture-A"
    )
    expect_identical(
      args$adbc.flight.sql.client_option.tls_skip_verify,
      "false"
    )
    expect_identical(
      args$adbc.flight.sql.client_option.tls_root_certs,
      paste(pem, collapse = "\n")
    )
    expect_identical(args$adbc.flight.sql.rpc.with_cookie_middleware, "false")
    expect_identical(args$bigint, "character")
    for (operation in c("connect", "query", "fetch", "update")) {
      expect_identical(
        args[[paste0("adbc.flight.sql.rpc.timeout_seconds.", operation)]],
        "12.5"
      )
    }
    expect_false(any(
      c("username", "password", "token", "dsn") %in% names(args)
    ))

    default <- oauth_db_dremio(auth$connection, "dremio.example.org")
    expect_identical(default(), "native-connection")
    expect_identical(loaded[[2L]][[1L]], "flightsql")
    expect_identical(
      connections[[2L]]$uri,
      "grpc+tls://dremio.example.org:32010"
    )
    expect_false(
      "adbc.flight.sql.client_option.tls_root_certs" %in%
        names(connections[[2L]])
    )
  })
})

test_that("Dremio renews fixed credentials without replaying reactive queries", {
  skip_if_not_installed("adbi", "0.1.2")
  skip_if_not_installed("adbcdrivermanager", "0.25.0")
  skip_if_not_installed("duckdb")
  native_connect <- DBI::dbConnect
  native_driver <- duckdb::duckdb_adbc()
  tokens <- character()
  local_mocked_bindings(
    adbc_driver = function(...) native_driver,
    .package = "adbcdrivermanager"
  )
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      args <- list(...)
      tokens <<- c(tokens, args$adbc.flight.sql.authorization_header)
      native_connect(adbi::adbi(native_driver))
    },
    .package = "DBI"
  )
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session, refresh_token = "fixture-refresh")
    b <- odb_test_authorization(session, "B")
    selected <- shiny::reactiveVal(a$connection)
    con <- oauth_db_dremio(
      selected,
      "dremio.example.org",
      required_scopes = "read"
    )
    queried <- 0L
    rows <- shiny::reactive({
      connection <- con()
      queried <<- queried + 1L
      DBI::dbGetQuery(connection, "SELECT 42 AS answer")
    })
    expect_equal(rows()$answer, 42)
    first <- con()
    result <- DBI::dbSendQuery(first, "SELECT 1")
    a$token(a$make_token("renewed-A"))
    session$flushReact()
    expect_equal(rows()$answer, 42)
    expect_identical(queried, 1L)
    second <- con()
    expect_false(DBI::dbIsValid(first))
    expect_false(DBI::dbIsValid(result))
    expect_identical(con(), second)
    expect_identical(tokens, c("Bearer fixture-A", "Bearer renewed-A"))

    a$token(a$make_token("expiring-A", lifetime = 30))
    third <- con()
    expect_false(DBI::dbIsValid(second))
    expect_identical(tail(tokens, 1L), "Bearer fixture-A-acquired")
    DBI::dbDisconnect(third)
    fourth <- con()
    expect_true(DBI::dbIsValid(fourth))
    expect_identical(tail(tokens, 1L), "Bearer fixture-A-acquired")

    other <- oauth_db_dremio(b$connection, "dremio.example.org")
    bob <- other()
    expect_false(identical(fourth, bob))
    selected(b$connection)
    fifth <- con()
    expect_false(DBI::dbIsValid(fourth))
    expect_identical(tail(tokens, 1L), "Bearer fixture-B")
    b$token(b$make_token("denied-B", permissions = "write"))
    expect_error(con(), class = "shiny.silent.error")
    expect_false(DBI::dbIsValid(fifth))
    b$token(b$make_token("fixture-B"))
    last <- con()
    selected(NULL)
    session$flushReact()
    expect_false(DBI::dbIsValid(last))
    expect_error(con(), class = "shiny.silent.error")
    session$close()
    expect_false(DBI::dbIsValid(bob))
    expect_error(other(), class = "shinyOAuthDB_authorization_unavailable")
  })
})

test_that("Dremio checks named targets and rejects configuration overrides before token access", {
  local_mocked_bindings(.odb_require = function(...) TRUE)
  loaded <- 0L
  local_mocked_bindings(.odb_backend_dremio = function(token, ...) {
    loaded <<- loaded + 1L
    token()
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, target = "dremio")
    base <- list(authorization = auth$connection, host = "dremio.example.org")
    for (name in c(
      "uri",
      "username",
      "password",
      "token",
      "access_token",
      "dsn",
      "adbc.flight.sql.authorization_header",
      "adbc.flight.sql.oauth.flow",
      "adbc.flight.sql.client_option.tls_skip_verify",
      "adbc.flight.sql.client_option.tls_override_hostname",
      "adbc.flight.sql.client_option.mtls_private_key",
      "adbc.flight.sql.rpc.call_header.authorization",
      "adbc.flight.sql.rpc.with_cookie_middleware",
      "rows_affected_callback"
    )) {
      failure <- tryCatch(
        do.call(
          oauth_db_dremio,
          c(
            base,
            stats::setNames(list("secret-fixture"), name)
          )
        ),
        error = identity
      )
      expect_s3_class(failure, "shinyOAuthDB_invalid_configuration")
      expect_false(grepl(
        "secret-fixture",
        conditionMessage(failure),
        fixed = TRUE
      ))
    }
    for (host in c(
      "https://host",
      "host:443",
      "host/path",
      "one,two",
      "host?x=y",
      "host\n"
    )) {
      expect_error(
        oauth_db_dremio(auth$connection, host),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
    for (port in list(
      NULL,
      NA_real_,
      Inf,
      0,
      65536,
      443.5,
      TRUE,
      "443",
      c(1, 2)
    )) {
      expect_error(
        do.call(oauth_db_dremio, c(base, list(port = port))),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
    for (timeout in list(NULL, NA_real_, Inf, 0, -1, TRUE, "30", c(1, 2))) {
      expect_error(
        do.call(oauth_db_dremio, c(base, list(timeout = timeout))),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
    expect_error(
      oauth_db_dremio(
        auth$connection,
        "host",
        bigint = "integer",
        big_int = "numeric"
      ),
      class = "shinyOAuthDB_invalid_configuration"
    )
    expect_identical(auth$calls$acquire, 0L)
    expect_identical(loaded, 0L)
    expect_error(
      oauth_db_dremio(auth$connection, "host", driver = "driver\n"),
      class = "shinyOAuthDB_invalid_configuration"
    )
    expect_error(
      oauth_db_dremio(auth$connection, "host", ca_bundle = tempfile()),
      class = "shinyOAuthDB_invalid_configuration"
    )
    invalid_ca <- tempfile()
    withr::defer(unlink(invalid_ca))
    writeLines("not a certificate", invalid_ca)
    expect_error(
      oauth_db_dremio(auth$connection, "host", ca_bundle = invalid_ca),
      class = "shinyOAuthDB_invalid_configuration"
    )
    con <- oauth_db_dremio(
      auth$connection,
      "host",
      target = "dremio",
      required_scopes = auth$scopes
    )
    expect_identical(con(), "fixture-A")
    auth$token(auth$make_token("denied", character()))
    expect_error(con(), class = "shiny.silent.error")
    expect_identical(loaded, 1L)
  })
})

test_that("Dremio native errors retain argument references and do not retry connection failures", {
  skip_if_not_installed("adbi", "0.1.2")
  skip_if_not_installed("adbcdrivermanager", "0.25.0")
  native_driver <- adbcdrivermanager::adbc_driver_monkey()
  local_mocked_bindings(
    adbc_driver = function(...) native_driver,
    .package = "adbcdrivermanager"
  )
  calls <- 0L
  local_mocked_bindings(
    dbConnect = function(...) {
      calls <<- calls + 1L
      stop(errorCondition(
        "Native failure",
        call = sys.call(),
        class = "dremio_boundary"
      ))
    },
    .package = "DBI"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    con <- oauth_db_dremio(auth$connection, "host")
    error <- tryCatch(con(), error = identity)
    expect_s3_class(error, "dremio_boundary")
    expect_identical(conditionMessage(error), "Native failure")
    expect_false(grepl(
      "fixture-A",
      paste(deparse(conditionCall(error)), collapse = ""),
      fixed = TRUE
    ))
    expect_identical(calls, 1L)
  })
})
