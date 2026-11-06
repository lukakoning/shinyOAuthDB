# Real browser/Keycloak login; Databricks warehouse and SQL calls are mocked.
# Rscript --vanilla tools/check-cloud-demo.R [additional-library-paths]
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) .libPaths(c(arguments, .libPaths()))

check_cloud_demo <- function() {
  dir.create(".validation/cloud-demo", recursive = TRUE, showWarnings = FALSE)
  output <- normalizePath(".validation/cloud-demo", winslash = "/")
  library <- tempfile("cloud-demo-library-")
  dir.create(library)
  pkgbuild::rcmd_build_tools("INSTALL", c(paste0("--library=", library), "."))
  libpath <- c(library, .libPaths())
  fixture <- tempfile("cloud OAuth fixture-")
  path <- tempfile("cloud app with spaces-")
  project <- paste0("shinyoauthdb-cloud-check-", Sys.getpid())
  callr::r(function(fixture, path) {
    shinyOAuthDB::oauth_db_demo(action = "files", path = fixture)
    shinyOAuthDB::oauth_db_cloud_demo(host = "workspace.example", client_id = "shiny-db",
      client_type = "confidential", edition = "workspace", port = 18100L,
      action = "files", path = path, prompt = FALSE)
  }, args = list(fixture, path), libpath = libpath)
  fixture <- normalizePath(fixture, winslash = "/")
  path <- normalizePath(path, winslash = "/")
  realm <- jsonlite::read_json(file.path(fixture, "realm.json"), simplifyVector = FALSE)
  realm$clientScopes <- c(realm$clientScopes, list(list(name = "sql", protocol = "openid-connect",
    attributes = list(`include.in.token.scope` = "true", `display.on.consent.screen` = "true"))))
  for (index in seq_along(realm$clients)) if (realm$clients[[index]]$clientId == "shiny-db") {
    realm$clients[[index]]$optionalClientScopes <- c(realm$clients[[index]]$optionalClientScopes, "sql")
  }
  jsonlite::write_json(realm, file.path(fixture, "realm.json"), auto_unbox = TRUE, pretty = TRUE)
  compose <- c("compose", "--project-name", project, "--project-directory", fixture,
    "-f", file.path(fixture, "compose.yml"), "-f", file.path(fixture, "compose.local.yml"))
  docker <- function(args) {
    status <- system2(Sys.which("docker"), vapply(c(compose, args), shQuote, ""))
    if (status != 0L) stop("Docker fixture command failed")
  }
  process <- chrome <- NULL
  on.exit({
    if (file.exists(file.path(path, "events.txt"))) file.copy(file.path(path, "events.txt"), file.path(output, "events.txt"), overwrite = TRUE)
    if (!is.null(chrome)) chrome$close()
    if (!is.null(process) && process$is_alive()) process$kill_tree()
    try(docker(c("down", "--volumes", "--remove-orphans")), silent = TRUE)
  }, add = TRUE)
  docker(c("up", "--detach", "--build", "--wait", "keycloak"))
  dir.create(file.path(fixture, "tls"))
  ca <- file.path(fixture, "tls", "ca-cert.pem")
  docker(c("cp", "tls:/fixtures/tls/ca-cert.pem", ca))

  prefix <- c(
    'library(shinyOAuthDB)',
    'library(DBI)',
    'fixture_log <- function(text) cat(text, "\\n", sep = "", file = "events.txt", append = TRUE)',
    'fixture_user <- function(token) {',
    '  body <- strsplit(token, ".", fixed = TRUE)[[1L]][[2L]]',
    '  body <- chartr("-_", "+/", body)',
    '  body <- paste0(body, strrep("=", (-nchar(body)) %% 4L))',
    '  jsonlite::fromJSON(rawToChar(openssl::base64_decode(body)))$preferred_username',
    '}',
    'oauth_db_databricks_client <- function(host, client_id, client_secret, redirect_uri, ...) {',
    '  shinyOAuth::oauth_client(shinyOAuth::oauth_provider_oidc_discover("https://localhost:18443/realms/shinyoauthdb"),',
    '    client_id = client_id, client_secret = client_secret, redirect_uri = redirect_uri,',
    '    scopes = c("openid", "profile", "sql"))',
    '}',
    'oauth_db_databricks_api <- function(authorization, ...) {',
    '  token <- oauth_db_token(authorization, required_scopes = "sql")',
    '  list(warehouses = function() {',
    '    fixture_log(paste("list", fixture_user(token())))',
    '    data.frame(id = "demo-warehouse", name = "Demo warehouse", state = "RUNNING")',
    '  })',
    '}',
    'if (!methods::isClass("CloudDemoFixtureConnection")) {',
    '  methods::setClass("CloudDemoFixtureConnection", contains = "DBIConnection", slots = c(user = "character"))',
    '}',
    'methods::setMethod("dbIsValid", "CloudDemoFixtureConnection", function(dbObj, ...) TRUE)',
    'methods::setMethod("dbDisconnect", "CloudDemoFixtureConnection", function(conn, ...) { fixture_log(paste("disconnect", conn@user)); TRUE })',
    'methods::setMethod("dbGetQuery", c("CloudDemoFixtureConnection", "character"), function(conn, statement, ...) {',
    '  fixture_log(paste("query", conn@user))',
    '  stopifnot(identical(statement, "SELECT current_user() AS signed_in_user"))',
    '  data.frame(signed_in_user = conn@user)',
    '})',
    'oauth_db_databricks <- function(authorization, ...) {',
    '  oauth_db_connect(authorization, required_scopes = "sql", connect = function(token) {',
    '    user <- fixture_user(token)',
    '    fixture_log(paste("connect", user))',
    '    methods::new("CloudDemoFixtureConnection", user = user)',
    '  })',
    '}'
  )
  appfile <- file.path(path, "app.R")
  writeLines(c(prefix, readLines(appfile)), appfile)
  process <- callr::r_bg(function(path, ca) {
    Sys.setenv(CURL_SSL_BACKEND = "openssl", CURL_CA_BUNDLE = ca,
      OAUTHDB_DATABRICKS_CLIENT_SECRET = "demo-client-secret")
    testthat::local_mocked_bindings(.odb_cloud_check_workspace = function(config) NULL,
      .package = "shinyOAuthDB")
    setwd(tempdir())
    shinyOAuthDB::oauth_db_cloud_demo(path = path, prompt = FALSE, launch_browser = FALSE)
  }, args = list(path, ca), libpath = libpath, supervise = TRUE,
    stdout = file.path(output, "app.log"), stderr = file.path(output, "app-error.log"))
  deadline <- Sys.time() + 40
  while (!isTRUE(tryCatch(curl::curl_fetch_memory("http://localhost:18100")$status_code == 200L,
    error = function(error) FALSE))) {
    if (!process$is_alive() || Sys.time() > deadline) stop("Cloud app startup failed; see .validation/cloud-demo logs")
    Sys.sleep(0.1)
  }
  chrome <- chromote::Chromote$new()
  value <- function(browser, js) browser$Runtime$evaluate(js, returnByValue = TRUE)$result$value
  wait <- function(browser, js) {
    deadline <- Sys.time() + 40
    repeat {
      if (isTRUE(tryCatch(value(browser, js), error = function(error) FALSE))) return(invisible(NULL))
      if (Sys.time() > deadline) stop("Browser timeout: ", js, "; ", value(browser, "document.body.innerText.slice(0, 1200)"))
      Sys.sleep(0.1)
    }
  }
  events <- function() if (file.exists(file.path(path, "events.txt"))) readLines(file.path(path, "events.txt")) else character()
  for (user in c("alice", "bob")) {
    cat("Checking cloud app as", user, "\n")
    context <- chrome$Target$createBrowserContext()$browserContextId
    target <- chrome$Target$createTarget("about:blank", browserContextId = context)$targetId
    browser <- chromote::ChromoteSession$new(parent = chrome, targetId = target)
    browser$Security$setIgnoreCertificateErrors(ignore = TRUE)
    browser$go_to("http://localhost:18100")
    wait(browser, "Boolean(window.Shiny && Shiny.shinyapp?.isConnected() && document.querySelector('#login:not(:disabled)'))")
    stopifnot(identical(trimws(value(browser, "document.querySelector('#rows').textContent")), ""))
    value(browser, "document.querySelector('#login').click()")
    wait(browser, "Boolean(document.querySelector('#username') && document.querySelector('#kc-login'))")
    value(browser, sprintf("document.querySelector('#username').value='%s'; document.querySelector('#password').value='%s-fixture-password'; document.querySelector('#kc-login').click()", user, user))
    wait(browser, "Boolean(document.querySelector('#warehouse')?.selectize?.options['demo-warehouse'])")
    stopifnot(!any(grepl(paste0("^(query|connect) ", user, "$"), events())))
    value(browser, "document.querySelector('#warehouse').selectize.setValue('demo-warehouse')")
    value(browser, "document.querySelector('#run').click()")
    wait(browser, sprintf("document.querySelector('#rows').textContent.includes('%s')", user))
    stopifnot(sum(events() == paste("query", user)) == 1L)
    value(browser, "document.querySelector('#refresh').click()")
    wait(browser, "document.querySelector('#query_status').textContent.includes('Query completed')")
    stopifnot(sum(events() == paste("query", user)) == 1L)
    value(browser, "document.querySelector('#logout').click()")
    wait(browser, "document.querySelector('#rows').textContent.trim() === ''")
    stopifnot(any(events() == paste("disconnect", user)))
    if (user == "bob") {
      value(browser, "document.querySelector('#stop').click()")
      process$wait(30000)
      stopifnot(!process$is_alive())
    }
    browser$close()
    chrome$Target$disposeBrowserContext(context)
    cat(user, ": browser sign-in, no implicit SQL, explicit query, sign-out clears results and closes the connection\n")
  }
  process$wait(30000)
  stopifnot(!process$is_alive(), process$get_exit_status() == 0L)
  process$get_result()
  project_text <- unlist(lapply(list.files(path, full.names = TRUE, all.files = TRUE, no.. = TRUE), readLines))
  stopifnot(!any(grepl("demo-client-secret", project_text, fixed = TRUE)))
  jsonlite::write_json(list(real_browser_oauth = TRUE, databricks_calls = "mocked",
    implicit_sql = FALSE, account_isolation = TRUE, connection_cleanup = TRUE,
    credentials_in_project = FALSE, stopped = TRUE), file.path(output, "result.json"), pretty = TRUE, auto_unbox = TRUE)
  cat("Cloud demo browser fixture passed. No live Databricks workspace was used.\n")
}

check_cloud_demo()
