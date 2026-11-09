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
      stop = function() calls$demo_stops <- calls$demo_stops + 1L
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

getting_started_async <- function(url = "https://data.example") {
  calls <- new.env(parent = emptyenv())
  calls$pending <- list()
  calls$arguments <- list()
  envir <- new.env(parent = asNamespace("shiny"))
  envir$client <- NULL
  envir$demo <- list(url = url)
  envir$oauth_module_server <- function(id, client, auto_redirect, async) {
    expect_true(async)
    session <- shiny::getDefaultReactiveDomain()
    calls$a <- odb_test_authorization(session, "A", "database.read")
    calls$b <- odb_test_authorization(session, "B", "database.read")
    calls$selected <- shiny::reactiveVal(NULL)
    list(
      connection = calls$selected,
      request_login = function() NULL,
      logout = function() calls$selected(NULL)
    )
  }
  eval(getting_started_chunk("async-fetch"), envir)
  list(server = envir$server, calls = calls)
}

async_fetch_flush <- function(session) {
  for (i in seq_len(12L)) {
    later::run_now(0.001)
    session$flushReact()
  }
}

async_fetch_mock <- function(calls) {
  function(.expr, ...) {
    calls$arguments[[length(calls$arguments) + 1L]] <- list(...)
    promises::promise(function(resolve, reject) {
      calls$pending[[length(calls$pending) + 1L]] <- list(
        resolve = resolve,
        reject = reject
      )
    })
  }
}

test_that("background fetching is explicit, ignores busy clicks and survives token rotation", {
  skip_if_not_installed("mirai", "2.5.1")
  app <- getting_started_async()
  calls <- app$calls
  local_mocked_bindings(mirai = async_fetch_mock(calls), .package = "mirai")
  shiny::testServer(app$server, {
    expect_error(output$rows, class = "shiny.silent.error")
    session$setInputs(load = 1L)
    calls$selected(calls$a$connection)
    async_fetch_flush(session)
    expect_length(calls$pending, 0L)
    session$setInputs(load = 2L)
    async_fetch_flush(session)
    expect_length(calls$pending, 1L)
    expect_identical(
      calls$arguments[[1L]],
      list(
        token = "fixture-A",
        url = "https://data.example"
      )
    )
    expect_identical(load_rows$status(), "running")
    expect_error(output$rows, class = "shiny.silent.error")
    session$setInputs(load = 3L)
    async_fetch_flush(session)
    expect_length(calls$pending, 1L)
    calls$pending[[1L]]$resolve(data.frame(value = "first-result"))
    async_fetch_flush(session)
    expect_match(output$rows, "first-result", fixed = TRUE)

    calls$a$token(calls$a$make_token("rotated"))
    async_fetch_flush(session)
    expect_match(output$rows, "first-result", fixed = TRUE)
    expect_length(calls$pending, 1L)
    session$setInputs(load = 4L)
    async_fetch_flush(session)
    expect_identical(calls$arguments[[2L]]$token, "rotated")
    expect_error(output$rows, class = "shiny.silent.error")
    calls$pending[[2L]]$reject(simpleError("Data request failed"))
    expect_warning(
      async_fetch_flush(session),
      "Data request failed",
      fixed = TRUE
    )
    expect_error(output$rows, "Data request failed", fixed = TRUE)
    session$setInputs(load = 5L)
    async_fetch_flush(session)
    calls$pending[[3L]]$resolve(data.frame(value = "retried-result"))
    async_fetch_flush(session)
    expect_match(output$rows, "retried-result", fixed = TRUE)
  })
})

test_that("late results stay hidden across authorization and permission changes", {
  skip_if_not_installed("mirai", "2.5.1")
  for (transition in c(
    "logout",
    "replace",
    "roundtrip",
    "permissions",
    "restore"
  )) {
    app <- getting_started_async()
    calls <- app$calls
    withr::with_options(list(shiny.sanitize.errors = FALSE), {
      local_mocked_bindings(mirai = async_fetch_mock(calls), .package = "mirai")
      shiny::testServer(app$server, {
        calls$selected(calls$a$connection)
        async_fetch_flush(session)
        session$setInputs(load = 1L)
        async_fetch_flush(session)
        expect_length(calls$pending, 1L)
        if (transition == "logout") {
          calls$selected(NULL)
        } else if (transition %in% c("replace", "roundtrip")) {
          calls$selected(calls$b$connection)
        } else {
          calls$a$token(calls$a$make_token("denied", "other.permission"))
        }
        async_fetch_flush(session)
        expect_error(output$rows, class = "shiny.silent.error")
        if (transition == "roundtrip") {
          calls$selected(calls$a$connection)
        } else if (transition == "restore") {
          calls$a$token(calls$a$make_token("restored"))
        }
        async_fetch_flush(session)
        if (transition == "replace") {
          calls$pending[[1L]]$reject(simpleError("Old account request failed"))
          expect_warning(
            async_fetch_flush(session),
            "Old account request failed",
            fixed = TRUE
          )
        } else {
          calls$pending[[1L]]$resolve(data.frame(value = "old-result"))
          async_fetch_flush(session)
        }
        expect_error(output$rows, class = "shiny.silent.error")
        if (transition == "logout") {
          calls$selected(calls$a$connection)
        }
        if (transition == "permissions") {
          calls$a$token(calls$a$make_token("restored"))
        }
        async_fetch_flush(session)
        expect_error(output$rows, class = "shiny.silent.error")
        session$setInputs(load = 2L)
        async_fetch_flush(session)
        expect_length(calls$pending, 2L)
        calls$pending[[2L]]$resolve(data.frame(value = "current-result"))
        async_fetch_flush(session)
        expect_match(output$rows, "current-result", fixed = TRUE)
      })
    })
  }
})

test_that("authorization changes during token acquisition prevent worker dispatch", {
  skip_if_not_installed("mirai", "2.5.1")
  app <- getting_started_async()
  calls <- app$calls
  local_mocked_bindings(mirai = async_fetch_mock(calls), .package = "mirai")
  shiny::testServer(app$server, {
    resolve_token <- NULL
    grant <- list(
      has_scopes = function(scopes) TRUE,
      access_token = function(...) {
        calls$token_arguments <- list(...)
        promises::promise(function(resolve, reject) resolve_token <<- resolve)
      }
    )
    calls$selected(grant)
    async_fetch_flush(session)
    session$setInputs(load = 1L)
    async_fetch_flush(session)
    expect_identical(load_rows$status(), "running")
    expect_identical(
      calls$token_arguments,
      list(
        required_scopes = "database.read",
        min_valid_for_seconds = 120,
        async = TRUE
      )
    )
    calls$selected(NULL)
    async_fetch_flush(session)
    calls$selected(grant)
    async_fetch_flush(session)
    resolve_token("fixture-A")
    async_fetch_flush(session)
    expect_length(calls$pending, 0L)
    expect_error(output$rows, class = "shiny.silent.error")
  })
})

test_that("the vignette's real worker fetch leaves the Shiny session responsive", {
  skip_if_not_installed("mirai", "2.5.1")
  skip_if_not_installed("jsonlite")
  skip_if(mirai::daemons_set(), "An existing worker pool must be preserved")
  calls <- new.env(parent = emptyenv())
  port <- httpuv::randomPort()
  service <- httpuv::startServer(
    "127.0.0.1",
    port,
    list(call = function(req) {
      calls$request <- req
      promises::promise(function(resolve, reject) {
        calls$complete <- function() {
          resolve(list(
            status = 200L,
            headers = list("Content-Type" = "application/json"),
            body = '[{"row_id":1,"value":"worker-result"}]'
          ))
        }
      })
    })
  )
  withr::defer(httpuv::stopServer(service))
  mirai::daemons(1)
  withr::defer(mirai::daemons(0))
  app <- getting_started_async(paste0("http://127.0.0.1:", port))
  shiny::testServer(app$server, {
    app$calls$selected(app$calls$a$connection)
    async_fetch_flush(session)
    session$setInputs(load = 1L)
    deadline <- proc.time()[["elapsed"]] + 15
    while (is.null(calls$complete) && proc.time()[["elapsed"]] < deadline) {
      later::run_now(0.01)
      session$flushReact()
    }
    expect_true(is.function(calls$complete))
    expect_identical(calls$request$PATH_INFO, "/visible_rows")
    expect_identical(calls$request$HTTP_AUTHORIZATION, "Bearer fixture-A")
    expect_match(calls$request$QUERY_STRING, "limit=100", fixed = TRUE)
    expect_identical(load_rows$status(), "running")
    calls$pings <- 0L
    shiny::observeEvent(input$ping, {
      calls$pings <- calls$pings + 1L
    })
    session$setInputs(ping = 1L)
    expect_identical(calls$pings, 1L)
    expect_error(output$rows, class = "shiny.silent.error")
    calls$complete()
    deadline <- proc.time()[["elapsed"]] + 10
    while (
      load_rows$status() == "running" && proc.time()[["elapsed"]] < deadline
    ) {
      later::run_now(0.01)
      session$flushReact()
    }
    expect_identical(load_rows$status(), "success")
    expect_match(output$rows, "worker-result", fixed = TRUE)
    app$calls$selected(NULL)
    async_fetch_flush(session)
    expect_error(output$rows, class = "shiny.silent.error")
    app$calls$selected(app$calls$a$connection)
    async_fetch_flush(session)
    expect_error(output$rows, class = "shiny.silent.error")
  })
})
