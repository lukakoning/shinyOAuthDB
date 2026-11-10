test_that("default cloud drafts resume and preserve edits separately for every platform", {
  cache <- withr::local_tempdir()
  local_mocked_bindings(
    .odb_user_cache = function() file.path(cache, "shinyOAuthDB", "cache")
  )
  local_mocked_bindings(
    .odb_cloud_run = function(...) stop("No launch"),
    .odb_cloud_secret = function(...) stop("No secret")
  )
  paths <- character()
  for (platform in c("databricks", names(cloud_platform_settings()))) {
    path <- oauth_db_cloud_demo(platform, action = "files", prompt = FALSE)
    paths <- c(paths, path)
    expect_true(startsWith(path, normalizePath(cache, winslash = "/")))
    writeLines("# keep my app", file.path(path, "app.R"))
    again <- oauth_db_cloud_demo(
      platform,
      action = "files",
      prompt = FALSE,
      client_id = "saved-client"
    )
    expect_identical(again, path)
    expect_identical(readLines(file.path(path, "app.R")), "# keep my app")
    expect_identical(.odb_cloud_load(path)$client_id, "saved-client")
  }
  expect_length(unique(paths), 8L)
})

test_that("returning from an app edits only the chosen setting and can pause safely", {
  path <- cloud_demo_path()
  settings <- cloud_platform_settings()$fabric
  do.call(
    oauth_db_cloud_demo,
    c(list("fabric", path = path, action = "files", prompt = FALSE), settings)
  )
  writeLines("# edited UI", file.path(path, "app.R"))
  local_mocked_bindings(
    .odb_cloud_port_available = function(...) NULL,
    .odb_cloud_platform_require = function(...) NULL,
    .odb_cloud_run = function(...) 10L
  )
  oauth_db_cloud_demo("fabric", path = path, prompt = FALSE)
  answers <- c(
    as.character(match("port", names(.odb_cloud_edit_fields("fabric")))),
    "80",
    as.character(match("port", names(.odb_cloud_edit_fields("fabric")))),
    "8200",
    "cancel"
  )
  local_mocked_bindings(
    .odb_cloud_interactive = function() TRUE,
    .odb_cloud_run = function(...) stop("Paused, do not launch"),
    .odb_cloud_read = function(...) {
      value <- answers[[1L]]
      answers <<- answers[-1L]
      value
    }
  )
  oauth_db_cloud_demo("fabric", path = path, prompt = TRUE)
  saved <- .odb_cloud_load(path)
  expect_identical(saved$port, "8200")
  expect_identical(saved$client_id, settings$client_id)
  expect_identical(saved$client_type, settings$client_type)
  expect_identical(readLines(file.path(path, "app.R")), "# edited UI")
  expect_true(file.exists(.odb_cloud_edit_marker(path)))
  answers <- "0"
  launched <- FALSE
  local_mocked_bindings(.odb_cloud_run = function(path, port, ...) {
    expect_identical(port, 8200L)
    launched <<- TRUE
    0L
  })
  oauth_db_cloud_demo("fabric", path = path, prompt = TRUE)
  expect_true(launched)
  expect_false(file.exists(.odb_cloud_edit_marker(path)))
  expect_length(answers, 0L)
})

test_that("changing an OAuth issuer clears registration while changing data settings keeps it", {
  for (platform in c("databricks", "fabric", "bigquery", "snowflake")) {
    config <- if (platform == "databricks") {
      list(
        host = "workspace.example",
        client_id = "registered-client",
        client_type = "public",
        port = "8100",
        warehouse_id = "old-warehouse"
      )
    } else {
      cloud_platform_settings()[[platform]]
    }
    field <- switch(
      platform,
      databricks = "host",
      fabric = "tenant_id",
      bigquery = "project",
      snowflake = "role"
    )
    value <- switch(
      platform,
      databricks = "new-workspace.example",
      fabric = "99999999-2222-3333-4444-555555555555",
      bigquery = "new-project",
      snowflake = "ANOTHER_READER"
    )
    answers <- c(
      as.character(match(field, names(.odb_cloud_edit_fields(platform)))),
      value,
      "0"
    )
    local_mocked_bindings(.odb_cloud_read = function(...) {
      value <- answers[[1L]]
      answers <<- answers[-1L]
      value
    })
    path <- cloud_demo_path()
    dir.create(path, recursive = TRUE)
    result <- .odb_cloud_edit_setup(config, path, platform)
    expect_identical(result[[field]], value)
    if (platform %in% c("databricks", "fabric")) {
      expect_null(result$client_id)
    } else {
      expect_identical(result$client_id, config$client_id)
    }
    if (platform == "databricks") expect_null(result$warehouse_id)
  }
})

test_that("changing an API resource lets the guide ask for its matching scope", {
  config <- cloud_platform_settings()$redshift
  field <- match("resource", names(.odb_cloud_edit_fields("redshift")))
  answers <- c(as.character(field), "api://new-resource", "0")
  local_mocked_bindings(.odb_cloud_read = function(...) {
    value <- answers[[1L]]
    answers <<- answers[-1L]
    value
  })
  path <- cloud_demo_path()
  dir.create(path, recursive = TRUE)
  result <- .odb_cloud_edit_setup(config, path, "redshift")
  expect_identical(result$resource, "api://new-resource")
  expect_null(result$scope)
  expect_identical(result$client_id, config$client_id)
})

test_that("an unready cloud integration can be confirmed when resuming the guide", {
  for (platform in c("redshift", "clickhouse")) {
    settings <- cloud_platform_settings()[[platform]]
    readiness <- .odb_cloud_specs()[[platform]]$readiness
    settings[[readiness]] <- "no"
    path <- cloud_demo_path()
    do.call(
      oauth_db_cloud_demo,
      c(list(platform, path = path, action = "files", prompt = FALSE), settings)
    )
    answers <- "1"
    launched <- FALSE
    local_mocked_bindings(
      .odb_cloud_interactive = function() TRUE,
      .odb_cloud_port_available = function(...) NULL,
      .odb_cloud_platform_require = function(...) NULL,
      .odb_cloud_run = function(...) {
        launched <<- TRUE
        0L
      },
      .odb_cloud_read = function(...) {
        value <- answers[[1L]]
        answers <<- answers[-1L]
        value
      }
    )
    oauth_db_cloud_demo(platform, path = path, prompt = TRUE)
    expect_true(launched)
    expect_length(answers, 0L)
    expect_identical(.odb_cloud_load(path)[[readiness]], "yes")
  }
})
