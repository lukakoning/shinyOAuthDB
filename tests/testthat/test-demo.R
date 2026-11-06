test_that("demo files ship with the package and can be edited without Docker", {
  path <- file.path(withr::local_tempdir(), "demo with spaces")
  local_mocked_bindings(.odb_demo_docker = function() stop("Docker must not be used"))
  expect_identical(oauth_db_demo(action = "files", path = path),
    normalizePath(path, winslash = "/"))
  expect_true(file.exists(file.path(path, "postgres", "app.R")))
  expect_true(file.exists(file.path(path, "postgres", "patches", "validator-audience.patch")))
  writeLines("# my edited app", file.path(path, "postgres", "app.R"))
  oauth_db_demo(action = "files", path = path)
  expect_identical(readLines(file.path(path, "postgres", "app.R")), "# my edited app")
  for (backend in c("postgres", "postgrest", "trino", "starrocks",
    "duckdb", "libsql", "cratedb", "opensearch")) {
    expect_true(file.exists(file.path(path, paste0("compose.", backend, ".yml"))))
    expect_true(file.exists(file.path(path, backend, "app.R")))
  }
})

test_that("demo commands isolate the project and clean up after a failed start", {
  path <- file.path(withr::local_tempdir(), "demo with spaces")
  calls <- list()
  local_mocked_bindings(
    .odb_demo_docker = function() "docker",
    .odb_demo_command = function(docker, args, check = TRUE) {
      calls[[length(calls) + 1L]] <<- list(args = args, check = check)
      if ("up" %in% args) return(1L)
      0L
    }
  )
  expect_error(suppressMessages(oauth_db_demo("trino", path = path,
    launch_browser = FALSE, build = FALSE)), "could not start the demo")
  expect_true("--no-build" %in% calls[[2L]]$args)
  expect_true(normalizePath(path, winslash = "/") %in% calls[[2L]]$args)
  expect_identical(tail(calls[[3L]]$args, 3L), c("logs", "--tail", "50"))
  expect_false(calls[[3L]]$check)
  expect_identical(tail(calls[[4L]]$args, 3L), c("down", "--volumes", "--remove-orphans"))
  project <- function(call) call$args[[match("--project-name", call$args) + 1L]]
  expect_identical(project(calls[[1L]]), project(calls[[4L]]))
  expect_match(project(calls[[1L]]), "^shinyoauthdb-demo-trino-")
  suppressMessages(oauth_db_demo("trino", path = path, action = "stop"))
  expect_identical(tail(calls[[5L]]$args, 3L), c("down", "--volumes", "--remove-orphans"))
})

test_that("the demo refuses unrelated directories and invalid requests", {
  path <- withr::local_tempdir()
  writeLines("keep", file.path(path, "my-file.txt"))
  expect_error(oauth_db_demo(action = "files", path = path), "must be empty")
  expect_identical(readLines(file.path(path, "my-file.txt")), "keep")
  expect_error(oauth_db_demo(action = "stop", path = path), "No demo configuration")
  expect_error(oauth_db_demo("snowflake"), "arg")
  expect_error(oauth_db_demo(build = NA), "TRUE or FALSE")
})
