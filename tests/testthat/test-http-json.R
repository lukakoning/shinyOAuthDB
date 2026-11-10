test_that("JSON response parsing never follows file paths or URLs", {
  withr::local_dir(withr::local_tempdir())
  canary <- paste0(
    '{"code":"42P01","error":{"errors":[{"reason":"invalidQuery"}]},',
    '"cols":["proof"],"col_types":["4"],',
    '"rows":[["local-file-read"]],"rowcount":"1"}'
  )
  writeLines(canary, "canary.json")
  for (body in c("canary.json", "https://internal.example/canary")) {
    response <- odb_http_response(body)
    expect_error(
      .odb_http_json(response, "test"),
      class = "shinyOAuthDB_invalid_response"
    )
    for (service in c("PostgREST", "BigQuery")) {
      expect_null(
        .odb_http_diagnostics(response, service, character())$service_code
      )
    }
    expect_s3_class(
      tryCatch(.odb_cratedb_result(response), error = identity),
      "shinyOAuthDB_invalid_response"
    )
  }
})

test_that("literal JSON parsing retains content types, simplification and exact integers", {
  body <- '[{"id":9007199254740993,"name":"caf\u00e9"}]'
  response <- httr2::response(
    status_code = 200L,
    headers = list("Content-Type" = "application/problem+json; charset=utf-8"),
    body = charToRaw(enc2utf8(body))
  )
  value <- .odb_http_json(response, "test", simplify = TRUE)
  expect_identical(
    value,
    data.frame(id = "9007199254740993", name = "caf\u00e9")
  )
  expect_identical(
    .odb_http_json(response, "test"),
    list(list(id = "9007199254740993", name = "caf\u00e9"))
  )
  response <- httr2::response(
    status_code = 200L,
    headers = list("Content-Type" = "text/plain"),
    body = charToRaw(body)
  )
  expect_error(
    .odb_http_json(response, "test"),
    class = "shinyOAuthDB_invalid_response"
  )
})
