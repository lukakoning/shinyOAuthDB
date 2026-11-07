test_that("cloud platform drafts are isolated, offline and preserve edits", {
  expect_setequal(names(cloud_platform_settings()), names(.odb_cloud_specs()))
  local_mocked_bindings(.odb_cloud_platform_require = function(...) stop("No dependencies"),
    .odb_cloud_secret = function(...) stop("No secret"), .odb_cloud_run = function(...) stop("No process"))
  for (platform in names(.odb_cloud_specs())) {
    path <- cloud_demo_path()
    oauth_db_cloud_demo(platform, action = "files", path = path, prompt = FALSE)
    expect_identical(readLines(file.path(path, ".shinyOAuthDB-cloud-demo")), platform)
    expect_true(all(file.exists(file.path(path, c("app.R", "demo-ui.R", "settings.dcf")))))
    writeLines("# my edits", file.path(path, "app.R"))
    oauth_db_cloud_demo(platform, action = "files", path = path, prompt = FALSE)
    expect_identical(readLines(file.path(path, "app.R")), "# my edits")
    expect_error(oauth_db_cloud_demo("databricks", action = "files", path = path, prompt = FALSE), "another platform")
    expect_error(oauth_db_cloud_demo(platform, prompt = FALSE, path = path), "Supply")
    expect_error(oauth_db_cloud_demo(platform, action = "files", path = cloud_demo_path(),
      prompt = FALSE, client_secret = "never-save-this"), "Unknown")
  }
})

test_that("the platform guide explains fields and can go back, pause and resume", {
  path <- cloud_demo_path()
  answers <- c("?", "not a hostname", "old.fabric.example", "back", "new.fabric.example", "")
  local_mocked_bindings(.odb_cloud_interactive = function() TRUE,
    .odb_cloud_port_available = function(...) NULL,
    .odb_cloud_read = function(label) { value <- answers[[1L]]; answers <<- answers[-1L]; value },
    .odb_cloud_platform_require = function(...) stop("Should pause"))
  oauth_db_cloud_demo("fabric", path = path, prompt = TRUE)
  expect_identical(.odb_cloud_load(path)$server, "new.fabric.example")
  expect_null(.odb_cloud_load(path)$client_id)
  answers <- c("Reporting", "11111111-2222-3333-4444-555555555555", "cancel")
  oauth_db_cloud_demo("fabric", path = path, prompt = TRUE)
  expect_identical(.odb_cloud_load(path)$database, "Reporting")
  expect_null(.odb_cloud_load(path)$client_id)
})

test_that("platform starts route secrets only through their own environment variable", {
  local_mocked_bindings(.odb_cloud_port_available = function(...) NULL,
    .odb_cloud_platform_require = function(...) NULL,
    .odb_cloud_run = function(path, port, launch_browser, secret, secret_env) {
      expect_identical(secret_env, "OAUTHDB_FABRIC_CLIENT_SECRET")
      expect_identical(secret, "fabric-sentinel")
      expect_false(any(grepl(secret, unlist(lapply(list.files(path, all.files = TRUE,
        no.. = TRUE, full.names = TRUE), readLines)), fixed = TRUE)))
      10L
    })
  withr::local_envvar(c(OAUTHDB_FABRIC_CLIENT_SECRET = "fabric-sentinel"))
  settings <- cloud_platform_settings()$fabric
  settings$client_type <- "confidential"
  path <- cloud_demo_path()
  do.call(oauth_db_cloud_demo, c(list(platform = "fabric", prompt = FALSE, path = path), settings))
  expect_null(.odb_cloud_load(path)$client_id)
  expect_null(.odb_cloud_load(path)$client_type)
  oauth_db_cloud_demo("fabric", path = path, action = "files", prompt = FALSE,
    client_id = "new-id", server = "other.fabric.example")
  expect_identical(.odb_cloud_load(path)$server, "other.fabric.example")
  expect_identical(.odb_cloud_load(path)$client_id, "new-id")
})

test_that("platform values reject connection strings and invalid tenant IDs", {
  for (value in c("host;PWD=secret", "user:secret@host.example", "http://host.example", "host.example:1433")) {
    error <- expect_error(.odb_cloud_value(value, "hostname"))
    expect_false(grepl("secret", conditionMessage(error), fixed = TRUE))
  }
  expect_error(.odb_cloud_value("common", "uuid"), "tenant")
  expect_error(.odb_cloud_value("db;password=hidden", "odbc"))
})

test_that("Fabric demo uses SQL delegated access and its configured native driver", {
  app <- cloud_platform_app("fabric")
  expect_named(app$client@token_targets, "sql")
  local_mocked_bindings(.odb_bind = capture_backend)
  binding <- app$make_access(function() NULL)
  expect_identical(binding$target, "sql")
  expect_identical(binding$args$server, cloud_platform_settings()$fabric$server)
  expect_identical(binding$args$database, "Reporting")
  expect_identical(binding$args$options$driver, "ODBC Driver 18 for SQL Server")
})

test_that("BigQuery demo requires a Web registration and limits query billing", {
  app <- cloud_platform_app("bigquery")
  expect_true("https://www.googleapis.com/auth/bigquery" %in% app$client@scopes)
  expect_error(oauth_db_cloud_demo("bigquery", client_type = "public", action = "files",
    path = cloud_demo_path(), prompt = FALSE), "confidential")
  expect_error(.odb_cloud_value("123456", "project"), "project ID")
  app$run_query(list(query = function(sql, maximum_bytes_billed) {
    expect_identical(sql, "SELECT SESSION_USER() AS signed_in_user")
    expect_identical(maximum_bytes_billed, "10000000")
    data.frame(user = "fixture")
  }))
})

test_that("Snowflake demo binds its OAuth role and warehouse to the SQL connection", {
  app <- cloud_platform_app("snowflake")
  expect_true("session:role:REPORTING_READER" %in% app$client@scopes)
  local_mocked_bindings(.odb_bind = capture_backend)
  binding <- app$make_access(function() NULL)
  expect_identical(binding$required_scopes, "session:role:REPORTING_READER")
  expect_identical(binding$args$role, "REPORTING_READER")
  expect_identical(binding$args$warehouse, "REPORTING_WH")
  expect_null(binding$args$database)
})

test_that("Azure SQL separates the database port from the Shiny callback", {
  app <- cloud_platform_app("azure-sql")
  expect_named(app$client@token_targets, "sql")
  expect_identical(.odb_cloud_value(1433L, "port"), "1433")
  local_mocked_bindings(.odb_bind = capture_backend)
  binding <- app$make_access(function() NULL)
  expect_identical(binding$target, "sql")
  expect_identical(binding$args$port, 1433L)
  expect_identical(binding$args$server, "example.database.windows.net")
})

test_that("Azure PostgreSQL preserves the mapped role, CA and PostgreSQL target", {
  app <- cloud_platform_app("azure-postgres")
  expect_named(app$client@token_targets, "postgres")
  local_mocked_bindings(.odb_bind = capture_backend)
  binding <- app$make_access(function() NULL)
  expect_identical(binding$target, "postgres")
  expect_identical(binding$args$user, "reporting-readers")
  expect_identical(binding$args$sslrootcert, "fixture-root-ca.pem")
  expect_identical(binding$args$port, 5432L)
  path <- tempfile()
  writeLines("fixture CA placeholder", path)
  on.exit(unlink(path), add = TRUE)
  expect_identical(.odb_cloud_value(path, "path"), normalizePath(path, winslash = "/"))
})

test_that("Redshift demo pauses before asking credentials when the integration isn't ready", {
  answers <- c("2")
  local_mocked_bindings(.odb_cloud_interactive = function() TRUE,
    .odb_cloud_port_available = function(...) NULL,
    .odb_cloud_read = function(...) { value <- answers[[1L]]; answers <<- answers[-1L]; value },
    .odb_cloud_platform_require = function(...) stop("No dependencies"),
    .odb_cloud_secret = function(...) stop("No secret"))
  path <- cloud_demo_path()
  oauth_db_cloud_demo("redshift", prompt = TRUE, path = path)
  expect_identical(.odb_cloud_load(path)$identity_center_ready, "no")
  expect_null(.odb_cloud_load(path)$client_id)
  expect_error(oauth_db_cloud_demo("redshift", prompt = FALSE, path = path), "Supply")
})

test_that("Redshift demo binds the accepted resource, delegated scope and EXT_JWT flow", {
  app <- cloud_platform_app("redshift")
  expect_named(app$client@token_targets, "redshift")
  expect_identical(app$client@token_targets$redshift$resource, "api://redshift-resource")
  local_mocked_bindings(.odb_bind = capture_backend)
  binding <- app$make_access(function() NULL)
  expect_identical(binding$target, "redshift")
  expect_identical(binding$args$token_type, "EXT_JWT")
  expect_identical(binding$required_scopes, "api://redshift-resource/access_as_user")
  expect_error(.odb_cloud_resource_scope(list(resource = "api://right", scope = "api://wrong/read")), "fully qualified")
})

for (cloud_platform in names(cloud_platform_settings())) local({
  platform <- cloud_platform
  test_that(paste(platform, "app constructs its real client and waits for an explicit query"), {
    app <- cloud_platform_app(platform)
    expect_identical(app$client@client_id, "demo-client")
    expect_identical(app$client@redirect_uri, "http://localhost:8100")
    control <- new.env(parent = emptyenv())
    control$connections <- list()
    control$queries <- 0L
    app$oauth_module_server <- function(...) {
      session <- shiny::getDefaultReactiveDomain()
      scopes <- if (length(app$query_scopes)) app$query_scopes else "demo.read"
      a <- odb_test_authorization(session, id = "A", target = app$query_target, scopes = scopes)
      b <- odb_test_authorization(session, id = "B", target = app$query_target, scopes = scopes)
      reference <- shiny::reactiveVal(NULL)
      control$choose <- function(id) {
        a$current(id == "A"); b$current(id == "B")
        reference(if (id == "A") a$connection else b$connection)
      }
      list(connection = reference, request_login = function() control$choose("A"),
        logout = function() { a$current(FALSE); b$current(FALSE); reference(NULL) })
    }
    app$make_access <- function(authorization) oauth_db_connect(authorization,
      target = app$query_target, connect = function(token) {
        con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
        attr(con, "user") <- sub("^fixture-", "", token)
        control$connections[[length(control$connections) + 1L]] <- con
        con
      })
    app$run_query <- function(access) {
      con <- access()
      control$queries <- control$queries + 1L
      if (isTRUE(control$fail)) stop("private raw service error")
      data.frame(signed_in_user = attr(con, "user"))
    }
    shiny::testServer(app$server, {
      session$flushReact()
      expect_length(control$connections, 0L)
      expect_error(output$rows, class = "shiny.silent.error")
      session$setInputs(login = 1L)
      expect_length(control$connections, 0L)
      expect_identical(control$queries, 0L)
      session$setInputs(run = 1L)
      expect_match(output$rows, ">[[:space:]]*A[[:space:]]*<")
      expect_identical(control$queries, 1L)
      control$choose("B")
      session$flushReact()
      expect_error(output$rows, class = "shiny.silent.error")
      expect_false(DBI::dbIsValid(control$connections[[1L]]))
      expect_identical(control$queries, 1L)
      session$setInputs(run = 2L)
      expect_match(output$rows, ">[[:space:]]*B[[:space:]]*<")
      control$fail <- TRUE
      session$setInputs(run = 3L)
      expect_error(output$rows, class = "shiny.silent.error")
      expect_false(grepl("private raw", output$query_status, fixed = TRUE))
      session$setInputs(logout = 1L)
      expect_error(output$rows, class = "shiny.silent.error")
      expect_false(DBI::dbIsValid(control$connections[[2L]]))
    })
  })
})
