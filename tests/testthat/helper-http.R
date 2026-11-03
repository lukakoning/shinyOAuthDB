odb_http_response <- function(text = "[]", status = 200L, headers = list()) {
  httr2::response(status_code = status,
    headers = c(list("Content-Type" = "application/json"), headers), body = charToRaw(text))
}
