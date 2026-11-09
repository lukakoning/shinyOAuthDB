test_that("SingleStore supplies visitor JWTs through the real ODBC connection builder", {
  skip_if_not_installed("odbc")
  strings <- character()
  local_mocked_bindings(
    odbc_connect = function(connection_string, ...) {
      strings <<- c(strings, connection_string)
      stop(errorCondition(
        "Native boundary reached",
        class = "singlestore_boundary"
      ))
    },
    .package = "odbc"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    auth$token(auth$make_token("header.alice.signature"))
    con <- oauth_db_singlestore(
      auth$connection,
      "sql.example.org",
      "reporting",
      ssl_ca = "C:/certificates/root.pem",
      port = 3307L,
      timeout = 10,
      NO_CACHE = 1L
    )
    expect_error(con(), class = "singlestore_boundary")
    for (setting in c(
      "driver=SingleStore ODBC Unicode Driver",
      "SERVER=sql.example.org",
      "PORT=3307",
      "DATABASE=reporting",
      "UID=*",
      "JWT=header.alice.signature",
      "SSLCA=C:/certificates/root.pem",
      "SSLVERIFY=1",
      "BROWSER_SSO=0",
      "IGNORE_KEYRING_SSO=1",
      "USE_MYCNF=0",
      "AUTO_RECONNECT=0",
      "NO_PROMPT=1"
    )) {
      expect_match(strings[[1L]], setting, fixed = TRUE)
    }
    expect_false(grepl(
      "(^|;)(dsn|pwd|password)=",
      strings[[1L]],
      ignore.case = TRUE
    ))
    default <- oauth_db_singlestore(
      auth$connection,
      "sql.example.org",
      ssl_ca = "ca.pem",
      user = "alice"
    )
    expect_error(default(), class = "singlestore_boundary")
    expect_match(strings[[2L]], "PORT=3306", fixed = TRUE)
    expect_match(strings[[2L]], "UID=alice", fixed = TRUE)
    expect_false(grepl("DATABASE=", strings[[2L]], fixed = TRUE))
  })
})

test_that("SingleStore isolates visitors and usernames and uses current tokens on reconnect", {
  skip_if_not_installed("odbc")
  skip_if_not_installed("RSQLite")
  native_connect <- DBI::dbConnect
  tokens <- users <- character()
  opened <- list()
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      if (!inherits(drv, "OdbcDriver")) {
        return(native_connect(drv, ...))
      }
      args <- list(...)
      tokens <<- c(tokens, args$JWT)
      users <<- c(users, args$UID)
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
    username <- shiny::reactiveVal("alice")
    con <- oauth_db_singlestore(
      selected,
      "sql.example.org",
      ssl_ca = "ca.pem",
      user = username,
      required_scopes = "read"
    )
    expect_error(con(), class = "shiny.silent.error")
    expect_length(opened, 0L)
    selected(a$connection)
    first <- con()
    expect_identical(DBI::dbGetQuery(first, "SELECT 42 AS value")$value, 42L)
    bob <- oauth_db_singlestore(
      b$connection,
      "sql.example.org",
      ssl_ca = "ca.pem"
    )
    other <- bob()
    expect_false(identical(first, other))
    a$token(a$make_token("header.renewed.signature"))
    rotated <- con()
    expect_false(identical(rotated, first))
    expect_false(DBI::dbIsValid(first))
    DBI::dbDisconnect(rotated)
    renewed <- con()
    expect_identical(tail(tokens, 1L), "header.renewed.signature")
    username("analysts")
    group <- con()
    expect_false(DBI::dbIsValid(renewed))
    expect_identical(tail(users, 1L), "analysts")
    selected(b$connection)
    switched <- con()
    expect_false(DBI::dbIsValid(group))
    expect_identical(tail(tokens, 1L), "header.bob.signature")
    b$token(b$make_token("header.denied.signature", permissions = "write"))
    expect_error(con(), class = "shiny.silent.error")
    expect_false(DBI::dbIsValid(switched))
    b$token(b$make_token("header.bob.signature"))
    last <- con()
    selected(NULL)
    expect_error(con(), class = "shiny.silent.error")
    expect_false(DBI::dbIsValid(last))
    selected(a$connection)
    final <- con()
    session$close()
    expect_false(DBI::dbIsValid(final))
    expect_false(DBI::dbIsValid(other))
    expect_error(con(), class = "shinyOAuthDB_authorization_unavailable")
  })
})

test_that("SingleStore blocks credential, routing and TLS overrides before token acquisition", {
  skip_if_not_installed("odbc")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    base <- list(
      authorization = auth$connection,
      server = "sql.example",
      ssl_ca = "ca.pem"
    )
    for (name in c(
      "JWT",
      "token",
      "access_token",
      "PWD",
      "PASSWORD",
      "UID",
      "USER",
      "BROWSER_SSO",
      "Browser.Sso",
      "IGNORE_KEYRING_SSO",
      "USE_MYCNF",
      "OPTION",
      "OPTIONS",
      "AUTO_RECONNECT",
      "NO_PROMPT",
      "SERVER",
      "SERVERNAME",
      "PORT",
      "DATABASE",
      "DSN",
      "FILEDSN",
      "SAVEFILE",
      "SSLCA",
      "SSLVERIFY",
      "SSLVerify",
      "SSLCERT",
      "SSLCIPHER",
      "SOCKET",
      "NamedPipe",
      "PLUGIN_DIR",
      "INITSTMT",
      "attributes",
      "dbms.name",
      ".connection_string"
    )) {
      failure <- tryCatch(
        do.call(
          oauth_db_singlestore,
          c(base, stats::setNames(list("private-fixture"), name))
        ),
        error = identity
      )
      expect_s3_class(failure, "shinyOAuthDB_invalid_configuration")
      expect_false(grepl(
        "private-fixture",
        conditionMessage(failure),
        fixed = TRUE
      ))
    }
    invalid <- list(
      server = c(
        "https://sql.example",
        "one,two",
        "sql.example:3306",
        "sql;JWT=bad"
      ),
      database = c("db;PWD=x", "db\n"),
      driver = c("driver;PWD=x", "driver\n"),
      ssl_ca = c("", " ", "\" \"", "''", "ca.pem;SSLVERIFY=0", "ca.pem\n"),
      user = c("", "alice;JWT=x", "alice\n")
    )
    for (name in names(invalid)) {
      for (value in invalid[[name]]) {
        args <- base
        args[[name]] <- value
        expect_error(
          do.call(oauth_db_singlestore, args),
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
      3306.5,
      TRUE,
      "3306",
      c(1, 2)
    )) {
      expect_error(
        do.call(oauth_db_singlestore, c(base, list(port = port))),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
    expect_error(
      do.call(oauth_db_singlestore, c(base, list(timeout = 1, time_out = 2))),
      class = "shinyOAuthDB_invalid_configuration"
    )
    expect_error(
      oauth_db_singlestore(auth$connection, "sql.example", ssl_ca = NULL),
      "ssl_ca"
    )
    expect_identical(auth$calls$acquire, 0L)
  })
})

test_that("SingleStore rejects malformed access tokens before calling a driver", {
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
    con <- oauth_db_singlestore(
      auth$connection,
      "sql.example",
      ssl_ca = "ca.pem"
    )
    for (value in c("opaque-secret", "header.payload.", "a.b.c.d", "a+b.c.d")) {
      auth$token(auth$make_token(value))
      failure <- tryCatch(con(), error = identity)
      expect_s3_class(failure, "shinyOAuthDB_invalid_credential")
      expect_false(grepl(value, conditionMessage(failure), fixed = TRUE))
    }
    expect_identical(calls, 0L)
  })
})

test_that("SingleStore uses the selected token target and literal operation scopes", {
  skip_if_not_installed("odbc")
  value <- NULL
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      value <<- list(...)$JWT
      stop(errorCondition(
        "Native boundary reached",
        class = "singlestore_boundary"
      ))
    },
    .package = "DBI"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(
      session,
      target = "singlestore",
      resource = "https://sql.example"
    )
    auth$token(auth$make_token("header.target.signature"))
    con <- oauth_db_singlestore(
      auth$connection,
      "sql.example",
      ssl_ca = "ca.pem",
      target = "singlestore",
      required_scopes = "https://sql.example/read"
    )
    expect_error(con(), class = "singlestore_boundary")
    expect_identical(value, "header.target.signature")
    value <- NULL
    denied <- oauth_db_singlestore(
      auth$connection,
      "sql.example",
      ssl_ca = "ca.pem",
      target = "singlestore",
      required_scopes = "https://sql.example/.default"
    )
    expect_error(denied(), class = "shiny.silent.error")
    expect_null(value)
  })
})
