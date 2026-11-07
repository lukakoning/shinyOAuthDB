test_that("a native connector can use its own scopes argument", {
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    native_scopes <- structure(c("query", "metadata"), class = "native_scopes")
    con <- oauth_db_connect(
      auth$connection,
      connect = function(password, scopes) {
        list(password = password, scopes = scopes)
      },
      token_arg = "password",
      scopes = native_scopes,
      required_scopes = "read"
    )
    expect_identical(
      con(),
      list(password = "fixture-A", scopes = native_scopes)
    )
    auth$token(auth$make_token("denied", "write"))
    expect_error(con(), class = "shiny.silent.error")
  })
})

test_that("ODBC helpers reject missing and nonscalar identifiers before binding", {
  skip_if_not_installed("odbc")
  local_mocked_bindings(.odb_bind = function(...) {
    stop("Must not bind an invalid configuration")
  })
  for (invalid in list(
    NULL,
    "",
    NA_character_,
    character(),
    c("first", "second"),
    1433L
  )) {
    expect_error(
      oauth_db_azure_sql(NULL, server = invalid, database = "reports"),
      "server must"
    )
    expect_error(
      oauth_db_snowflake(NULL, server = invalid, role = "READER"),
      "server must"
    )
  }
  expect_error(
    oauth_db_sql_server(NULL, "server", database = character()),
    "database must"
  )
  expect_error(
    oauth_db_azure_sql(NULL, "server", "reports", driver = c("one", "two")),
    "driver must"
  )
  expect_error(
    oauth_db_snowflake(NULL, "account", role = "READER", driver = NULL),
    "driver must"
  )
  expect_error(
    oauth_db_snowflake(NULL, "account", database = "", role = "READER"),
    "database must"
  )
  expect_error(
    oauth_db_snowflake(NULL, "account", schema = character(), role = "READER"),
    "schema must"
  )
  expect_error(
    oauth_db_snowflake(
      NULL,
      "account",
      warehouse = NA_character_,
      role = "READER"
    ),
    "warehouse must"
  )
})

test_that("quoted ODBC values reach the native connector unchanged", {
  skip_if_not_installed("odbc")
  captured <- NULL
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      captured <<- list(...)
      "native"
    },
    .package = "DBI"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    for (name in c(
      "Sales;Archive",
      "Sales{Archive}",
      'Sales "Archive";2026',
      "Reader's;reports",
      " padded = name "
    )) {
      database <- odbc::quote_value(name)
      con <- oauth_db_azure_sql(
        auth$connection,
        "server",
        database,
        APP = database,
        target = NULL,
        required_scopes = "read"
      )
      expect_identical(con(), "native")
      expect_identical(captured$database, database)
      expect_identical(captured$APP, database)
      expect_identical(captured$Encrypt, "yes")
      expect_identical(captured$TrustServerCertificate, "no")
      expect_identical(captured$attributes, list(azure_token = "fixture-A"))

      snow <- oauth_db_snowflake(
        auth$connection,
        "account",
        database,
        "PUBLIC",
        "WH",
        "READER",
        target = NULL,
        required_scopes = "read"
      )
      expect_identical(snow(), "native")
      expect_identical(captured$database, database)
      expect_identical(captured$authenticator, "oauth")
      expect_identical(captured$token, "fixture-A")
    }
    con <- oauth_db_azure_sql(
      auth$connection,
      odbc::quote_value("server"),
      "db",
      port = 1443L,
      target = NULL,
      required_scopes = "read"
    )
    con()
    expect_identical(as.character(captured$server), '"server,1443"')
  })
})

test_that("ODBC delimiters cannot escape the quoted value", {
  local_mocked_bindings(
    .odb_require = function(...) TRUE,
    .odb_bind = capture_backend
  )
  for (value in c(
    '"Sales";UID=other;"x"',
    "'Sales';PWD=secret;'x'",
    '"Sales";TrustServerCertificate=yes;"x"',
    '"Sales;UID=other',
    "Sales;UID=other",
    "{Sales};UID=other",
    '"Sales\nArchive"',
    "Sales\rArchive",
    "Sales\tArchive"
  )) {
    expect_error(
      oauth_db_azure_sql(NULL, "server", value),
      "odbc::quote_value",
      fixed = TRUE
    )
    expect_error(
      oauth_db_snowflake(NULL, "account", value, "PUBLIC", "WH", "READER"),
      "odbc::quote_value",
      fixed = TRUE
    )
  }
  # SQL Server combines server and port into one ODBC value: a quoted port
  # must not introduce a delimiter in the middle of that value.
  expect_error(
    oauth_db_azure_sql(NULL, "server", "db", port = '"1433;UID=other"'),
    "port"
  )
  expect_error(
    oauth_db_azure_sql(NULL, "server", "db", `APP=x;UID` = "other"),
    "option names"
  )
  expect_error(
    oauth_db_snowflake(
      NULL,
      "account",
      "db",
      "PUBLIC",
      "WH",
      "READER",
      `APP=x;TOKEN_FILE_PATH` = "path"
    ),
    "option names"
  )
})

test_that("ODBC endpoint aliases and file settings cannot override connection identity", {
  local_mocked_bindings(
    .odb_require = function(...) TRUE,
    .odb_bind = capture_backend
  )
  for (name in c("Addr", "ADDRESS", "FileDSN", "SaveFile", "FailoverPartner")) {
    option <- stats::setNames(list("sensitive-fixture-value"), name)
    for (helper in list(
      oauth_db_azure_sql,
      oauth_db_sql_server,
      oauth_db_fabric_sql
    )) {
      error <- expect_error(
        do.call(helper, c(list(NULL, "fixed.example.org", "reports"), option)),
        "cannot be overridden",
        class = "shinyOAuthDB_invalid_configuration"
      )
      expect_false(grepl(
        "sensitive-fixture-value",
        conditionMessage(error),
        fixed = TRUE
      ))
    }
  }
  for (helper in list(oauth_db_snowflake, oauth_db_redshift)) {
    for (name in c("FileDSN", "SaveFile")) {
      args <- c(
        list(NULL, "fixed.example.org", "reports"),
        stats::setNames(list("other.dsn"), name)
      )
      if (identical(helper, oauth_db_snowflake)) {
        args$role <- "READER"
      }
      expect_error(
        do.call(helper, args),
        "cannot be overridden",
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
  }
})

test_that("ODBC option values cannot inject protected keywords through native coercion", {
  local_mocked_bindings(
    .odb_require = function(...) TRUE,
    .odb_bind = function(...) stop("Invalid options must not reach binding")
  )
  payload <- "review;SERVER=other.example.org;TAIL=review"
  invalid <- list(
    list(payload),
    as.name(payload),
    factor(payload),
    expression(value),
    c("first", "second"),
    character(),
    c(1, 2),
    NA_real_,
    NA,
    complex(real = 1),
    as.raw(65),
    matrix(1),
    structure("value", class = "custom"),
    I(1)
  )
  for (value in invalid) {
    for (helper in list(
      oauth_db_azure_sql,
      oauth_db_snowflake,
      oauth_db_redshift,
      oauth_db_fabric_sql
    )) {
      args <- list(NULL, "fixed.example.org", "reports", APP = value)
      if (identical(helper, oauth_db_snowflake)) {
        args$role <- "READER"
      }
      error <- expect_error(
        do.call(helper, args, quote = TRUE),
        "scalar",
        class = "shinyOAuthDB_invalid_configuration"
      )
      expect_false(grepl(payload, conditionMessage(error), fixed = TRUE))
    }
    expect_error(
      oauth_db_starrocks(
        NULL,
        "fixed.example.org",
        "reports",
        "alice",
        "MySQL driver",
        readtimeout = value
      ),
      "scalar",
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  for (value in list(
    stats::setNames(1, payload),
    stats::setNames(TRUE, payload)
  )) {
    expect_error(
      oauth_db_azure_sql(NULL, "fixed.example.org", "reports", APP = value),
      "odbc::quote_value",
      fixed = TRUE,
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  expect_error(
    .odb_odbc_values(list(APP = "line\nbreak")),
    "control characters"
  )
  expect_error(
    .odb_odbc_values(list(APP = I(payload))),
    "odbc::quote_value",
    fixed = TRUE
  )
})

test_that("ODBC validation preserves supported native scalar values", {
  skip_if_not_installed("odbc")
  values <- list(
    optional = NULL,
    text = "reporting",
    number = 12.5,
    integer = 10L,
    flag = TRUE,
    unlimited_timeout = Inf,
    quoted = odbc::quote_value("Sales;Archive")
  )
  expect_identical(.odb_odbc_values(values), values)
})
