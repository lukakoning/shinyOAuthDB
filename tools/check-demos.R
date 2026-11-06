# Run one installed-package demo with Docker and a real browser.
# Rscript --vanilla tools/check-demos.R postgres [docker|local] [additional-library-paths]
arguments <- commandArgs(trailingOnly = TRUE)
database <- if (length(arguments)) arguments[[1L]] else "postgres"
mode <- if (length(arguments) > 1L && arguments[[2L]] %in% c("docker", "local")) arguments[[2L]] else "docker"
libraries <- arguments[-seq_len(min(length(arguments), if (length(arguments) > 1L && arguments[[2L]] %in% c("docker", "local")) 2L else 1L))]
if (length(libraries)) .libPaths(c(libraries, .libPaths()))
stopifnot(database %in% c("postgres", "postgrest", "trino", "starrocks",
  "duckdb", "libsql", "cratedb", "opensearch"))
shared <- database %in% c("duckdb", "libsql", "cratedb")
permission_demo <- shared || database == "opensearch"

check_demo <- function() {
  output <- file.path(normalizePath(".validation", winslash = "/", mustWork = TRUE), "demos",
    paste0(database, if (mode == "local") "-local"))
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  library <- tempfile("demo-library-")
  dir.create(library)
  pkgbuild::rcmd_build_tools("INSTALL", c(paste0("--library=", library), "."))
  libpath <- c(library, .libPaths())
  path <- tempfile(paste0("demo with spaces-", database, "-"))
  if (mode == "local") {
    callr::r(function(database, path) {
      shinyOAuthDB::oauth_db_demo(database, app = "local", action = "files", path = path)
    }, args = list(database, path), libpath = libpath)
    local_app <- file.path(path, "local-app", database, "app.R")
    code <- readLines(local_app)
    code <- sub(paste0('h2("', database, ' demo")'), 'h2("Local R editable app")', code, fixed = TRUE)
    writeLines(code, local_app)
  }
  process <- callr::r_bg(function(database, path, mode) {
    # This process has an installed package and no repository working directory.
    setwd(tempdir())
    shinyOAuthDB::oauth_db_demo(database, path = path, app = mode, launch_browser = FALSE)
  }, args = list(database, path, mode), libpath = libpath, supervise = TRUE,
    stdout = file.path(output, "launcher.log"), stderr = file.path(output, "docker.log"))
  chrome <- NULL
  on.exit({
    if (!is.null(chrome)) chrome$close()
    if (process$is_alive()) {
      if (file.exists(file.path(path, ".shinyOAuthDB-demo"))) {
        normalized <- normalizePath(path, winslash = "/", mustWork = TRUE)
        project <- paste0("shinyoauthdb-demo-", database, "-",
          substr(openssl::sha256(charToRaw(normalized)), 1L, 8L))
        args <- c("compose", "--project-name", project, "--project-directory", normalized,
          "--file", file.path(normalized, "compose.yml"),
          "--file", file.path(normalized, paste0("compose.", database, ".yml")))
        if (mode == "local") args <- c(args,
          "--file", file.path(normalized, "compose.local.yml"),
          "--file", file.path(normalized, database, "compose.local.yml"))
        args <- c(args, "logs", "--no-color", "--tail", "100")
        try(system2(Sys.which("docker"), vapply(args, shQuote, ""),
          stdout = file.path(output, "services.log"), stderr = file.path(output, "services-error.log")), silent = TRUE)
      }
      try(callr::r(function(database, path) {
        shinyOAuthDB::oauth_db_demo(database, action = "stop", path = path)
      }, args = list(database, path), libpath = libpath), silent = TRUE)
      process$wait(10000)
      if (process$is_alive()) process$kill()
    }
  }, add = TRUE)
  # Allow a source build when the pinned DuckDB R client has no binary.
  deadline <- Sys.time() + if (database == "duckdb") 4200 else 1200
  repeat {
    ready <- tryCatch(curl::curl_fetch_memory("http://localhost:18100")$status_code == 200L,
      error = function(e) FALSE)
    if (ready) break
    if (!process$is_alive() || Sys.time() > deadline) {
      stop("Demo startup failed. See ", output, "/docker.log", call. = FALSE)
    }
    Sys.sleep(0.2)
  }
  if (mode == "local") {
    project <- paste0("shinyoauthdb-demo-", database, "-",
      substr(openssl::sha256(charToRaw(normalizePath(path, winslash = "/"))), 1L, 8L))
    containers <- system2(Sys.which("docker"), vapply(c("ps", "--quiet", "--filter",
      paste0("label=com.docker.compose.project=", project), "--filter", "label=com.docker.compose.service=app"), shQuote, ""), stdout = TRUE)
    stopifnot(!length(containers))
  }
  chrome <- chromote::Chromote$new()
  value <- function(browser, js) browser$Runtime$evaluate(js, returnByValue = TRUE)$result$value
  wait <- function(browser, js) {
    deadline <- Sys.time() + 40
    repeat {
      if (isTRUE(tryCatch(value(browser, js), error = function(e) FALSE))) return(invisible(TRUE))
      if (Sys.time() > deadline) {
        page <- value(browser, "({origin: location.origin, path: location.pathname, text: document.body.innerText.slice(0, 1200)})")
        stop("Demo browser check timed out: ", js, "; page: ",
          jsonlite::toJSON(page, auto_unbox = TRUE), call. = FALSE)
      }
      Sys.sleep(0.1)
    }
  }
  for (user in c("alice", "bob")) {
    context <- chrome$Target$createBrowserContext()$browserContextId
    target <- chrome$Target$createTarget("about:blank", browserContextId = context)$targetId
    browser <- chromote::ChromoteSession$new(parent = chrome, targetId = target)
    # Only the disposable test browser accepts the generated local certificate.
    browser$Security$setIgnoreCertificateErrors(ignore = TRUE)
    browser$go_to("http://localhost:18100")
    wait(browser, "Boolean(window.Shiny && Shiny.shinyapp && Shiny.shinyapp.isConnected() && document.querySelector('#login:not(:disabled)'))")
    if (mode == "local") wait(browser, sprintf("document.querySelector('h2')?.textContent === '%s'",
      if (user == "alice") "Local R editable app" else "Local R edited app"))
    stopifnot(identical(trimws(value(browser, "document.querySelector('#rows').textContent")), ""))
    if (permission_demo) stopifnot(identical(trimws(value(browser, "document.querySelector('#account').textContent")), ""))
    value(browser, "document.querySelector('#login').click()")
    wait(browser, "Boolean(document.querySelector('#username') && document.querySelector('#kc-login'))")
    value(browser, sprintf(paste0("document.querySelector('#username').value='%s';",
      "document.querySelector('#password').value='%s-fixture-password';",
      "document.querySelector('#kc-login').click()"), user, user))
    prefix <- if (shared) "shared" else user
    wait(browser, sprintf("Boolean(document.querySelector('#rows')?.textContent.includes('%s-visible-1'))", prefix))
    rows <- value(browser, "document.querySelector('#rows').textContent")
    other <- if (user == "alice") "bob" else "alice"
    stopifnot(grepl(paste0(prefix, "-visible-2"), rows), !grepl(paste0(other, "-visible"), rows))
    if (permission_demo) {
      stopifnot(grepl(paste("Signed in as", user), value(browser, "document.querySelector('#account').textContent"), fixed = TRUE))
      value(browser, "document.querySelector('#probe').click()")
      wait(browser, "document.querySelector('#permission').textContent === 'Write rejected by database'")
    }
    value(browser, "document.querySelector('#logout').click()")
    wait(browser, "Boolean(document.querySelector('#rows') && document.querySelector('#rows').textContent.trim() === '')")
    if (permission_demo) wait(browser, "document.querySelector('#account').textContent.trim() === '' && document.querySelector('#permission').textContent.trim() === ''")
    cat(user, ": sign-in, expected data policy, sign-out clears output",
      if (permission_demo) ", database rejects writes", "\n", sep = "")
    if (user == "bob") {
      value(browser, "document.querySelector('#stop').click()")
    }
    browser$close()
    chrome$Target$disposeBrowserContext(context)
    if (mode == "local" && user == "alice") {
      code <- sub("Local R editable app", "Local R edited app", readLines(local_app), fixed = TRUE)
      writeLines(code, local_app)
    }
  }
  process$wait(30000)
  if (process$is_alive()) stop("Stop demo did not finish cleanup.", call. = FALSE)
  stopifnot(identical(process$get_exit_status(), 0L))
  process$get_result()
  jsonlite::write_json(list(database = database, app = mode,
    local_edits = if (mode == "local") TRUE else NULL, accounts = c("alice", "bob"),
    installed_package = TRUE, sign_in = TRUE, isolated_rows = !shared,
    data_policy = if (shared) "shared-read-only" else "per-user rows",
    writes_denied = if (permission_demo) TRUE else NULL,
    sign_out = TRUE, stopped = TRUE), file.path(output, "result.json"), auto_unbox = TRUE, pretty = TRUE)
  cat(database, ": installed-package Docker/browser demo passed.\n")
}
dir.create(".validation", showWarnings = FALSE)
check_demo()
