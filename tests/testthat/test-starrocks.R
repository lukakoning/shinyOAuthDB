test_that("StarRocks supplies a temporary JWT file to the ODBC plugin and always removes it", {
  skip_if_not_installed("odbc")
  native <- NULL
  path <- NULL
  fail <- FALSE
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      native <<- c(list(drv = drv), list(...))
      path <<- native[["openid-token-file"]]
      expect_true(file.exists(path))
      expect_identical(
        readLines(path, warn = FALSE),
        "header.payload.signature"
      )
      if (fail) {
        stop("fixture connection failure")
      }
      structure(list(), class = "starrocks_fixture")
    },
    .package = "DBI"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    auth$token(auth$make_token("header.payload.signature"))
    con <- oauth_db_starrocks(
      auth$connection,
      "starrocks.example",
      "reporting",
      "alice",
      "MySQL driver",
      ssl_ca = "ca.pem",
      plugin_dir = "plugins",
      timeout = 10L
    )
    con()
    expect_false(file.exists(path))
    expect_false(dir.exists(dirname(path)))
    expect_s4_class(native$drv, "OdbcDriver")
    expect_identical(native$SSLMODE, "VERIFY_IDENTITY")
    expect_identical(native$UID, "alice")
    expect_identical(native$SSLCA, "ca.pem")
    expect_identical(native$PLUGIN_DIR, "plugins")
    expect_identical(native$PORT, 9030L)
    expect_identical(native$USE_MYCNF, 0L)
    expect_identical(native$NO_SSPS, 1L)
    expect_false(grepl("header|payload|signature", native$PWD))
    fail <<- TRUE
    other <- oauth_db_starrocks(
      auth$connection,
      "starrocks.example",
      "reporting",
      "alice",
      "MySQL driver"
    )
    expect_error(other(), "fixture connection failure")
    expect_false(file.exists(path))
    expect_false(dir.exists(dirname(path)))
  })
})

test_that("StarRocks follows accounts and usernames while preserving valid SQL sessions", {
  skip_if_not_installed("odbc")
  skip_if_not_installed("RSQLite")
  opened <- list()
  users <- character()
  local_mocked_bindings(.odb_backend_starrocks = function(token, user, ...) {
    token()
    users <<- c(users, user())
    con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    opened[[length(opened) + 1L]] <<- con
    con
  })
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session)
    b <- odb_test_authorization(session, id = "B")
    selected <- shiny::reactiveVal(NULL)
    username <- shiny::reactiveVal("alice")
    con <- oauth_db_starrocks(
      selected,
      "starrocks.example",
      "reporting",
      username,
      "MySQL driver"
    )
    expect_error(con(), class = "shiny.silent.error")
    selected(a$connection)
    first <- con()
    a$token(a$make_token("rotated-A"))
    expect_identical(con(), first)
    username("analysts")
    second <- con()
    expect_false(DBI::dbIsValid(first))
    selected(b$connection)
    third <- con()
    expect_false(DBI::dbIsValid(second))
    selected(NULL)
    expect_error(con(), class = "shiny.silent.error")
    expect_false(DBI::dbIsValid(third))
  })
  expect_identical(users, c("alice", "analysts", "analysts"))
})

test_that("StarRocks rejects credential overrides and non-JWT credentials", {
  skip_if_not_installed("odbc")
  for (name in c(
    "DSN",
    ".connection_string",
    "PWD",
    "USER",
    "OPTION",
    "USE_MYCNF",
    "SSLMODE",
    "openid-token-file",
    "MULTI_HOST",
    "ENABLE_DNS_SRV",
    "attributes",
    "INITSTMT",
    "PASSWORD2",
    "NO_SSPS"
  )) {
    args <- c(
      list(function() NULL, "server", "reporting", "alice", "MySQL driver"),
      stats::setNames(list("private-fixture"), name)
    )
    expect_error(
      do.call(oauth_db_starrocks, args),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  expect_error(
    oauth_db_starrocks(
      function() NULL,
      "server;PWD=bad",
      "db",
      "alice",
      "MySQL driver"
    ),
    "Quote ODBC"
  )
  expect_error(
    oauth_db_starrocks(
      function() NULL,
      "one,two",
      "db",
      "alice",
      "MySQL driver"
    ),
    "one TCP"
  )
  expect_error(
    oauth_db_starrocks(
      function() NULL,
      "server",
      "db",
      "alice",
      "MySQL driver",
      port = -1
    ),
    "port"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    con <- oauth_db_starrocks(
      auth$connection,
      "server",
      "reporting",
      "alice",
      "MySQL driver"
    )
    expect_error(con(), class = "shinyOAuthDB_invalid_credential")
  })
})
