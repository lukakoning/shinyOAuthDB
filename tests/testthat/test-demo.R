test_that("demo files ship with the package and can be edited without Docker", {
  path <- file.path(withr::local_tempdir(), "demo with spaces")
  local_mocked_bindings(.odb_demo_docker = function() {
    stop("Docker must not be used")
  })
  expect_identical(
    oauth_db_demo(action = "files", path = path),
    normalizePath(path, winslash = "/")
  )
  expect_true(file.exists(file.path(path, "postgres", "app.R")))
  expect_true(file.exists(file.path(
    path,
    "postgres",
    "patches",
    "validator-audience.patch"
  )))
  writeLines("# my edited app", file.path(path, "postgres", "app.R"))
  oauth_db_demo(action = "files", path = path)
  expect_identical(
    readLines(file.path(path, "postgres", "app.R")),
    "# my edited app"
  )
  for (backend in c(
    "postgres",
    "postgrest",
    "trino",
    "starrocks",
    "duckdb",
    "libsql",
    "cratedb",
    "opensearch"
  )) {
    expect_true(file.exists(file.path(
      path,
      paste0("compose.", backend, ".yml")
    )))
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
      if ("up" %in% args) {
        return(1L)
      }
      0L
    }
  )
  expect_error(
    suppressMessages(oauth_db_demo(
      "trino",
      path = path,
      launch_browser = FALSE,
      build = FALSE
    )),
    "could not start the demo"
  )
  expect_true("--no-build" %in% calls[[2L]]$args)
  expect_true(normalizePath(path, winslash = "/") %in% calls[[2L]]$args)
  expect_identical(tail(calls[[3L]]$args, 3L), c("logs", "--tail", "50"))
  expect_false(calls[[3L]]$check)
  expect_identical(
    tail(calls[[4L]]$args, 3L),
    c("down", "--volumes", "--remove-orphans")
  )
  project <- function(call) call$args[[match("--project-name", call$args) + 1L]]
  expect_identical(project(calls[[1L]]), project(calls[[4L]]))
  expect_match(project(calls[[1L]]), "^shinyoauthdb-demo-trino-")
  suppressMessages(oauth_db_demo("trino", path = path, action = "stop"))
  expect_identical(
    tail(calls[[5L]]$args, 3L),
    c("down", "--volumes", "--remove-orphans")
  )
})

test_that("the demo refuses unrelated directories and invalid requests", {
  path <- withr::local_tempdir()
  writeLines("keep", file.path(path, "my-file.txt"))
  expect_error(oauth_db_demo(action = "files", path = path), "must be empty")
  expect_identical(readLines(file.path(path, "my-file.txt")), "keep")
  expect_error(
    oauth_db_demo(action = "stop", path = path),
    "No demo configuration"
  )
  expect_error(oauth_db_demo("snowflake"), "arg")
  expect_error(oauth_db_demo(build = NA), "TRUE or FALSE")
  expect_error(oauth_db_demo(app = "unknown"), "arg")
})

test_that("local app files use host endpoints and preserve edits", {
  path <- file.path(withr::local_tempdir(), "local app with spaces")
  local_mocked_bindings(.odb_demo_docker = function() {
    stop("Docker must not be used")
  })
  for (backend in c(
    "postgres",
    "postgrest",
    "trino",
    "starrocks",
    "duckdb",
    "libsql",
    "cratedb",
    "opensearch"
  )) {
    oauth_db_demo(backend, app = "local", action = "files", path = path)
    app <- file.path(path, "local-app", backend, "app.R")
    code <- paste(readLines(app), collapse = "\n")
    expect_silent(parse(app))
    expect_match(code, "19444", fixed = TRUE)
    expect_match(
      code,
      file.path(normalizePath(path, winslash = "/"), "tls", "ca-cert.pem"),
      fixed = TRUE
    )
    expect_false(grepl("/fixtures/tls", code, fixed = TRUE))
    expect_true(file.exists(file.path(path, backend, "compose.local.yml")))
    writeLines("# my edited local app", app)
    oauth_db_demo(backend, app = "local", action = "files", path = path)
    expect_identical(readLines(app), "# my edited local app")
  }
  expect_match(
    paste(
      readLines(file.path(path, "local-app", "trino", "prepare.R")),
      collapse = "\n"
    ),
    "19444L",
    fixed = TRUE
  )
  expect_false(grepl(
    "/fixtures/tls",
    paste(
      readLines(file.path(path, "local-app", "starrocks", "prepare.R")),
      collapse = "\n"
    )
  ))
  expect_error(
    oauth_db_demo(
      "postgrest",
      app = "local",
      action = "files",
      path = path,
      launch_browser = NA
    ),
    "TRUE or FALSE"
  )
})

test_that("local mode starts infrastructure, copies the CA and cleans up R failures", {
  path <- file.path(withr::local_tempdir(), "local demo with spaces")
  calls <- list()
  local_mocked_bindings(
    .odb_demo_docker = function() "docker",
    .odb_demo_local_require = function(database) {
      expect_identical(database, "postgrest")
    },
    .odb_demo_command = function(docker, args, check = TRUE) {
      calls[[length(calls) + 1L]] <<- args
      if ("cp" %in% args) {
        writeLines("public certificate", tail(args, 1L))
      }
      0L
    },
    .odb_demo_local_run = function(path, database, launch_browser) {
      expect_false(launch_browser)
      expect_identical(
        readLines(file.path(path, "tls", "ca-cert.pem")),
        "public certificate"
      )
      stop("local app failed")
    }
  )
  expect_error(
    suppressMessages(oauth_db_demo(
      "postgrest",
      app = "local",
      path = path,
      launch_browser = FALSE
    )),
    "local app failed"
  )
  expect_identical(tail(calls[[2L]], 1L), "local")
  expect_true(
    file.path(normalizePath(path, winslash = "/"), "compose.local.yml") %in%
      calls[[2L]]
  )
  expect_false("app" %in% calls[[2L]])
  expect_identical(
    tail(calls[[4L]], 3L),
    c("down", "--volumes", "--remove-orphans")
  )
  expect_false(any(vapply(
    calls,
    function(args) "--follow" %in% args,
    logical(1)
  )))
})

test_that("unsupported local PostgreSQL is explained before starting Docker", {
  path <- withr::local_tempdir()
  local_mocked_bindings(
    .odb_require = function(...) NULL,
    .odb_postgres_runtime = function() stop("native runtime unavailable"),
    .odb_demo_docker = function() stop("Docker must not be used")
  )
  expect_error(
    oauth_db_demo("postgres", app = "local", path = path),
    "oauth_db_demo\\('postgrest', app = 'local'\\)"
  )
})

test_that("local app settings stay in the child R process", {
  previous <- Sys.getenv(
    c("CURL_CA_BUNDLE", "CURL_SSL_BACKEND"),
    unset = NA_character_
  )
  allowed <- getOption("shinyOAuth.allowed_hosts")
  path <- normalizePath(withr::local_tempdir(), winslash = "/")
  local_mocked_bindings(
    r = function(
      func,
      args,
      libpath,
      user_profile,
      show,
      spinner,
      supervise,
      cleanup_tree,
      windows_hide_window
    ) {
      expect_identical(
        args[1:3],
        list(file.path(path, "local-app", "postgrest"), "postgrest", FALSE)
      )
      expect_identical(
        unname(args[[4L]][["CURL_CA_BUNDLE"]]),
        file.path(path, "tls", "ca-cert.pem")
      )
      expect_identical(libpath, .libPaths())
      if (.Platform$OS.type == "windows") {
        expect_identical(unname(args[[4L]][["CURL_SSL_BACKEND"]]), "openssl")
      }
      expect_false(user_profile)
      expect_true(show)
      expect_true(supervise)
      expect_true(cleanup_tree)
      expect_true(windows_hide_window)
    },
    .package = "callr"
  )
  suppressMessages(.odb_demo_local_run(path, "postgrest", FALSE))
  expect_identical(Sys.getenv(names(previous), unset = NA_character_), previous)
  expect_identical(getOption("shinyOAuth.allowed_hosts"), allowed)
})

test_that("local StarRocks files retain explicit driver and plugin paths", {
  path <- file.path(withr::local_tempdir(), "custom ODBC demo")
  withr::local_envvar(c(
    OAUTHDB_DEMO_ODBC_DRIVER = "C:/drivers with spaces/myodbc9w.dll",
    OAUTHDB_DEMO_ODBC_PLUGINS = "C:/drivers with spaces/plugin"
  ))
  oauth_db_demo("starrocks", app = "local", action = "files", path = path)
  code <- paste(
    readLines(file.path(path, "local-app", "starrocks", "app.R")),
    collapse = "\n"
  )
  expect_match(
    code,
    'driver = "C:/drivers with spaces/myodbc9w.dll"',
    fixed = TRUE
  )
  expect_match(
    code,
    'plugin_dir = "C:/drivers with spaces/plugin"',
    fixed = TRUE
  )
})
