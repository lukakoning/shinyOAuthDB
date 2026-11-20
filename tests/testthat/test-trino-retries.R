trino_mock_attempts <- function(respond, envir = parent.frame()) {
  force(respond)
  local_mocked_bindings(
    curl_fetch = function(handle, url, path) {
      request <- httr2::last_request()
      response <- respond(request)
      list(
        curl_data = list(
          method = httr2::req_get_method(request),
          url = url,
          status_code = httr2::resp_status(response),
          headers = httr2::resp_headers(response),
          times = NULL
        ),
        body = response$body
      )
    },
    .package = "httr2",
    .env = envir
  )
}

test_that("Trino cannot replay statement submissions through native HTTP retries", {
  skip_if_not_installed("RTrino", "0.1.0")
  for (status in c(429L, 502L, 503L, 504L)) {
    local({
      submissions <- 0L
      trino_mock_attempts(function(req) {
        if (httr2::req_get_method(req) == "POST") {
          submissions <<- submissions + 1L
          expect_true(req$options$fresh_connect)
          expect_true(req$options$forbid_reuse)
          expect_false(req$options$followlocation)
          return(odb_http_response("PRIVATE_GATEWAY_BODY", status))
        }
        trino_test_response(req)
      })
      odb_test_domain(function(session) {
        auth <- odb_test_authorization(session)
        con <- oauth_db_trino(
          auth$connection,
          "trino.example.org",
          "lake",
          "reports",
          user = "reader"
        )
        native <- con()
        failure <- expect_error(
          DBI::dbExecute(native, "INSERT INTO audit_log VALUES (1)"),
          class = "shinyOAuthDB_request_failed"
        )
        expect_match(conditionMessage(failure), "not retried automatically")
        expect_false(grepl("PRIVATE_GATEWAY_BODY", conditionMessage(failure)))
        expect_identical(submissions, 1L)
        expect_identical(auth$calls$acquire, 0L)
      })
    })
  }
})

test_that("Trino rejects authorization changes before another HTTP attempt", {
  skip_if_not_installed("RTrino", "0.1.0")
  for (method in c("GET", "POST")) {
    for (transition in c("logout", "replace", "permissions")) {
      local({
        attempts <- 0L
        selected <- auth <- replacement <- NULL
        trino_mock_attempts(function(req) {
          if (httr2::req_get_method(req) == method) {
            attempts <<- attempts + 1L
            switch(
              transition,
              logout = selected(NULL),
              replace = selected(replacement$connection),
              permissions = auth$token(auth$make_token("denied", "write"))
            )
            return(odb_http_response("PRIVATE_GATEWAY_BODY", 503L))
          }
          trino_test_response(req)
        })
        odb_test_domain(function(session) {
          auth <<- odb_test_authorization(session)
          replacement <<- odb_test_authorization(session, "B")
          selected <<- shiny::reactiveVal(auth$connection)
          con <- oauth_db_trino(
            selected,
            "trino.example.org",
            "lake",
            "reports",
            user = "reader",
            required_scopes = "read"
          )
          if (method == "GET") {
            expect_error(
              con(),
              class = "shinyOAuthDB_authorization_unavailable"
            )
          } else {
            native <- con()
            expect_error(
              DBI::dbExecute(native, "INSERT INTO audit_log VALUES (1)"),
              class = "shinyOAuthDB_authorization_unavailable"
            )
          }
          expect_identical(attempts, 1L)
        })
      })
    }
  }
})

test_that("Trino safe read retries use renewed credentials", {
  skip_if_not_installed("RTrino", "0.1.0")
  auth <- NULL
  attempts <- 0L
  credentials <- character()
  trino_mock_attempts(function(req) {
    attempts <<- attempts + 1L
    signed <- req
    signed$headers <- req$state$headers
    credentials <<- c(
      credentials,
      httr2::req_get_headers(signed, redacted = "reveal")$Authorization
    )
    if (attempts == 1L) {
      auth$token(auth$make_token("renewed-token"))
      return(odb_http_response("", 503L))
    }
    trino_test_response(req)
  })
  odb_test_domain(function(session) {
    auth <<- odb_test_authorization(session)
    con <- oauth_db_trino(
      auth$connection,
      "trino.example.org",
      "lake",
      "reports",
      user = "reader"
    )
    native <- con()
    expect_s4_class(native, "TrinoConnection")
    expect_identical(attempts, 2L)
    expect_identical(credentials, c("Bearer fixture-A", "Bearer renewed-token"))
  })
})
