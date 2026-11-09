test_that("Azure MySQL sends only the visitor token through verified ODBC", {
  skip_if_not_installed("odbc")
  native <- NULL
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      native <<- c(list(drv = drv), list(...))
      "native-connection"
    },
    .package = "DBI"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(
      session,
      target = "mysql",
      resource = "https://ossrdbms-aad.database.windows.net"
    )
    con <- oauth_db_azure_mysql(
      auth$connection,
      "example.mysql.database.azure.com",
      "reporting",
      "readers",
      "MariaDB driver",
      ssl_ca = "azure-ca.pem",
      timeout = 10L,
      timezone = "UTC",
      timezone_out = "Europe/Amsterdam",
      FORWARDONLY = 1L
    )
    expect_null(native)
    expect_identical(con(), "native-connection")
    expect_s4_class(native$drv, "OdbcDriver")
    expect_identical(native$SERVER, "example.mysql.database.azure.com")
    expect_identical(native$DATABASE, "reporting")
    expect_identical(native$UID, "readers")
    expect_identical(native$PWD, "fixture-A")
    expect_identical(native$PORT, 3306L)
    expect_identical(native$FORCETLS, 1L)
    expect_identical(native$SSLVERIFY, 1L)
    expect_identical(native$TCPIP, 1L)
    expect_identical(native$SSLCA, "azure-ca.pem")
    expect_identical(native$USE_MYCNF, 0L)
    expect_identical(native$NO_PROMPT, 1L)
    expect_identical(native$AUTO_RECONNECT, 0L)
    expect_identical(native$timeout, 10L)
    expect_identical(native$timezone, "UTC")
    expect_identical(native$timezone_out, "Europe/Amsterdam")
    expect_identical(native$FORWARDONLY, 1L)
    expect_false(any(
      c("DSN", "openid-token-file", "PLUGIN_DIR") %in% names(native)
    ))
    auth$token(auth$make_token("renewed-A"))
    expect_identical(con(), "native-connection")
    expect_identical(native$PWD, "renewed-A")
  })
})

test_that("Azure MySQL replaces fixed credentials without replaying reactive queries", {
  skip_if_not_installed("odbc")
  skip_if_not_installed("RSQLite")
  opened <- list()
  tokens <- users <- character()
  local_mocked_bindings(.odb_backend_azure_mysql = function(token, user, ...) {
    tokens <<- c(tokens, token())
    users <<- c(users, user())
    native <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    opened[[length(opened) + 1L]] <<- native
    native
  })
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    b <- odb_test_authorization(session, id = "B")
    selected <- shiny::reactiveVal(NULL)
    user <- shiny::reactiveVal("alice")
    con <- oauth_db_azure_mysql(
      selected,
      "mysql.example",
      "reporting",
      user,
      "MariaDB driver",
      target = NULL,
      required_scopes = "read"
    )
    expect_error(con(), class = "shiny.silent.error")
    expect_length(opened, 0L)
    selected(a$connection)
    runs <- 0L
    rows <- shiny::reactive({
      runs <<- runs + 1L
      DBI::dbGetQuery(con(), "SELECT 1 AS value")
    })
    expect_identical(rows()$value, 1L)
    first <- con()
    expect_identical(con(), first)
    a$token(a$make_token("renewed-A"))
    session$flushReact()
    expect_identical(rows()$value, 1L)
    expect_identical(runs, 1L)
    expect_true(DBI::dbIsValid(first))
    renewed <- con()
    expect_false(DBI::dbIsValid(first))
    expect_true(DBI::dbIsValid(renewed))
    DBI::dbDisconnect(renewed)
    recovered <- con()
    expect_true(DBI::dbIsValid(recovered))
    user("analysts")
    changed <- con()
    expect_false(DBI::dbIsValid(recovered))
    selected(b$connection)
    other <- con()
    expect_false(DBI::dbIsValid(changed))
    b$token(b$make_token("denied-B", permissions = "write"))
    session$flushReact()
    expect_false(DBI::dbIsValid(other))
    expect_error(con(), class = "shiny.silent.error")
    b$token(b$make_token("restored-B"))
    restored <- con()
    selected(NULL)
    session$flushReact()
    expect_false(DBI::dbIsValid(restored))
    expect_error(con(), class = "shiny.silent.error")
    selected(a$connection)
    last <- con()
    session$close()
    expect_false(DBI::dbIsValid(last))
    expect_error(con(), class = "shinyOAuthDB_authorization_unavailable")
  })
  expect_identical(
    tokens,
    c(
      "fixture-A",
      "renewed-A",
      "renewed-A",
      "renewed-A",
      "fixture-B",
      "restored-B",
      "renewed-A"
    )
  )
  expect_identical(users, c("alice", "alice", "alice", rep("analysts", 4L)))
  expect_true(all(vapply(opened, function(x) !DBI::dbIsValid(x), logical(1))))
})

test_that("Azure MySQL rejects authentication and routing overrides before token use", {
  skip_if_not_installed("odbc")
  connected <- 0L
  local_mocked_bindings(
    dbConnect = function(...) {
      connected <<- connected + 1L
      stop("An invalid configuration must not connect")
    },
    .package = "DBI"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    for (name in c(
      "DSN",
      "FILEDSN",
      ".connection_string",
      "connection_string",
      "attributes",
      "UID",
      "PWD",
      "PASSWORD1",
      "PASSWORD2",
      "PASSWORD3",
      "USER",
      "SSL.MODE",
      "SSLCA",
      "SSLVERIFY",
      "ENABLE_CLEARTEXT_PLUGIN",
      "OPTION",
      "USE_MYCNF",
      "INITSTMT",
      "STMT",
      "AUTO_RECONNECT",
      "PLUGIN_DIR",
      "DEFAULT_AUTH",
      "openid-token-file",
      "NAMED_PIPE",
      "SOCKET",
      "MULTI_HOST",
      "ENABLE_DNS_SRV",
      "NO_PROMPT",
      "NO_SSPS",
      "drv",
      "SERVER",
      "DATABASE",
      "PORT",
      "LOG_QUERY",
      "SAVEFILE"
    )) {
      args <- c(
        list(
          auth$connection,
          "mysql.example",
          "reporting",
          "alice",
          "MariaDB driver"
        ),
        stats::setNames(list("private-fixture"), name)
      )
      failure <- tryCatch(do.call(oauth_db_azure_mysql, args), error = identity)
      expect_s3_class(failure, "shinyOAuthDB_invalid_configuration")
      expect_false(grepl(
        "private-fixture",
        conditionMessage(failure),
        fixed = TRUE
      ))
    }
    expect_identical(auth$calls$acquire, 0L)
    expect_identical(connected, 0L)
  })
})

test_that("Azure MySQL validates endpoints, options and reactive usernames", {
  skip_if_not_installed("odbc")
  expect_error(
    oauth_db_azure_mysql(
      NULL,
      "host",
      "db",
      "user",
      "MySQL ODBC 9.5 Unicode Driver"
    ),
    "Use MariaDB Connector/ODBC"
  )
  for (port in list(
    NULL,
    integer(),
    NA_real_,
    Inf,
    -1,
    0,
    65536,
    1.5,
    1i,
    c(1L, 2L),
    TRUE,
    "3306"
  )) {
    expect_error(
      oauth_db_azure_mysql(NULL, "host", "db", "user", "driver", port = port),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  for (server in c(
    "one,two",
    "https://mysql.example",
    "host/path",
    "host name"
  )) {
    expect_error(
      oauth_db_azure_mysql(NULL, server, "db", "user", "driver"),
      "one TCP"
    )
  }
  expect_error(
    oauth_db_azure_mysql(NULL, "host;PWD=bad", "db", "user", "driver"),
    "Quote ODBC"
  )
  expect_error(
    oauth_db_azure_mysql(NULL, "host", "db", "user;PWD=bad", "driver"),
    "Quote ODBC"
  )
  expect_error(
    oauth_db_azure_mysql(
      NULL,
      "host",
      "db",
      "user",
      "driver",
      timeout = c(1, 2)
    ),
    "scalar"
  )
  expect_error(
    do.call(
      oauth_db_azure_mysql,
      c(
        list(NULL, "host", "db", "user", "driver"),
        stats::setNames(list(1, 2), c("timeout", "timeout"))
      )
    ),
    "unique"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    con <- oauth_db_azure_mysql(
      auth$connection,
      "host",
      "db",
      function() "user;PWD=bad",
      "driver",
      target = NULL
    )
    expect_error(con(), "Quote ODBC")
    local_mocked_bindings(.odb_backend_azure_mysql = function(port, ...) port)
    for (port in c(1L, 65535L)) {
      con <- oauth_db_azure_mysql(
        auth$connection,
        "host",
        "db",
        "user",
        "driver",
        port = port,
        target = NULL
      )
      expect_identical(con(), port)
    }
  })
})

test_that("MySQL consent composes with other Microsoft services", {
  resource <- "https://ossrdbms-aad.database.windows.net"
  client <- oauth_db_microsoft_client(
    "mysql",
    "organizations",
    "app",
    "http://localhost:8100"
  )
  expect_identical(client@token_target_default, "mysql")
  expect_identical(client@token_targets$mysql$resource, resource)
  expect_identical(
    client@token_targets$mysql$scopes,
    paste0(resource, "/.default")
  )
  expect_identical(client@token_targets$mysql$required_scopes, character())
  unnamed <- oauth_db_microsoft_client(
    "mysql",
    "organizations",
    "app",
    "http://localhost:8100",
    token_targets = list()
  )
  expect_identical(unnamed@token_targets, list())
  expect_true(paste0(resource, "/.default") %in% unnamed@scopes)
  for (service in c(
    "sql",
    "postgres",
    "fabric",
    "kql",
    "dax",
    "graphql",
    "onelake",
    "databricks_entra"
  )) {
    for (services in list(c("mysql", service), c(service, "mysql"))) {
      combined <- oauth_db_microsoft_client(
        services,
        "organizations",
        "app",
        "http://localhost:8100"
      )
      expect_identical(
        combined@token_targets$mysql$scopes,
        paste0(resource, "/user_impersonation")
      )
      expect_identical(
        combined@token_targets$mysql$required_scopes,
        paste0(resource, "/user_impersonation")
      )
      expect_false(any(endsWith(combined@scopes, "/.default")))
      expect_identical(
        combined@token_target_default,
        names(combined@token_targets)[[1L]]
      )
      if (service == "postgres") {
        expect_identical(
          combined@token_targets$mysql,
          combined@token_targets$postgres
        )
      }
    }
  }
})

test_that("Azure MySQL respects named permission evidence and isolates SQL access", {
  skip_if_not_installed("odbc")
  local_mocked_bindings(.odb_backend_azure_mysql = function(token, ...) token())
  odb_test_domain(function(session) {
    auth <- odb_test_fabric_authorization(session, services = c("mysql", "sql"))
    con <- oauth_db_azure_mysql(auth$connection, "host", "db", "user", "driver")
    sql <- oauth_db_token(auth$connection, target = "sql")
    expect_identical(con(), "A-mysql")
    expect_identical(sql(), "A-sql")
    values <- auth$tokens()
    values$mysql <- auth$make_token("mysql", scopes = character())
    auth$tokens(values)
    expect_error(con(), class = "shiny.silent.error")
    expect_identical(sql(), "A-sql")
    values$mysql <- auth$make_token("mysql")
    auth$tokens(values)
    expect_identical(con(), "A-mysql")
  })
  odb_test_domain(function(session) {
    client <- oauth_db_microsoft_client(
      "mysql",
      "organizations",
      "app",
      "http://localhost:8100"
    )
    auth <- odb_test_authorization(
      session,
      client = client,
      scopes = "https://ossrdbms-aad.database.windows.net/user_impersonation"
    )
    con <- oauth_db_azure_mysql(
      auth$connection,
      "host",
      "db",
      "user",
      "driver",
      required_scopes = "https://ossrdbms-aad.database.windows.net/.default"
    )
    expect_identical(con(), "fixture-A")
    auth$current(FALSE)
    expect_error(con(), class = "shiny.silent.error")
  })
})

test_that("Azure MySQL refreshes before connecting and closes connections opened after sign-out", {
  skip_if_not_installed("odbc")
  skip_if_not_installed("RSQLite")
  opened <- NULL
  expire_during_connect <- FALSE
  local_mocked_bindings(.odb_backend_azure_mysql = function(token, ...) {
    expect_identical(token(), "fixture-A-acquired")
    opened <<- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    if (is.function(expire_during_connect)) {
      expire_during_connect()
    }
    opened
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, refresh_token = "fixture-refresh")
    auth$token(auth$make_token("expired", lifetime = -1))
    con <- oauth_db_azure_mysql(
      auth$connection,
      "host",
      "db",
      "user",
      "driver",
      target = NULL
    )
    first <- con()
    expect_identical(auth$calls$acquire, 1L)
    DBI::dbDisconnect(first)
    expire_during_connect <<- function() auth$current(FALSE)
    expect_error(con(), class = "shinyOAuthDB_authorization_unavailable")
    expect_false(DBI::dbIsValid(opened))
  })
})
