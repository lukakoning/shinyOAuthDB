trino_test_response <- function(req, paginate = FALSE) {
  user <- httr2::req_get_headers(req, redacted = "reveal")[["X-Trino-User"]]
  value <- if (grepl("/v1/info$", req$url)) {
    list(
      nodeVersion = list(version = "484"),
      environment = "fixture",
      starting = FALSE
    )
  } else {
    result <- list(
      id = "fixture-query",
      infoUri = "https://trino.example.org/query",
      columns = list(list(
        name = "database_user",
        type = "varchar",
        typeSignature = list(rawType = "varchar", arguments = list())
      )),
      stats = list(state = "FINISHED"),
      data = list(list(user))
    )
    if (identical(req$method, "POST") && paginate) {
      result$stats$state <- "RUNNING"
      result$data <- NULL
      result$nextUri <- "https://trino.example.org/v1/statement/fixture-query/1"
    }
    result
  }
  httr2::response(
    status_code = 200,
    url = req$url,
    headers = list("Content-Type" = "application/json"),
    body = charToRaw(jsonlite::toJSON(value, auto_unbox = TRUE, null = "null"))
  )
}
