test_that("Oracle reaches the real ODBC boundary with an isolated token descriptor", {
  skip_if_not_installed("odbc")
  paths <- strings <- character()
  local_mocked_bindings(
    odbc_connect = function(connection_string, ...) {
      strings <<- c(strings, connection_string)
      path <- sub('.*TOKEN_LOCATION="([^"]+)".*', "\\1", connection_string)
      paths <<- c(paths, path)
      expect_true(file.exists(path))
      expect_identical(
        readLines(path, warn = FALSE),
        "header.payload.signature"
      )
      if (.Platform$OS.type != "windows") {
        expect_identical(as.integer(file.info(path)$mode), strtoi("600", 8L))
        expect_identical(
          as.integer(file.info(dirname(path))$mode),
          strtoi("700", 8L)
        )
      }
      stop(errorCondition("Native boundary reached", class = "oracle_boundary"))
    },
    .package = "odbc"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    auth$token(auth$make_token("header.payload.signature"))
    con <- oauth_db_oracle(
      auth$connection,
      "oracle.example.org",
      "reporting.example.org",
      "Oracle driver",
      port = 2484L,
      wallet_location = "C:/Oracle wallets (TLS)/reporting",
      server_cert_dn = "CN=oracle.example.org,O=Example,C=NL",
      FBS = 100000L
    )
    for (i in 1:2) {
      expect_error(con(), class = "oracle_boundary")
      expect_false(file.exists(paths[[i]]))
      expect_false(dir.exists(dirname(paths[[i]])))
    }
    expect_length(unique(paths), 2L)
    expect_true(all(grepl("(PROTOCOL=TCPS)", strings, fixed = TRUE)))
    expect_true(all(grepl("(HOST=oracle.example.org)", strings, fixed = TRUE)))
    expect_true(all(grepl("(PORT=2484)", strings, fixed = TRUE)))
    expect_true(all(grepl("(TOKEN_AUTH=OAUTH)", strings, fixed = TRUE)))
    expect_true(all(grepl(
      "(AUTHENTICATION_SERVICE=NONE)",
      strings,
      fixed = TRUE
    )))
    expect_true(all(grepl("(SSL_SERVER_DN_MATCH=YES)", strings, fixed = TRUE)))
    expect_true(all(grepl("(TLS_SERVER_DN_MATCH=YES)", strings, fixed = TRUE)))
    expect_true(all(grepl(
      '(WALLET_LOCATION="C:/Oracle wallets (TLS)/reporting")',
      strings,
      fixed = TRUE
    )))
    expect_true(all(grepl(
      '(SSL_SERVER_CERT_DN="CN=oracle.example.org,O=Example,C=NL")',
      strings,
      fixed = TRUE
    )))
    expect_true(all(grepl("FEN=F", strings, fixed = TRUE)))
    expect_true(all(grepl("FBS=100000", strings, fixed = TRUE)))
    expect_false(any(grepl("header.payload.signature", strings, fixed = TRUE)))
    expect_false(any(grepl("(^|;)dsn=", strings, ignore.case = TRUE)))
  })
})

test_that("Oracle uses current visitor tokens on reconnect and closes retired sessions", {
  skip_if_not_installed("odbc")
  skip_if_not_installed("RSQLite")
  native_connect <- DBI::dbConnect
  native_query <- DBI::dbGetQuery
  opened <- tokens <- paths <- list()
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      if (!inherits(drv, "OdbcDriver")) {
        return(native_connect(drv, ...))
      }
      args <- list(...)
      path <- sub('.*TOKEN_LOCATION="([^"]+)".*', "\\1", args$DBQ)
      paths[[length(paths) + 1L]] <<- path
      tokens[[length(tokens) + 1L]] <<- readLines(path, warn = FALSE)
      expect_identical(args$UID, "")
      expect_identical(args$PWD, "")
      expect_identical(args$timezone_out, "Europe/Amsterdam")
      connection <- native_connect(RSQLite::SQLite(), ":memory:")
      opened[[length(opened) + 1L]] <<- connection
      connection
    },
    dbGetQuery = function(conn, statement, ...) {
      if (grepl("SYS_CONTEXT", statement, fixed = TRUE)) {
        return(data.frame(AUTH_METHOD = "TOKEN_GLOBAL"))
      }
      native_query(conn, statement, ...)
    },
    .package = "DBI"
  )
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    b <- odb_test_authorization(session, id = "B")
    a$token(a$make_token("header.alice.signature"))
    b$token(b$make_token("header.bob.signature"))
    selected <- shiny::reactiveVal(NULL)
    con <- oauth_db_oracle(
      selected,
      "oracle.example",
      "reporting",
      "Oracle driver",
      required_scopes = "read",
      timezone_out = "Europe/Amsterdam"
    )
    expect_error(con(), class = "shiny.silent.error")
    expect_length(opened, 0L)
    selected(a$connection)
    first <- con()
    expect_identical(DBI::dbGetQuery(first, "SELECT 42 AS value")$value, 42L)
    expect_false(file.exists(paths[[1L]]))
    a$token(a$make_token("header.renewed.signature"))
    expect_identical(con(), first)
    expect_length(opened, 1L)
    DBI::dbDisconnect(first)
    second <- con()
    expect_identical(tokens[[2L]], "header.renewed.signature")
    selected(b$connection)
    third <- con()
    expect_false(DBI::dbIsValid(second))
    expect_identical(tokens[[3L]], "header.bob.signature")
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
    expect_error(con(), class = "shinyOAuthDB_authorization_unavailable")
  })
  expect_false(any(file.exists(unlist(paths))))
  expect_false(any(dir.exists(dirname(unlist(paths)))))
})

test_that("Oracle disconnects if token authentication cannot be confirmed", {
  skip_if_not_installed("odbc")
  skip_if_not_installed("RSQLite")
  native_connect <- DBI::dbConnect
  opened <- NULL
  path <- NULL
  answer <- data.frame(AUTH_METHOD = "PASSWORD")
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      args <- list(...)
      path <<- sub('.*TOKEN_LOCATION="([^"]+)".*', "\\1", args$DBQ)
      opened <<- native_connect(RSQLite::SQLite(), ":memory:")
      opened
    },
    dbGetQuery = function(...) {
      if (inherits(answer, "condition")) {
        stop(answer)
      }
      answer
    },
    .package = "DBI"
  )
  bad_methods <- list(
    data.frame(AUTH_METHOD = "PASSWORD"),
    data.frame(AUTH_METHOD = "OS"),
    data.frame(AUTH_METHOD = NA_character_),
    data.frame(AUTH_METHOD = character()),
    data.frame(AUTH_METHOD = c("TOKEN_GLOBAL", "PASSWORD")),
    data.frame(AUTH_METHOD = "TOKEN_GLOBAL", other = "extra"),
    list(AUTH_METHOD = "TOKEN_GLOBAL")
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    auth$token(auth$make_token("header.payload.signature"))
    con <- oauth_db_oracle(auth$connection, "oracle.example", "db", "driver")
    for (bad in bad_methods) {
      answer <<- bad
      expect_error(con(), class = "shinyOAuthDB_invalid_credential")
      expect_false(DBI::dbIsValid(opened))
      expect_false(file.exists(path))
      expect_false(dir.exists(dirname(path)))
    }
    answer <<- errorCondition(
      "Oracle verification failed",
      class = "verify_error"
    )
    expect_error(con(), class = "verify_error")
    expect_false(DBI::dbIsValid(opened))
    expect_false(file.exists(path))
  })
})

test_that("Oracle validates configuration before requesting visitor credentials", {
  skip_if_not_installed("odbc")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    base <- list(
      authorization = auth$connection,
      host = "oracle.example",
      service_name = "reporting",
      driver = "Oracle driver"
    )
    for (name in c(
      "DSN",
      "d",
      "ds",
      "DBQ",
      "UID",
      "PWD",
      "User",
      "password",
      ".connection_string",
      "attributes",
      "FEN",
      "DCC",
      "TOKEN_AUTH",
      "TOKEN_LOCATION",
      "SSL_SERVER_DN_MATCH",
      "TLS_SERVER_DN_MATCH"
    )) {
      error <- tryCatch(
        do.call(
          oauth_db_oracle,
          c(base, stats::setNames(list("secret-fixture"), name))
        ),
        error = identity
      )
      expect_s3_class(error, "shinyOAuthDB_invalid_configuration")
      expect_false(grepl(
        "secret-fixture",
        conditionMessage(error),
        fixed = TRUE
      ))
    }
    invalid <- list(
      host = c("one,two", "host)(TOKEN_AUTH=NONE)", "https://oracle.example"),
      service_name = c("db)(SID=other)", "db;PWD=x", "db\n"),
      wallet_location = c('wallet"', "wallet;PWD=x", "wallet\n"),
      server_cert_dn = c('CN=host"', "CN=host;PWD=x")
    )
    for (name in names(invalid)) {
      for (value in invalid[[name]]) {
        args <- base
        args[[name]] <- value
        expect_error(
          do.call(oauth_db_oracle, args),
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
      1522.5,
      TRUE,
      "1522",
      c(1, 2)
    )) {
      expect_error(
        do.call(oauth_db_oracle, c(base, list(port = port))),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
    expect_identical(auth$calls$acquire, 0L)
    con <- do.call(oauth_db_oracle, base)
    expect_error(con(), class = "shinyOAuthDB_invalid_credential")
  })
})

test_that("Oracle cleans the token file on interruption", {
  skip_if_not_installed("odbc")
  path <- NULL
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      path <<- sub('.*TOKEN_LOCATION="([^"]+)".*', "\\1", list(...)$DBQ)
      stop(structure(
        list(message = "interrupted", call = NULL),
        class = c("interrupt", "condition")
      ))
    },
    .package = "DBI"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    auth$token(auth$make_token("header.payload.signature"))
    con <- oauth_db_oracle(auth$connection, "oracle.example", "db", "driver")
    caught <- tryCatch(con(), interrupt = identity)
    expect_s3_class(caught, "interrupt")
    expect_false(file.exists(path))
    expect_false(dir.exists(dirname(path)))
  })
})

oracle_fixture_jwt <- function(claims) {
  payload <- as.character(jsonlite::toJSON(claims, auto_unbox = TRUE))
  payload <- chartr(
    "+/",
    "-_",
    as.character(openssl::base64_encode(charToRaw(payload)))
  )
  paste0("e30.", sub("=+$", "", payload), ".signature")
}

test_that("Oracle end-user sessions verify server claims and rotate with their tokens", {
  skip_if_not_installed("odbc")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("RSQLite")
  claims <- list(
    iss = "https://issuer.example/realms/oracle",
    sub = "alice",
    aud = c("database", "account")
  )
  first_jwt <- oracle_fixture_jwt(c(claims, list(iat = 1L)))
  renewed_jwt <- oracle_fixture_jwt(c(claims, list(iat = 2L)))
  context <- as.character(jsonlite::toJSON(claims, auto_unbox = TRUE))
  opened <- paths <- tokens <- list()
  native_connect <- DBI::dbConnect
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      args <- list(...)
      path <- sub('.*TOKEN_LOCATION="([^"]+)".*', "\\1", args$DBQ)
      paths[[length(paths) + 1L]] <<- path
      tokens[[length(tokens) + 1L]] <<- readLines(path, warn = FALSE)
      connection <- native_connect(RSQLite::SQLite(), ":memory:")
      opened[[length(opened) + 1L]] <<- connection
      connection
    },
    dbGetQuery = function(conn, statement, ...) {
      expect_match(
        statement,
        "ORA_END_USER_CONTEXT.USER.TOKEN.iss",
        fixed = TRUE
      )
      expect_match(
        statement,
        "ORA_END_USER_CONTEXT.USER.TOKEN.sub",
        fixed = TRUE
      )
      expect_match(
        statement,
        "ORA_END_USER_CONTEXT.USER.TOKEN.aud",
        fixed = TRUE
      )
      expect_false(grepl("signature", statement, fixed = TRUE))
      data.frame(TOKEN_CLAIMS = context)
    },
    .package = "DBI"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    auth$token(auth$make_token(first_jwt))
    con <- oauth_db_oracle(
      auth$connection,
      "oracle.example",
      "db",
      "driver",
      authorization_model = "end_user"
    )
    first <- con()
    expect_identical(con(), first)
    expect_length(opened, 1L)
    executions <- 0L
    rows <- shiny::reactive({
      con()
      executions <<- executions + 1L
      42L
    })
    expect_identical(rows(), 42L)
    auth$token(auth$make_token(renewed_jwt))
    session$flushReact()
    expect_identical(rows(), 42L)
    expect_identical(executions, 1L)
    second <- con()
    expect_false(DBI::dbIsValid(first))
    expect_true(DBI::dbIsValid(second))
    expect_identical(tokens, list(first_jwt, renewed_jwt))
    expect_false(any(file.exists(unlist(paths))))
    auth$current(FALSE)
    expect_error(con(), class = "shiny.silent.error")
    expect_false(DBI::dbIsValid(second))
  })
})

test_that("Oracle end-user verification rejects missing or different token contexts", {
  skip_if_not_installed("odbc")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("RSQLite")
  claims <- list(iss = "https://issuer.example", sub = "alice", aud = "oracle")
  token <- oracle_fixture_jwt(claims)
  context <- NULL
  connection <- path <- NULL
  native_connect <- DBI::dbConnect
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      path <<- sub('.*TOKEN_LOCATION="([^"]+)".*', "\\1", list(...)$DBQ)
      connection <<- native_connect(RSQLite::SQLite(), ":memory:")
      connection
    },
    dbGetQuery = function(...) {
      if (inherits(context, "condition")) {
        stop(context)
      }
      data.frame(TOKEN_CLAIMS = context)
    },
    .package = "DBI"
  )
  bad <- c(
    "{}",
    "null",
    "not-json",
    '"/private/file.json"',
    '{"iss":"https://other.example","sub":"alice","aud":"oracle"}',
    '{"iss":"https://issuer.example","sub":"bob","aud":"oracle"}',
    '{"iss":"https://issuer.example","sub":"alice","aud":"other"}',
    '{"iss":"https://issuer.example","sub":"alice","aud":["oracle",null]}',
    '{"iss":"https://issuer.example","sub":"alice","sub":"bob","aud":"oracle"}'
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    auth$token(auth$make_token(token))
    con <- oauth_db_oracle(
      auth$connection,
      "oracle.example",
      "db",
      "driver",
      authorization_model = "end_user"
    )
    for (value in bad) {
      context <<- value
      error <- expect_error(con(), class = "shinyOAuthDB_invalid_credential")
      expect_false(grepl(
        "alice|bob|signature|private",
        conditionMessage(error)
      ))
      expect_false(DBI::dbIsValid(connection))
      expect_false(file.exists(path))
      expect_false(dir.exists(dirname(path)))
    }
    context <<- errorCondition("Context unavailable", class = "context_error")
    expect_error(con(), class = "context_error")
    expect_false(DBI::dbIsValid(connection))
    expect_false(file.exists(path))
  })
})

test_that("Oracle validates end-user token identity before opening a connection", {
  skip_if_not_installed("odbc")
  skip_if_not_installed("jsonlite")
  connects <- 0L
  local_mocked_bindings(
    dbConnect = function(...) {
      connects <<- connects + 1L
      stop("Invalid identity reached the driver")
    },
    .package = "DBI"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    con <- oauth_db_oracle(
      auth$connection,
      "oracle.example",
      "db",
      "driver",
      authorization_model = "end_user"
    )
    for (claims in list(
      list(),
      list(iss = "issuer", sub = "alice"),
      list(iss = "issuer", sub = "", aud = "oracle"),
      list(iss = "issuer", sub = "alice", aud = list(list("oracle")))
    )) {
      auth$token(auth$make_token(oracle_fixture_jwt(claims)))
      expect_error(con(), class = "shinyOAuthDB_invalid_credential")
    }
    auth$token(auth$make_token("header.payload.signature"))
    expect_error(con(), class = "shinyOAuthDB_invalid_credential")
    expect_identical(connects, 0L)
  })
})

test_that("Oracle retains provider-specific permission names literally", {
  local_mocked_bindings(
    .odb_bind = capture_backend,
    .odb_require = function(...) TRUE
  )
  scope <- "https://issuer.example/database/.default"
  expect_identical(
    oauth_db_oracle(
      NULL,
      "host",
      "db",
      "driver",
      required_scopes = scope
    )$required_scopes,
    scope
  )
})

test_that("Oracle identity comparisons preserve UTF-8 and normalize audience order", {
  claims <- list(
    iss = "https://issuer.example",
    sub = "\u00e1l\u00efce",
    aud = c("second", "first")
  )
  expect_identical(
    .odb_oracle_jwt_identity(oracle_fixture_jwt(claims)),
    list(iss = claims$iss, sub = claims$sub, aud = c("first", "second"))
  )
})
