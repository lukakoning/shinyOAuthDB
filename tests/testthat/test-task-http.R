test_that("ClickHouse execution tasks return successful HTTP acknowledgements", {
  task_app_workers()
  submissions <- 0L
  httr2::local_mocked_responses(function(req) {
    submissions <<- submissions + 1L
    response <- httr2::response(
      status_code = 204L,
      method = "POST",
      url = req$url,
      headers = list("X-Request-Id" = "write-1"),
      timing = c(total = 0.1)
    )
    response$request <- req
    response$cache$private <- "fixture-A"
    response
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_clickhouse_api(auth$connection, "https://click.example")
    task <- oauth_db_task(api, method = "execute")
    expect_true(task$invoke("CREATE TABLE example (id UInt64) ENGINE=Memory"))
    task_app_flush(session)
    expect_identical(task$status(), "success")
    response <- task$result()
    expect_s3_class(response, "httr2_response")
    expect_identical(httr2::resp_status(response), 204L)
    expect_identical(httr2::resp_header(response, "X-Request-Id"), "write-1")
    expect_identical(response$timing, c(total = 0.1))
    expect_false(httr2::resp_has_body(response))
    expect_null(response$request)
    expect_true(is.environment(response$cache))
    expect_length(ls(response$cache, all.names = TRUE), 0L)
    expect_false(grepl(
      "fixture-A",
      rawToChar(serialize(response, NULL, ascii = TRUE)),
      fixed = TRUE
    ))
    expect_identical(task$result(), response)
    expect_identical(submissions, 1L)
  })
})

test_that("raw and nested HTTP task results retain usable response bodies", {
  task_app_workers()
  httr2::local_mocked_responses(function(req) {
    response <- odb_http_response('[{"id":42}]')
    response$request <- req
    response$cache$private <- "fixture-A"
    response
  })
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_postgrest_api(auth$connection, "https://data.example")
    raw <- oauth_db_task(api, method = "select")
    expect_true(raw$invoke("orders", raw = TRUE))
    task_app_flush(session)
    expect_identical(raw$status(), "success")
    expect_identical(
      httr2::resp_body_json(raw$result(), simplifyVector = TRUE),
      data.frame(id = 42L)
    )
    nested <- oauth_db_task(api, method = function(client) {
      list(response = client$select("orders", raw = TRUE), missing = NULL)
    })
    expect_true(nested$invoke())
    task_app_flush(session)
    expect_identical(nested$status(), "success")
    result <- nested$result()
    expect_named(result, c("response", "missing"))
    expect_null(result$missing)
    expect_identical(httr2::resp_status(result$response), 200L)
    expect_identical(
      httr2::resp_body_json(result$response, simplifyVector = TRUE),
      data.frame(id = 42L)
    )
    expect_null(result$response$request)
    expect_false(grepl(
      "fixture-A",
      rawToChar(serialize(result, NULL, ascii = TRUE)),
      fixed = TRUE
    ))
  })
})

test_that("HTTP response transfer preserves ordinary result types and metadata", {
  task_app_workers()
  methods <- list(
    function(client) pairlist(first = 1L, missing = NULL),
    function(client) {
      structure(
        list(1L, 2L),
        names = c("id", "id"),
        class = "data.frame",
        row.names = 1L
      )
    }
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_postgrest_api(auth$connection, "https://data.example")
    for (method in methods) {
      task <- oauth_db_task(api, method = method)
      expect_true(task$invoke())
      task_app_flush(session)
      expect_identical(task$status(), "success")
      expect_identical(task$result(), method(NULL))
    }
  })
})

test_that("real workers transfer HTTP responses without credential environments", {
  compute <- paste0("oauthdb-http-result-", Sys.getpid())
  skip_if(mirai::daemons_set(.compute = compute), "Preserve an existing pool")
  mirai::daemons(1, .compute = compute, autoexit = NA)
  withr::defer(mirai::daemons(0, .compute = compute))
  paths <- .libPaths()
  package_path <- system.file(package = "shinyOAuthDB")
  mirai::everywhere(
    {
      .libPaths(paths)
      if (!file.exists(file.path(package_path, "Meta", "package.rds"))) {
        pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      } else {
        library(shinyOAuthDB)
      }
    },
    paths = paths,
    package_path = package_path,
    .compute = compute
  )
  odb_test_domain(function(session) {
    auth <- odb_test_authorization(session)
    api <- oauth_db_postgrest_api(auth$connection, "https://data.example")
    task <- oauth_db_task(api, compute = compute, method = function(client) {
      response <- httr2::response(
        headers = list("Content-Type" = "application/json"),
        body = charToRaw('[{"id":42}]')
      )
      response$request <- httr2::req_auth_bearer_token(
        httr2::request("https://data.example"),
        "fixture-A"
      )
      response$cache$private <- "fixture-A"
      response
    })
    expect_true(task$invoke())
    deadline <- proc.time()[["elapsed"]] + 30
    while (task$status() == "running" && proc.time()[["elapsed"]] < deadline) {
      later::run_now(0.01)
      session$flushReact()
    }
    expect_identical(task$status(), "success")
    response <- task$result()
    expect_s3_class(response, "httr2_response")
    expect_identical(
      httr2::resp_body_json(response, simplifyVector = TRUE),
      data.frame(id = 42L)
    )
    expect_null(response$request)
    expect_false(grepl(
      "fixture-A",
      rawToChar(serialize(response, NULL, ascii = TRUE)),
      fixed = TRUE
    ))
  })
})
