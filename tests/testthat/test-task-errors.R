test_that("worker failures redact overlapping credentials in every diagnostic field", {
  short <- "synthetic-short"
  long <- paste0(short, "-private-suffix")
  native_error <- errorCondition(
    paste("Failure", long, short),
    class = "native_worker_failure",
    reason = paste0("reason-", long),
    status = 403L,
    service = paste0("service-", long),
    service_code = paste0("code-", long),
    request_id = paste0("id-", long)
  )
  local_mocked_bindings(.odb_task_run = function(...) stop(native_error))
  for (credentials in list(
    list(short, long),
    list(long, short),
    list(short, long, short)
  )) {
    result <- .odb_task_job(NULL, credentials, NULL, NULL, NULL)
    expect_false(result$ok)
    expect_s3_class(result$error, "native_worker_failure")
    expect_identical(
      conditionMessage(result$error),
      "Failure [REDACTED] [REDACTED]"
    )
    expect_identical(result$error$reason, "reason-[REDACTED]")
    expect_identical(result$error$status, 403L)
    expect_identical(result$error$service, "service-[REDACTED]")
    expect_identical(result$error$service_code, "code-[REDACTED]")
    expect_identical(result$error$request_id, "id-[REDACTED]")
    expect_null(result$error$call)
    stored <- rawToChar(serialize(result$error, NULL, ascii = TRUE))
    expect_false(grepl(short, stored, fixed = TRUE))
    expect_false(grepl("private-suffix", stored, fixed = TRUE))
  }
})

test_that("worker failures sanitize classes and discard diagnostic attributes", {
  credential <- "synthetic-private-credential"
  frame <- new.env(parent = emptyenv())
  frame$credential <- credential
  native_error <- errorCondition(
    paste("Failure", credential),
    class = c("native_worker_failure", paste0("native_", credential)),
    reason = structure(
      "denied",
      names = credential,
      private = charToRaw(credential)
    ),
    status = structure(403L, frame = frame),
    service = structure("Database", callback = function() credential),
    service_code = structure("DENIED", pointer = methods::new("externalptr")),
    request_id = structure("request-1", private = list(credential)),
    parent = simpleError(credential)
  )
  local_mocked_bindings(.odb_task_run = function(...) stop(native_error))
  result <- .odb_task_job(NULL, list(credential), NULL, NULL, NULL)
  expect_false(result$ok)
  expect_s3_class(result$error, "native_worker_failure")
  expect_identical(conditionMessage(result$error), "Failure [REDACTED]")
  expect_identical(result$error$reason, "denied")
  expect_identical(result$error$status, 403L)
  expect_identical(result$error$service, "Database")
  expect_identical(result$error$service_code, "DENIED")
  expect_identical(result$error$request_id, "request-1")
  expect_null(result$error$parent)
  stored <- rawToChar(serialize(result$error, NULL, ascii = TRUE))
  expect_false(grepl(credential, stored, fixed = TRUE))
})

test_that("worker diagnostics omit missing, structured and non-scalar fields", {
  native_error <- errorCondition(
    "Worker failed",
    reason = factor("denied"),
    status = as.raw(1),
    service = NA_character_,
    service_code = c("first", "second"),
    request_id = list("private")
  )
  local_mocked_bindings(.odb_task_run = function(...) stop(native_error))
  result <- .odb_task_job(NULL, list("fixture-A"), NULL, NULL, NULL)
  expect_false(result$ok)
  expect_named(result$error, c("message", "call"))
})

test_that("real worker error metadata reaches the owning session without credentials", {
  compute <- paste0("oauthdb-error-test-", Sys.getpid())
  skip_if(
    mirai::daemons_set(.compute = compute),
    "Preserve an existing worker pool"
  )
  mirai::daemons(1, .compute = compute, autoexit = NA)
  withr::defer(mirai::daemons(0, .compute = compute))
  paths <- .libPaths()
  package_path <- system.file(package = "shinyOAuthDB")
  mirai::everywhere(
    {
      .libPaths(paths)
      if (!file.exists(file.path(package_path, "Meta", "package.rds"))) {
        pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      } else {
        library(shinyOAuthDB)
      }
    },
    paths = paths,
    package_path = package_path,
    .compute = compute
  )
  odb_test_domain(function(session) {
    source <- oauth_db_postgrest_api(
      odb_test_response_authorization()$connection,
      "https://data.example"
    )
    task <- oauth_db_task(source, compute = compute, method = function(client) {
      stop(errorCondition(
        "Worker failed",
        class = c("native_worker_failure", "fixture-A"),
        status = structure(403L, credential = "fixture-A")
      ))
    })
    expect_true(task$invoke())
    deadline <- proc.time()[["elapsed"]] + 30
    while (task$status() == "running" && proc.time()[["elapsed"]] < deadline) {
      later::run_now(0.01)
      session$flushReact()
    }
    expect_identical(task$status(), "error")
    error <- tryCatch(task$result(), error = identity)
    expect_s3_class(error, "native_worker_failure")
    expect_identical(error$status, 403L)
    expect_false(grepl(
      "fixture-A",
      rawToChar(serialize(error, NULL, ascii = TRUE)),
      fixed = TRUE
    ))
  })
})
