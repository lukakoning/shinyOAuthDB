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
