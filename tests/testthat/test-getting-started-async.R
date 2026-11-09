getting_started_chunk <- function(label) {
  path <- test_path("..", "..", "vignettes", "getting-started.Rmd")
  skip_if_not(file.exists(path), "Vignette source is unavailable")
  lines <- readLines(path, encoding = "UTF-8")
  start <- grep(paste0("^`{3}\\{r ", label, "[,}]"), lines)
  stopifnot(length(start) == 1L)
  end <- which(seq_along(lines) > start & lines == "```")[[1L]]
  parse(text = lines[seq.int(start + 1L, end - 1L)])
}

test_that("the getting-started app configures and cleans up async OAuth workers", {
  skip_if_not_installed("mirai", "2.5.1")
  calls <- new.env(parent = emptyenv())
  calls$workers <- integer()
  calls$stops <- list()
  calls$demo_stops <- 0L
  local_mocked_bindings(
    daemons = function(n, ...) {
      calls$workers <- c(calls$workers, n)
    },
    .package = "mirai"
  )
  envir <- new.env(parent = globalenv())
  envir$oauth_db_demo <- function(...) {
    list(
      provider = shinyOAuth::oauth_provider(
        name = "postgrest",
        auth_url = "https://example.invalid/authorize",
        token_url = "https://example.invalid/token"
      ),
      url = "https://data.example",
      stop = function() {
        calls$demo_stops <- calls$demo_stops + 1L
      }
    )
  }
  envir$onStop <- function(fun) {
    calls$stops[[length(calls$stops) + 1L]] <- fun
  }
  envir$runApp <- function(app, ...) app
  app <- eval(getting_started_chunk("app"), envir)
  expect_s3_class(app, "shiny.appobj")
  expect_identical(calls$workers, integer())
  app$onStart()
  expect_equal(calls$workers, 2)
  envir$oauth_module_server <- function(id, client, auto_redirect, async) {
    expect_identical(id, "auth")
    expect_false(auto_redirect)
    expect_true(async)
    list(connection = function() NULL)
  }
  shiny::testServer(envir$server, {
    expect_error(output$rows, class = "shiny.silent.error")
    expect_equal(calls$workers, 2)
  })
  for (stop in calls$stops) {
    stop()
  }
  expect_equal(calls$workers, c(2, 0))
  expect_identical(calls$demo_stops, 1L)
})


test_that("the getting-started fetch example uses the public task interface", {
  skip_if_not_installed("mirai", "2.5.1")
  task_app_workers()
  envir <- new.env(parent = asNamespace("shiny"))
  calls <- new.env(parent = emptyenv())
  httr2::local_mocked_responses(function(req) {
    expect_identical(
      httr2::req_get_headers(req, redacted = "reveal")$Authorization,
      "Bearer fixture-A"
    )
    calls$requests <- calls$requests + 1L
    odb_http_response('[{"row_id":1,"value":"example-result"}]')
  })
  calls$requests <- 0L
  server <- function(input, output, session) {
    auth <- odb_test_authorization(session, "A", "database.read")
    postgres <- oauth_db_postgrest_api(auth$connection, "https://data.example")
    eval(getting_started_chunk("async-fetch"))
  }
  shiny::testServer(server, {
    expect_error(output$rows, class = "shiny.silent.error")
    expect_identical(calls$requests, 0L)
    session$setInputs(load = 1L)
    task_app_flush(session)
    expect_match(output$rows, "example-result", fixed = TRUE)
    expect_identical(calls$requests, 1L)
    auth$current(FALSE)
    task_app_flush(session)
    expect_error(output$rows, class = "shiny.silent.error")
  })
})
