bq_test_response <- function(payload, status = 200L) {
  httr2::response(
    status_code = status,
    headers = list("Content-Type" = "application/json"),
    body = charToRaw(jsonlite::toJSON(
      payload,
      auto_unbox = TRUE,
      null = "null"
    ))
  )
}

bq_test_result <- function(values = c("first", "second")) {
  list(
    jobComplete = TRUE,
    jobReference = list(
      projectId = "billing",
      jobId = "job-1",
      location = "EU"
    ),
    schema = list(fields = list(list(name = "value", type = "STRING"))),
    totalRows = as.character(length(values)),
    rows = lapply(values, function(x) list(f = list(list(v = x))))
  )
}
