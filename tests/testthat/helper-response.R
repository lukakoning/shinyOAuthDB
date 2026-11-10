# Response matrices use fixed credentials; authorization lifecycle tests use
# the real module-created connection fixtures in helper-authorization.R.
odb_test_response_authorization <- function() {
  list(
    connection = list(
      id = "response-fixture",
      has_scopes = function(...) TRUE,
      summary = function() list(status = "active"),
      access_token = function(...) "fixture-A"
    )
  )
}
