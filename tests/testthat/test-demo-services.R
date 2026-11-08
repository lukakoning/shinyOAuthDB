test_that("services mode returns to R without starting Shiny and restores its settings", {
  withr::local_options(list(
    shinyOAuth.allowed_hosts = "existing.example",
    shinyOAuth.allow_insecure_oidc_loopback = FALSE
  ))
  previous <- options()[c(
    "shinyOAuth.allowed_hosts",
    "shinyOAuth.allow_insecure_oidc_loopback"
  )]
  tls <- Sys.getenv(
    c("CURL_CA_BUNDLE", "CURL_SSL_BACKEND"),
    unset = NA_character_
  )
  calls <- list()
  local_mocked_bindings(
    .odb_demo_docker = function() "docker",
    .odb_demo_local_require = function(...) {
      stop("No local driver should be needed")
    },
    .odb_demo_local_run = function(...) stop("No app should start"),
    .odb_demo_command = function(docker, args, check = TRUE) {
      calls[[length(calls) + 1L]] <<- args
      if ("cp" %in% args) {
        writeLines("public CA", tail(args, 1L))
      }
      0L
    }
  )
  path <- file.path(withr::local_tempdir(), "services with spaces")
  demo <- suppressMessages(oauth_db_demo(
    "postgrest",
    action = "services",
    path = path
  ))
  withr::defer(demo$stop())
  expect_true(is.environment(demo))
  expect_identical(demo$url, "http://127.0.0.1:19444")
  expect_identical(demo$host, "localhost")
  expect_identical(demo$port, 19444L)
  expect_null(demo$ca_bundle)
  expect_identical(
    demo$provider@issuer,
    "https://localhost:18443/realms/shinyoauthdb"
  )
  expect_match(demo$provider@auth_url, "^https://localhost:18443/")
  expect_match(demo$provider@token_url, "^http://localhost:18080/")
  expect_true(demo$provider@id_token_validation)
  expect_true(demo$provider@use_pkce)
  expect_true(demo$provider@use_nonce)
  expect_identical(tail(calls[[2L]], 1L), "local")
  expect_true(
    file.path(demo$path, "postgrest", "compose.services.yml") %in% calls[[2L]]
  )
  expect_false(any(vapply(
    calls,
    function(args) "down" %in% args || "--follow" %in% args,
    logical(1)
  )))
  expect_true(getOption("shinyOAuth.allow_insecure_oidc_loopback"))
  expect_identical(Sys.getenv(names(tls), unset = NA_character_), tls)
  suppressMessages(demo$stop())
  expect_identical(
    tail(calls[[3L]], 3L),
    c("down", "--volumes", "--remove-orphans")
  )
  expect_identical(options()[names(previous)], previous)
  expect_identical(Sys.getenv(names(tls), unset = NA_character_), tls)
  demo$stop()
  expect_length(calls, 3L)
})

for (failure in c("up", "cp", "provider")) {
  local({
    stage <- failure
    test_that(paste("services mode cleans up after a failed", stage), {
      withr::local_options(list(
        shinyOAuth.allowed_hosts = "existing.example",
        shinyOAuth.allow_insecure_oidc_loopback = FALSE
      ))
      previous <- options()[c(
        "shinyOAuth.allowed_hosts",
        "shinyOAuth.allow_insecure_oidc_loopback"
      )]
      calls <- list()
      local_mocked_bindings(
        .odb_demo_docker = function() "docker",
        .odb_demo_command = function(docker, args, check = TRUE) {
          calls[[length(calls) + 1L]] <<- args
          if (stage == "up" && "up" %in% args) {
            return(1L)
          }
          if (stage == "cp" && "cp" %in% args) {
            stop("copy failed")
          }
          if ("cp" %in% args) {
            writeLines("public CA", tail(args, 1L))
          }
          0L
        }
      )
      if (stage == "provider") {
        local_mocked_bindings(
          oauth_provider = function(...) stop("provider failed"),
          .package = "shinyOAuth"
        )
      }
      expect_error(
        suppressMessages(oauth_db_demo(
          if (stage == "cp") "trino" else "postgrest",
          action = "services",
          path = file.path(withr::local_tempdir(), "services")
        )),
        switch(
          stage,
          up = "could not start",
          cp = "copy failed",
          provider = "provider failed"
        )
      )
      expect_true("down" %in% tail(calls, 1L)[[1L]])
      expect_identical(options()[names(previous)], previous)
    })
  })
}

test_that("services stop can be retried and preserves later user option changes", {
  withr::local_options(list(
    shinyOAuth.allowed_hosts = "existing.example",
    shinyOAuth.allow_insecure_oidc_loopback = FALSE
  ))
  calls <- 0L
  demo <- .odb_demo_services_settings(
    tempdir(),
    function() {
      calls <<- calls + 1L
      if (calls == 1L) 1L else 0L
    },
    "postgrest"
  )
  withr::defer(try(demo$stop(), silent = TRUE))
  expect_error(demo$stop(), "Retry")
  expect_true(getOption("shinyOAuth.allow_insecure_oidc_loopback"))
  options(shinyOAuth.allowed_hosts = "later.example")
  suppressMessages(demo$stop())
  expect_identical(getOption("shinyOAuth.allowed_hosts"), "later.example")
  expect_false(getOption("shinyOAuth.allow_insecure_oidc_loopback"))
  demo$stop()
  expect_identical(calls, 2L)
})

test_that("discarded service handles clean up their containers", {
  withr::local_options(list(shinyOAuth.allow_insecure_oidc_loopback = FALSE))
  calls <- 0L
  create <- function() {
    demo <- .odb_demo_services_settings(
      tempdir(),
      function() {
        calls <<- calls + 1L
        0L
      },
      "postgrest"
    )
    expect_true(is.environment(demo))
    invisible(NULL)
  }
  create()
  suppressMessages(gc())
  expect_identical(calls, 1L)
  expect_false(getOption("shinyOAuth.allow_insecure_oidc_loopback"))
})

test_that("the PostgREST HTTP exception is confined to its active demo", {
  endpoint <- "http://127.0.0.1:19444"
  expect_error(.odb_demo_postgrest_url(endpoint), "HTTPS")
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    odb_http_response('[{"marker":"visible"}]')
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    demo <- .odb_demo_services_settings(tempdir(), function() 0L, "postgrest")
    withr::defer(demo$stop())
    expect_identical(.odb_demo_postgrest_url(endpoint), endpoint)
    for (other in c(
      "http://localhost:19444",
      "http://127.0.0.1:19445",
      "http://example.org:19444",
      "http://127.0.0.1:19444/path",
      "http://user@127.0.0.1:19444",
      "http://127.0.0.1:19444?query=1"
    )) {
      expect_error(.odb_demo_postgrest_url(other), "HTTPS")
    }
    expect_error(.odb_http_url(endpoint), "HTTPS")
    api <- oauth_db_postgrest_api(auth$connection, demo$url)
    expect_identical(api$select("visible_rows")$marker, "visible")
    suppressMessages(demo$stop())
    expect_error(api$select("visible_rows"), "HTTPS")
    expect_error(oauth_db_postgrest_api(auth$connection, endpoint), "HTTPS")
    expect_identical(calls, 1L)
  })
})
