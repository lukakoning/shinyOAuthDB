athena_arguments <- function(authorization, ...) {
  c(
    list(
      authorization = authorization,
      workgroup_arn = "arn:aws:athena:eu-west-1:123456789012:workgroup/reporting",
      application_role_arn = "arn:aws:iam::123456789012:role/apps/AthenaApplication",
      s3_output_location = "s3://query-results/reporting/"
    ),
    list(...)
  )
}

test_that("Athena supplies the visitor token to JWT_TIP without host credentials", {
  skip_if_not_installed("odbc")
  withr::local_envvar(c(
    AWS_PROFILE = "host-profile",
    AWS_ACCESS_KEY_ID = "host-key",
    AWS_SECRET_ACCESS_KEY = "host-secret",
    AWS_SESSION_TOKEN = "host-session"
  ))
  calls <- list()
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      calls[[length(calls) + 1L]] <<- c(list(drv = drv), list(...))
      "native"
    },
    .package = "DBI"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session, target = "athena")
    con <- do.call(
      oauth_db_athena,
      athena_arguments(
        auth$connection,
        target = "athena",
        required_scopes = auth$scopes,
        schema = "sales",
        catalog = "AwsDataCatalog",
        access_role_arn = "arn:aws:iam::123456789012:role/AthenaAccess",
        customer_idc_application_arn = paste0(
          "arn:aws:sso::123456789012:application/ssoins-fixture/apl-fixture"
        ),
        driver = "Athena fixture driver",
        RequestTimeout = 30000L,
        rows_to_fetch_per_block = 1000L,
        timeout = 20
      )
    )
    expect_length(calls, 0L)
    expect_identical(con(), "native")
    native <- calls[[1L]]
    expect_s4_class(native$drv, "OdbcDriver")
    expect_identical(native$driver, "Athena fixture driver")
    expect_identical(native$AuthenticationType, "JWT_TIP")
    expect_identical(native$web_identity_token, "fixture-A")
    expect_identical(native$AwsRegion, "eu-west-1")
    expect_identical(native$Workgroup, "reporting")
    expect_identical(native$WorkGroupArn, athena_arguments(NULL)$workgroup_arn)
    expect_identical(
      native$ApplicationRoleArn,
      athena_arguments(NULL)$application_role_arn
    )
    expect_identical(native$S3OutputLocation, "s3://query-results/reporting/")
    expect_identical(native$Schema, "sales")
    expect_identical(native$Catalog, "AwsDataCatalog")
    expect_identical(
      native$AccessRoleArn,
      "arn:aws:iam::123456789012:role/AthenaAccess"
    )
    expect_identical(
      native$CustomerIdcApplicationArn,
      "arn:aws:sso::123456789012:application/ssoins-fixture/apl-fixture"
    )
    expect_identical(native$JwtTipFileCache, 0L)
    expect_identical(native$EnableConnectionCaching, 0L)
    expect_identical(native$EnableResultReuse, 0L)
    expect_identical(native$VerifySSL, 1L)
    expect_identical(native$LogLevel, 0L)
    expect_match(native$role_session_name, "^shinyOAuthDB-[0-9a-f]{32}$")
    expect_identical(native$RequestTimeout, 30000L)
    expect_identical(native$RowsToFetchPerBlock, 1000L)
    expect_identical(native$timeout, 20)
    expect_false(any(grepl("^host-", unlist(native[-1L]))))
    expect_identical(con(), "native")
    expect_length(calls, 1L)
    auth$token(auth$make_token("rotated-A"))
    con()
    expect_length(calls, 2L)
    expect_identical(calls[[2L]]$web_identity_token, "rotated-A")
    expect_false(identical(
      calls[[2L]]$role_session_name,
      native$role_session_name
    ))
  })
})

test_that("Athena leaves optional ARN discovery to the configured driver", {
  skip_if_not_installed("odbc")
  native <- NULL
  local_mocked_bindings(
    dbConnect = function(drv, ...) {
      native <<- list(...)
      "native"
    },
    .package = "DBI"
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    con <- do.call(oauth_db_athena, athena_arguments(auth$connection))
    con()
    expect_false(any(
      c("AccessRoleArn", "CustomerIdcApplicationArn") %in% names(native)
    ))
    expect_identical(native$Schema, "default")
    expect_identical(native$Catalog, "AwsDataCatalog")
  })
})

test_that("Athena closes connections on token, account and session changes", {
  skip_if_not_installed("odbc")
  skip_if_not_installed("RSQLite")
  opened <- list()
  local_mocked_bindings(.odb_backend_athena = function(token, ...) {
    con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    attr(con, "opening_token") <- token()
    opened[[length(opened) + 1L]] <<- con
    con
  })
  retained <- accessor <- NULL
  odb_test_domain(function(session) {
    a <- odb_test_authorization(session, id = "A")
    b <- odb_test_authorization(session, id = "B")
    selected <- shiny::reactiveVal(NULL)
    con <- do.call(
      oauth_db_athena,
      athena_arguments(selected, required_scopes = "read")
    )
    accessor <<- con
    expect_error(con(), class = "shiny.silent.error")
    expect_length(opened, 0L)
    selected(a$connection)
    first <- con()
    expect_identical(con(), first)
    a$token(a$make_token("rotated-A"))
    second <- con()
    expect_false(DBI::dbIsValid(first))
    expect_identical(attr(second, "opening_token"), "rotated-A")
    selected(b$connection)
    third <- con()
    expect_false(DBI::dbIsValid(second))
    expect_identical(attr(third, "opening_token"), "fixture-B")
    b$token(b$make_token("denied-B", "write"))
    expect_error(con(), class = "shiny.silent.error")
    expect_false(DBI::dbIsValid(third))
    b$token(b$make_token("restored-B"))
    fourth <- con()
    selected(NULL)
    expect_error(con(), class = "shiny.silent.error")
    expect_false(DBI::dbIsValid(fourth))
    selected(a$connection)
    retained <<- con()
  })
  expect_false(DBI::dbIsValid(retained))
  odb_test_domain(function(session) {
    expect_error(accessor(), class = "shinyOAuthDB_authorization_unavailable")
  })
})

test_that("Athena refuses undeclared options and connection-string injection", {
  skip_if_not_installed("odbc")
  local_mocked_bindings(.odb_bind = function(...) {
    stop("Invalid settings must fail before binding")
  })
  for (name in c(
    "AuthenticationType",
    "web_identity_token",
    "AccessKeyID",
    "SecretAccessKey",
    "SessionToken",
    "Profile",
    "DSN",
    "FileDSN",
    "SaveFile",
    "attributes",
    ".connection_string",
    "AwsRegion",
    "Workgroup",
    "WorkGroupArn",
    "ApplicationRoleArn",
    "AccessRoleArn",
    "CustomerIdcApplicationArn",
    "role_session_name",
    "duration",
    "VerifySSL",
    "JwtTipFileCache",
    "EnableConnectionCaching",
    "EnableResultReuse",
    "LogLevel",
    "LogPath",
    "EndpointOverride",
    "STSEndpointOverride",
    "UID",
    "PWD",
    "driver"
  )) {
    args <- athena_arguments(NULL)
    # Lowercase driver is a supported public argument; test its ODBC alias.
    if (name == "driver") {
      name <- "DRIVER"
    }
    args[[name]] <- "sensitive-fixture-value"
    error <- tryCatch(do.call(oauth_db_athena, args), error = identity)
    expect_s3_class(error, "shinyOAuthDB_invalid_configuration")
    expect_false(grepl(
      "sensitive-fixture-value",
      conditionMessage(error),
      fixed = TRUE
    ))
  }
  for (entry in list(
    list(schema = "sales;AuthenticationType=IAM Credentials"),
    list(s3_output_location = "s3://results/;VerifySSL=0"),
    list(driver = "driver;DSN=host"),
    list(RequestTimeout = "100;VerifySSL=0"),
    list(`RequestTimeout;VerifySSL` = "0")
  )) {
    args <- utils::modifyList(athena_arguments(NULL), entry)
    expect_error(
      do.call(oauth_db_athena, args),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
  expect_error(
    do.call(
      oauth_db_athena,
      athena_arguments(NULL, RequestTimeout = 1, request_timeout = 2)
    ),
    "unique names"
  )
  expect_error(
    do.call(oauth_db_athena, c(athena_arguments(NULL), list(1))),
    "nonempty"
  )
})

test_that("Athena validates resource identity before acquiring credentials", {
  skip_if_not_installed("odbc")
  local_mocked_bindings(.odb_bind = function(...) {
    stop("Invalid settings must fail before binding")
  })
  for (name in c(
    "workgroup_arn",
    "application_role_arn",
    "s3_output_location",
    "schema",
    "catalog",
    "driver"
  )) {
    for (value in list(NULL, "", NA_character_, c("one", "two"), 123)) {
      args <- athena_arguments(NULL)
      args[name] <- list(value)
      expect_error(
        do.call(oauth_db_athena, args),
        class = "shinyOAuthDB_invalid_configuration"
      )
    }
  }
  for (entry in list(
    list(workgroup_arn = "arn:aws:athena:eu-west-1:123456789012:workgroup/"),
    list(workgroup_arn = "arn:aws:athena:eu-west-1:123:workgroup/reports"),
    list(
      workgroup_arn = "arn:aws:athena:eu-west-1:123456789012:workgroup/reports;VerifySSL=0"
    ),
    list(application_role_arn = "arn:aws:iam::123456789012:user/Analyst"),
    list(
      application_role_arn = "arn:aws-cn:iam::123456789012:role/Application"
    ),
    list(access_role_arn = "arn:aws:iam::123456789012:user/Analyst"),
    list(
      customer_idc_application_arn = "arn:aws:sso:::instance/ssoins-fixture"
    ),
    list(s3_output_location = "https://results.example.org")
  )) {
    expect_error(
      do.call(
        oauth_db_athena,
        utils::modifyList(athena_arguments(NULL), entry)
      ),
      class = "shinyOAuthDB_invalid_configuration"
    )
  }
})

test_that("Athena does not retry failed connection creation or use expired tokens", {
  skip_if_not_installed("odbc")
  attempts <- 0L
  local_mocked_bindings(.odb_backend_athena = function(token, ...) {
    token()
    attempts <<- attempts + 1L
    stop("Native connection failed")
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    con <- do.call(oauth_db_athena, athena_arguments(auth$connection))
    expect_error(con(), "Native connection failed")
    expect_identical(attempts, 1L)
    auth$token(auth$make_token("expired", lifetime = -60))
    expect_error(con())
    expect_identical(attempts, 1L)
  })
})
