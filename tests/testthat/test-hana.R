test_that("HANA reaches the real ODBC boundary with JWT-only authentication and verified TLS", {
  skip_if_not_installed("odbc")
  strings <- character()
  local_mocked_bindings(
    odbc_connect = function(connection_string, ...) {
      strings <<- c(strings, connection_string)
      stop(errorCondition("Native boundary reached", class = "hana_boundary"))
    },
    .package = "odbc"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    auth$token(auth$make_token("header.alice.signature"))
    con <- oauth_db_hana(
      auth$connection,
      "hana.example.org",
      database = "REPORTING",
      port = 30015L,
      schema = "SALES",
      driver = "HDBODBC",
      ssl_trust_store = "C:/HANA certificates/root.pem",
      timeout = 20
    )
    expect_error(con(), class = "hana_boundary")
    expect_length(strings, 1L)
    for (setting in c(
      "driver=HDBODBC",
      "serverNode=hana.example.org:30015",
      "UID=",
      "PWD=header.alice.signature",
      "authenticationMethods=jwt",
      "encrypt=true",
      "sslValidateCertificate=true",
      "sslHostNameInCertificate=hana.example.org",
      "reconnect=false",
      "databaseName=REPORTING",
      "currentSchema=SALES",
      "sslTrustStore=C:/HANA certificates/root.pem"
    )) {
      expect_match(strings[[1L]], setting, fixed = TRUE)
    }
    expect_false(grepl("(^|;)dsn=", strings[[1L]], ignore.case = TRUE))

    auth$token(auth$make_token("header.renewed.signature"))
    default <- oauth_db_hana(auth$connection, "cloud.example.org")
    expect_error(default(), class = "hana_boundary")
    expect_match(
      strings[[2L]],
      "serverNode=cloud.example.org:443",
      fixed = TRUE
    )
    expect_match(strings[[2L]], "PWD=header.renewed.signature", fixed = TRUE)
    expect_false(grepl(
      "databaseName|currentSchema|sslTrustStore",
      strings[[2L]]
    ))
  })
})

test_that("HANA isolates visitors, reconnects with current tokens and closes retired connections", {
  skip_if_not_installed("odbc")
  skip_if_not_installed("RSQLite")
  native_connect <- DBI::dbConnect
  opened <- tokens <- list()
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      if (!inherits(drv, "OdbcDriver")) {
        return(native_connect(drv, ...))
      }
      args <- list(...)
      tokens[[length(tokens) + 1L]] <<- args$PWD
      expect_identical(args$UID, "")
      expect_identical(args$authenticationMethods, "jwt")
      expect_identical(args$timezone_out, "Europe/Amsterdam")
      connection <- native_connect(RSQLite::SQLite(), ":memory:")
      opened[[length(opened) + 1L]] <<- connection
      connection
    },
    .package = "DBI"
  )
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    b <- odb_test_authorization(session, id = "B")
    a$token(a$make_token("header.alice.signature"))
    b$token(b$make_token("header.bob.signature"))
    selected <- shiny::reactiveVal(NULL)
    con <- oauth_db_hana(
      selected,
      "hana.example.org",
      required_scopes = "read",
      timezone_out = "Europe/Amsterdam"
    )
    expect_error(con(), class = "shiny.silent.error")
    expect_length(opened, 0L)
    selected(a$connection)
    first <- con()
    expect_identical(DBI::dbGetQuery(first, "SELECT 42 AS value")$value, 42L)
    other <- oauth_db_hana(
      b$connection,
      "hana.example.org",
      timezone_out = "Europe/Amsterdam"
    )
    bob <- other()
    expect_false(identical(first, bob))
    expect_identical(
      unlist(tokens),
      c("header.alice.signature", "header.bob.signature")
    )

    a$token(a$make_token("header.renewed.signature"))
    expect_identical(con(), first)
    DBI::dbDisconnect(first)
    second <- con()
    expect_identical(tokens[[3L]], "header.renewed.signature")
    selected(b$connection)
    third <- con()
    expect_false(DBI::dbIsValid(second))
    expect_identical(tokens[[4L]], "header.bob.signature")
    expect_true(DBI::dbIsValid(bob))

    b$token(b$make_token("header.denied.signature", permissions = "write"))
    expect_error(con(), class = "shiny.silent.error")
    expect_false(DBI::dbIsValid(third))
    b$token(b$make_token("header.bob.signature"))
    fourth <- con()
    selected(NULL)
    expect_error(con(), class = "shiny.silent.error")
    expect_false(DBI::dbIsValid(fourth))
    selected(a$connection)
    last <- con()
    session$close()
    expect_false(DBI::dbIsValid(last))
    expect_false(DBI::dbIsValid(bob))
    expect_error(con(), class = "shinyOAuthDB_authorization_unavailable")
  })
})

test_that("HANA rejects connection, credential and TLS overrides before acquiring tokens", {
  skip_if_not_installed("odbc")
  connected <- 0L
  local_mocked_bindings(
    dbConnect = function(...) {
      connected <<- connected + 1L
      stop("Invalid configuration reached the driver")
    },
    .package = "DBI"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    base <- list(authorization = auth$connection, server = "hana.example.org")
    for (name in c(
      "UID",
      "PWD",
      "user",
      "password",
      "token",
      "access_token",
      "authenticationMethods",
      "Authentication.Methods",
      "authenticationX509",
      "key",
      "userkey",
      "dsn",
      "filedsn",
      "attributes",
      ".connection_string",
      "SERVERNODE",
      "databaseName",
      "currentSchema",
      "sslValidateCertificate",
      "sslHostNameInCertificate",
      "sslTrustStore",
      "ENCRYPT",
      "reconnect",
      "sessionCookie",
      "proxyHost",
      "traceFile"
    )) {
      failure <- tryCatch(
        do.call(
          oauth_db_hana,
          c(base, stats::setNames(list("secret-fixture"), name))
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
    invalid <- list(
      server = c(
        "https://hana.example",
        "hana.example:443",
        "one,two",
        "*",
        "host;PWD=x",
        "host\n"
      ),
      database = c("db;UID=other", "db\n"),
      schema = c("sales;PWD=x", "sales\n"),
      driver = c("HDBODBC;PWD=x", "HDBODBC\n"),
      ssl_trust_store = c("ca.pem;encrypt=false", "ca.pem\n")
    )
    for (name in names(invalid)) {
      for (value in invalid[[name]]) {
        args <- base
        args[[name]] <- value
        expect_error(
          do.call(oauth_db_hana, args),
          class = "shinyOAuthDB_invalid_configuration"
        )
      }
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
        do.call(oauth_db_hana, c(base, list(port = port))),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
    expect_error(
      oauth_db_hana(auth$connection, "hana.example", "REPORTS", "unnamed"),
      class = "shinyOAuthDB_invalid_configuration"
    )
    expect_error(
      oauth_db_hana(auth$connection, "hana.example", timeout = 1, time_out = 2),
      class = "shinyOAuthDB_invalid_configuration"
    )
    expect_identical(auth$calls$acquire, 0L)
    expect_identical(connected, 0L)
  })
})

test_that("HANA rejects non-JWT credentials without calling the driver or exposing them", {
  skip_if_not_installed("odbc")
  calls <- 0L
  local_mocked_bindings(
    dbConnect = function(...) {
      calls <<- calls + 1L
      stop("Invalid token reached the driver")
    },
    .package = "DBI"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    con <- oauth_db_hana(auth$connection, "hana.example")
    for (value in c(
      "opaque-secret",
      "header.payload.",
      "header.payload.signature.extra",
      "header+payload.signature.part"
    )) {
      auth$token(auth$make_token(value))
      failure <- tryCatch(con(), error = identity)
      expect_s3_class(failure, "shinyOAuthDB_invalid_credential")
      expect_false(grepl(value, conditionMessage(failure), fixed = TRUE))
    }
    expect_identical(calls, 0L)
  })
})

test_that("HANA respects named token targets and literal operation scopes", {
  skip_if_not_installed("odbc")
  token <- NULL
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      token <<- list(...)$PWD
      stop(errorCondition("Native boundary reached", class = "hana_boundary"))
    },
    .package = "DBI"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(
      session,
      target = "hana",
      resource = "https://hana.example"
    )
    auth$token(auth$make_token("header.target.signature"))
    con <- oauth_db_hana(
      auth$connection,
      "hana.example",
      target = "hana",
      required_scopes = "https://hana.example/read"
    )
    expect_error(con(), class = "hana_boundary")
    expect_identical(token, "header.target.signature")
    token <- NULL
    denied <- oauth_db_hana(
      auth$connection,
      "hana.example",
      target = "hana",
      required_scopes = "https://hana.example/.default"
    )
    expect_error(denied(), class = "shiny.silent.error")
    expect_null(token)
  })
})
