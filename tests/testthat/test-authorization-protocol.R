test_that("malformed permission evidence cannot acquire a token or open a connection", {
  invalid <- list(NULL, logical(), NA, 1, "TRUE", c(TRUE, FALSE))
  for (permissions in invalid) odb_test_domain(function(session) {
    acquired <- opened <- 0L
    grant <- list(id = "permission-contract",
      has_scopes = function(scopes, target = NULL) permissions,
      access_token = function(...) { acquired <<- acquired + 1L; "fixture-token" })
    con <- oauth_db_connect(grant, required_scopes = "read", connect = function(token) {
      opened <<- opened + 1L
      new.env()
    })
    expect_error(con(), class = "shinyOAuthDB_invalid_authorization")
    session$flushReact()
    expect_error(con(), class = "shinyOAuthDB_invalid_authorization")
    expect_identical(acquired, 0L)
    expect_identical(opened, 0L)
  })
  odb_test_domain(function(session) {
    allowed <- shiny::reactiveVal(FALSE)
    acquired <- opened <- 0L
    grant <- list(id = "valid-permissions",
      has_scopes = function(scopes, target = NULL) allowed(),
      access_token = function(...) { acquired <<- acquired + 1L; "fixture-token" })
    con <- oauth_db_connect(grant, required_scopes = "read", connect = function(token) {
      opened <<- opened + 1L
      expect_identical(token, "fixture-token")
      new.env()
    })
    expect_error(con(), class = "shiny.silent.error")
    expect_identical(acquired, 0L)
    expect_identical(opened, 0L)
    allowed(TRUE)
    session$flushReact()
    expect_type(con(), "environment")
    expect_identical(acquired, 1L)
    expect_identical(opened, 1L)
  })
})

test_that("unexpected expiry validation failures remain errors rather than permission evidence", {
  errors <- list(errorCondition("fixture provider failure", class = "fixture_provider_error"),
    structure(list(message = "Unsupported token target", call = NULL,
      context = list(reason = "unsupported_target")),
      class = c("shinyOAuth_access_error", "error", "condition")))
  for (problem in errors) odb_test_domain(function(session) {
    opened <- 0L
    grant <- list(id = "expiry-validation",
      has_scopes = function(scopes, target = NULL) TRUE,
      summary = function() list(status = "expired"),
      access_token = function(...) stop(problem))
    con <- oauth_db_connect(grant, required_scopes = "read", connect = function(token) {
      opened <<- opened + 1L
      new.env()
    })
    for (attempt in 1:2) {
      failure <- tryCatch(con(), error = identity)
      expect_identical(class(failure), class(problem))
      expect_identical(conditionMessage(failure), conditionMessage(problem))
      expect_identical(failure$context, problem$context)
      session$flushReact()
    }
    expect_identical(opened, 0L)
  })
})
