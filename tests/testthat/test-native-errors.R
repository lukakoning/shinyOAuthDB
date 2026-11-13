native_expect_private_error <- function(error, credentials) {
  expect_s3_class(error, "error")
  stored <- rawToChar(serialize(error, NULL, ascii = TRUE))
  printed <- paste(capture.output(print(error)), collapse = "\n")
  for (credential in credentials) {
    expect_false(grepl(credential, stored, fixed = TRUE))
    expect_false(grepl(credential, printed, fixed = TRUE))
  }
}

test_that("generic connector failures redact native calls and traces without losing diagnostics", {
  for (kind in c("base", "rlang")) {
    odb_test_domain(function(session) {
      auth <- odb_test_authorization(session)
      credential <- paste(format(openssl::rand_bytes(24)), collapse = "")
      auth$token(auth$make_token(credential))
      ready <- FALSE
      con <- oauth_db_connect(
        auth$connection,
        connect = function(host, password) {
          if (ready) {
            return(list(host = host, read = function() password))
          }
          if (kind == "base") {
            stop("Driver failed")
          }
          rlang::abort("Driver failed", class = "native_connect_failure")
        },
        host = "example.invalid",
        token_arg = "password"
      )
      error <- tryCatch(shiny::captureStackTraces(con()), error = identity)
      expect_s3_class(
        error,
        if (kind == "base") "simpleError" else "native_connect_failure"
      )
      expect_identical(conditionMessage(error), "Driver failed")
      native_expect_private_error(error, credential)
      ready <- TRUE
      expect_identical(con()$host, "example.invalid")
      expect_identical(con()$read(), credential)
    })
  }
})

test_that("native failures redact every credential issued while connecting", {
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    credentials <- vapply(
      seq_len(2L),
      function(i) {
        paste(format(openssl::rand_bytes(24)), collapse = "")
      },
      ""
    )
    auth$token(auth$make_token(credentials[[1L]]))
    con <- .odb_bind(auth$connection, function(token) {
      first <- token()
      auth$token(auth$make_token(credentials[[2L]]))
      second <- token()
      stop(errorCondition(
        paste("Driver failed", first, second),
        class = "native_connect_failure",
        status = 403L,
        parent = simpleError(first),
        response = list(body = charToRaw(second)),
        frame = environment()
      ))
    })
    error <- tryCatch(shiny::captureStackTraces(con()), error = identity)
    expect_s3_class(error, "native_connect_failure")
    expect_identical(error$status, 403L)
    expect_identical(
      conditionMessage(error),
      "Driver failed [REDACTED] [REDACTED]"
    )
    expect_identical(conditionMessage(error$parent), "[REDACTED]")
    expect_null(error$frame)
    native_expect_private_error(error, credentials)
  })
})

test_that("real Databricks connection validation errors do not retain bearer credentials", {
  skip_if_not_installed("brickster", "0.2.14")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    credential <- paste(format(openssl::rand_bytes(24)), collapse = "")
    auth$token(auth$make_token(credential))
    con <- oauth_db_databricks(
      auth$connection,
      host = "example.invalid",
      warehouse_id = "fixture",
      max_active_connections = 0
    )
    error <- tryCatch(shiny::captureStackTraces(con()), error = identity)
    expect_s3_class(error, "rlang_error")
    expect_match(conditionMessage(error), "max_active_connections")
    native_expect_private_error(error, credential)
  })
})

test_that("native ODBC connection errors retain diagnostics without bearer tokens", {
  skip_if_not_installed("odbc")
  token <- paste(
    "synthetic",
    paste(format(openssl::rand_bytes(24)), collapse = ""),
    "signature",
    sep = "."
  )
  driver <- paste0("shinyOAuthDB_missing_driver_", Sys.getpid())
  reference <- tryCatch(
    DBI::dbConnect(odbc::odbc(), driver = driver),
    error = identity
  )
  expect_s3_class(reference, "error")
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    auth$token(auth$make_token(token))
    factories <- list(
      function() {
        oauth_db_athena(
          auth$connection,
          workgroup_arn = "arn:aws:athena:eu-west-1:123456789012:workgroup/reporting",
          application_role_arn = "arn:aws:iam::123456789012:role/AthenaApplication",
          s3_output_location = "s3://query-results/reporting/",
          driver = driver
        )
      },
      function() {
        oauth_db_singlestore(
          auth$connection,
          "sql.example",
          ssl_ca = "ca.pem",
          driver = driver
        )
      },
      function() {
        oauth_db_hana(auth$connection, "hana.example", driver = driver)
      },
      function() {
        oauth_db_snowflake(
          auth$connection,
          "account.example",
          role = "reader",
          required_scopes = "read",
          driver = driver
        )
      },
      function() {
        oauth_db_redshift(
          auth$connection,
          "redshift.example",
          "reporting",
          driver = driver
        )
      }
    )
    for (factory in factories) {
      con <- factory()
      error <- tryCatch(con(), error = identity)
      expect_identical(class(error), class(reference))
      expect_identical(conditionMessage(error), conditionMessage(reference))
      expect_false(any(grepl(token, capture.output(dput(error)), fixed = TRUE)))
      expect_false(grepl(
        token,
        rawToChar(serialize(error, NULL, ascii = TRUE)),
        fixed = TRUE
      ))
    }
  })
})

test_that("ODBC errors cannot retain credentials through the evaluation frame", {
  local_mocked_bindings(
    dbConnect = function(...) {
      error <- simpleError("native connection failed")
      error$frame <- parent.frame()
      stop(error)
    },
    .package = "DBI"
  )
  token <- paste(format(openssl::rand_bytes(24)), collapse = "")
  error <- tryCatch(
    .odb_odbc_connect(list(drv = "fixture", pwd = token)),
    error = identity
  )
  expect_s3_class(error, "simpleError")
  expect_identical(conditionMessage(error), "native connection failed")
  expect_false(grepl(
    token,
    rawToChar(serialize(error, NULL, ascii = TRUE)),
    fixed = TRUE
  ))
})

test_that("ODBC errors preserve trace calls without their source environments", {
  token <- paste(format(openssl::rand_bytes(24)), collapse = "")
  source <- srcfilecopy("driver.R", "native_connect()")
  source$credential <- token
  call <- quote(native_connect())
  attr(call, "srcref") <- srcref(source, c(1L, 1L, 1L, 16L, 1L, 16L))
  trace <- rlang::trace_back(top = globalenv())
  trace$call[[1L]] <- call
  local_mocked_bindings(
    dbConnect = function(...) {
      error <- simpleError("native connection failed", call = call)
      error$trace <- trace
      stop(error)
    },
    .package = "DBI"
  )
  error <- tryCatch(.odb_odbc_connect(list(drv = "fixture")), error = identity)
  expect_s3_class(error, "simpleError")
  expect_identical(conditionMessage(error), "native connection failed")
  expect_identical(conditionCall(error), quote(native_connect()))
  expect_identical(error$trace$call[[1L]], quote(native_connect()))
  expect_false(grepl(
    token,
    rawToChar(serialize(error, NULL, ascii = TRUE)),
    fixed = TRUE
  ))
})

test_that("Dremio errors retain diagnostics without credential frames or source references", {
  skip_if_not_installed("adbi", "0.1.2")
  skip_if_not_installed("adbcdrivermanager", "0.25.0")
  local_mocked_bindings(adbi = function(...) "fixture", .package = "adbi")
  local_mocked_bindings(
    adbc_driver = function(...) "fixture-driver",
    .package = "adbcdrivermanager"
  )
  token <- paste(format(openssl::rand_bytes(24)), collapse = "")
  source <- srcfilecopy("driver.R", "native_connect()")
  source$credential <- token
  call <- quote(native_connect())
  attr(call, "srcref") <- srcref(source, c(1L, 1L, 1L, 16L, 1L, 16L))
  trace <- rlang::trace_back(top = globalenv())
  trace$call[[1L]] <- call
  local_mocked_bindings(
    dbConnect = function(...) {
      error <- simpleError("Flight SQL connection failed", call = call)
      error$frame <- parent.frame()
      error$trace <- trace
      stop(error)
    },
    .package = "DBI"
  )
  provider <- local({
    value <- token
    function() value
  })
  error <- tryCatch(
    .odb_backend_dremio(
      provider,
      "dremio.example",
      32010L,
      "flightsql",
      NULL,
      30,
      list()
    ),
    error = identity
  )
  expect_s3_class(error, "simpleError")
  expect_identical(conditionMessage(error), "Flight SQL connection failed")
  expect_identical(conditionCall(error), quote(native_connect()))
  expect_identical(error$trace$call[[1L]], quote(native_connect()))
  expect_null(error$frame$args)
  expect_false(exists("token", error$frame, inherits = FALSE))
  expect_false(grepl(
    token,
    rawToChar(serialize(error, NULL, ascii = TRUE)),
    fixed = TRUE
  ))
})
