test_that("cloud drafts are offline, editable and contain only non-secret settings", {
  path <- cloud_demo_path()
  withr::local_envvar(c(
    OAUTHDB_DATABRICKS_CLIENT_SECRET = "secret-not-for-files"
  ))
  local_mocked_bindings(
    .odb_cloud_check_workspace = function(...) stop("No network"),
    .odb_cloud_run = function(...) stop("No app")
  )
  expect_identical(
    oauth_db_cloud_demo(
      host = "https://Workspace.example/sql/warehouses?o=123#query",
      client_id = "custom-client",
      action = "files",
      prompt = FALSE,
      path = path
    ),
    normalizePath(path, winslash = "/")
  )
  config <- .odb_cloud_load(path)
  expect_identical(config$host, "workspace.example")
  expect_identical(config$client_id, "custom-client")
  files <- list.files(path, full.names = TRUE, all.files = TRUE, no.. = TRUE)
  expect_false(any(grepl(
    "secret-not-for-files",
    unlist(lapply(files, readLines)),
    fixed = TRUE
  )))
  writeLines("# my edits", file.path(path, "app.R"))
  oauth_db_cloud_demo(action = "files", path = path, prompt = FALSE)
  expect_identical(readLines(file.path(path, "app.R")), "# my edits")
  draft <- cloud_demo_path()
  oauth_db_cloud_demo(action = "files", path = draft, prompt = FALSE)
  expect_identical(.odb_cloud_load(draft)$port, "8100")
})

test_that("cloud input rejects account URLs, embedded credentials and unrelated files", {
  expect_identical(
    .odb_cloud_host("DBA.example/a?token=never-echo#x"),
    "dba.example"
  )
  for (value in c(
    "http://workspace.example",
    "https://user:secret@workspace.example",
    "https://workspace.example:1234"
  )) {
    error <- expect_error(.odb_cloud_host(value))
    expect_false(grepl("secret", conditionMessage(error), fixed = TRUE))
  }
  expect_error(
    .odb_cloud_host("https://accounts.cloud.databricks.com"),
    "account-console"
  )
  path <- cloud_demo_path()
  dir.create(path, recursive = TRUE)
  writeLines("keep", file.path(path, "unrelated.txt"))
  expect_error(
    oauth_db_cloud_demo(path = path, action = "files", prompt = FALSE),
    "must be empty"
  )
  expect_identical(readLines(file.path(path, "unrelated.txt")), "keep")
  expect_error(
    oauth_db_cloud_demo(port = 80, action = "files", prompt = FALSE),
    "1024"
  )
  expect_error(
    oauth_db_cloud_demo(
      warehouse_id = "id",
      http_path = "/sql/1.0/warehouses/id",
      action = "files",
      prompt = FALSE
    ),
    "only one"
  )
  expect_error(
    oauth_db_cloud_demo(action = "files", prompt = NA),
    "TRUE or FALSE"
  )
})

test_that("Free Edition stops before secrets, network calls or local launch", {
  local_mocked_bindings(
    .odb_cloud_check_workspace = function(...) stop("No network"),
    .odb_cloud_secret = function(...) stop("No secret"),
    .odb_cloud_run = function(...) stop("No launch")
  )
  expect_error(
    oauth_db_cloud_demo(
      edition = "free",
      path = cloud_demo_path(),
      prompt = FALSE
    ),
    class = "shinyOAuthDB_cloud_demo_unsupported_edition"
  )
  expect_error(
    oauth_db_cloud_demo(
      host = "workspace.example",
      path = cloud_demo_path(),
      prompt = FALSE
    ),
    "client_id"
  )
})

test_that("the cloud guide can show help, go back, pause and resume", {
  path <- cloud_demo_path()
  answers <- c(
    "?",
    "1",
    "?",
    "https://workspace.example/page?o=1",
    "back",
    "new.example",
    "",
    ""
  )
  local_mocked_bindings(
    .odb_cloud_interactive = function() TRUE,
    .odb_cloud_port_available = function(...) NULL,
    .odb_cloud_read = function(label) {
      result <- answers[[1L]]
      answers <<- answers[-1L]
      result
    },
    .odb_cloud_check_workspace = function(...) stop("Should pause")
  )
  expect_identical(
    oauth_db_cloud_demo(path = path, prompt = TRUE),
    normalizePath(path, winslash = "/")
  )
  expect_identical(.odb_cloud_load(path)$host, "new.example")
  answers <- c("cancel")
  oauth_db_cloud_demo(path = path, client_id = "given-client", prompt = TRUE)
  expect_identical(.odb_cloud_load(path)$client_id, "given-client")
  expect_null(.odb_cloud_load(path)$client_type)
})

test_that("public and confidential starts keep credentials out of project files", {
  paths <- list()
  calls <- list()
  local_mocked_bindings(
    .odb_cloud_port_available = function(port) NULL,
    .odb_cloud_check_workspace = function(config) NULL,
    .odb_cloud_run = function(path, port, launch_browser, secret) {
      calls[[length(calls) + 1L]] <<- list(secret = secret)
      paths[[length(paths) + 1L]] <<- path
    }
  )
  withr::local_envvar(c(
    OAUTHDB_DATABRICKS_CLIENT_SECRET = "confidential-sentinel"
  ))
  public <- cloud_demo_path()
  oauth_db_cloud_demo(
    host = "workspace.example",
    client_id = "public-id",
    path = public,
    prompt = FALSE
  )
  expect_null(calls[[1L]]$secret)
  private <- cloud_demo_path()
  oauth_db_cloud_demo(
    host = "workspace.example",
    client_id = "private-id",
    client_type = "confidential",
    http_path = "/sql/1.0/warehouses/demo-id",
    path = private,
    prompt = FALSE
  )
  expect_identical(calls[[2L]]$secret, "confidential-sentinel")
  expect_identical(.odb_cloud_load(private)$warehouse_id, "demo-id")
  for (path in paths) {
    expect_false(any(grepl(
      "confidential-sentinel",
      unlist(lapply(
        list.files(path, full.names = TRUE, all.files = TRUE, no.. = TRUE),
        readLines
      )),
      fixed = TRUE
    )))
  }
})

test_that("masked secrets and process launch don't print or serialize the credential", {
  withr::local_envvar(c(OAUTHDB_DATABRICKS_CLIENT_SECRET = NA_character_))
  local_mocked_bindings(
    askpass = function(...) "masked-sentinel",
    .package = "askpass"
  )
  expect_identical(.odb_cloud_secret(TRUE), "masked-sentinel")
  expect_error(.odb_cloud_secret(FALSE), "OAUTHDB_DATABRICKS_CLIENT_SECRET")
  before <- Sys.getenv(
    "OAUTHDB_DATABRICKS_CLIENT_SECRET",
    unset = NA_character_
  )
  local_mocked_bindings(
    run = function(command, args, env, ...) {
      expect_identical(unname(env[[1L]]), "current")
      expect_false(any(grepl(
        "masked-sentinel",
        c(command, args),
        fixed = TRUE
      )))
      expect_identical(
        unname(env[["OAUTHDB_DATABRICKS_CLIENT_SECRET"]]),
        "masked-sentinel"
      )
      list(status = 0L)
    },
    .package = "processx"
  )
  .odb_cloud_run(
    normalizePath(tempdir(), winslash = "/"),
    8100L,
    FALSE,
    "masked-sentinel"
  )
  expect_identical(
    Sys.getenv("OAUTHDB_DATABRICKS_CLIENT_SECRET", unset = NA_character_),
    before
  )
})

test_that("Back to setup preserves edits and registration for the settings editor", {
  path <- cloud_demo_path()
  local_mocked_bindings(
    .odb_cloud_port_available = function(...) NULL,
    .odb_cloud_check_workspace = function(...) NULL,
    .odb_cloud_run = function(...) 10L
  )
  oauth_db_cloud_demo(
    host = "workspace.example",
    client_id = "old-client",
    path = path,
    action = "files",
    prompt = FALSE
  )
  writeLines("# edited app", file.path(path, "app.R"))
  oauth_db_cloud_demo(path = path, prompt = FALSE)
  expect_identical(.odb_cloud_load(path)$client_id, "old-client")
  expect_identical(.odb_cloud_load(path)$client_type, "public")
  expect_true(file.exists(.odb_cloud_edit_marker(path)))
  expect_identical(readLines(file.path(path, "app.R")), "# edited app")
})
