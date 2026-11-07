test_that("failed credential consumers recover without replaying successful work", {
  for (target in list(NULL, "data")) {
    for (kind in c("token", "connection", "http")) {
      odb_test_domain(function(session) {
        auth <- odb_test_authorization(session, target = target)
        auth$token(auth$make_token("short-lived", lifetime = 30))
        opened <- requests <- executions <- 0L
        httr2::local_mocked_responses(function(req) {
          requests <<- requests + 1L
          odb_http_response('[{"value":"healthy"}]')
        })
        accessor <- switch(
          kind,
          token = oauth_db_token(auth$connection, target = target),
          connection = oauth_db_connect(
            auth$connection,
            target = target,
            connect = function(token) {
              opened <<- opened + 1L
              list(value = token)
            }
          ),
          http = oauth_db_postgrest_api(
            auth$connection,
            "https://data.example",
            target = target
          )
        )
        rows <- shiny::reactive({
          executions <<- executions + 1L
          if (kind == "http") {
            accessor$select("rows")$value
          } else {
            value <- accessor()
            if (kind == "connection") value$value else value
          }
        })
        expect_error(rows(), class = "shinyOAuth_access_error")
        session$flushReact()
        expect_identical(c(opened, requests), c(0L, 0L))
        auth$token(auth$make_token("healthy"))
        session$flushReact()
        expect_identical(rows(), "healthy")
        expect_identical(executions, 2L)
        auth$token(auth$make_token("rotated"))
        session$flushReact()
        expect_identical(rows(), "healthy")
        expect_identical(executions, 2L)
        expect_identical(opened, as.integer(kind == "connection"))
        expect_identical(requests, as.integer(kind == "http"))
      })
    }
  }
})

test_that("transient refresh and lifetime failures recover when credentials change", {
  for (reason in c("refresh_unavailable", "lifetime_unavailable")) {
    odb_test_domain(function(session) {
      version <- shiny::reactiveVal(0L)
      executions <- 0L
      grant <- list(
        id = "recoverable",
        has_scopes = function(...) TRUE,
        summary = function() {
          version()
          list(status = "active")
        },
        access_token = function(...) {
          if (version() == 0L) {
            getFromNamespace("connection_access_error", "shinyOAuth")(reason)
          }
          paste0("token-", version())
        }
      )
      bearer <- oauth_db_token(grant)
      rows <- shiny::reactive({
        executions <<- executions + 1L
        bearer()
      })
      expect_error(rows(), class = "shinyOAuth_access_error")
      session$flushReact()
      expect_error(rows(), class = "shinyOAuth_access_error")
      expect_identical(executions, 1L)
      version(1L)
      session$flushReact()
      expect_identical(rows(), "token-1")
      version(2L)
      session$flushReact()
      expect_identical(rows(), "token-1")
      expect_identical(executions, 2L)
    })
  }
})
