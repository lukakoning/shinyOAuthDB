# Run one installed-package demo with Docker and a real browser.
# Rscript --vanilla tools/check-demos.R postgres [additional-library-paths]
arguments <- commandArgs(trailingOnly = TRUE)
database <- if (length(arguments)) arguments[[1L]] else "postgres"
if (length(arguments) > 1L) .libPaths(c(arguments[-1L], .libPaths()))
stopifnot(database %in% c("postgres", "postgrest", "trino", "starrocks"))

check_demo <- function() {
  output <- file.path(normalizePath(".validation", winslash = "/", mustWork = TRUE), "demos", database)
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  library <- tempfile("demo-library-")
  dir.create(library)
  pkgbuild::rcmd_build_tools("INSTALL", c(paste0("--library=", library), "."))
  libpath <- c(library, .libPaths())
  path <- tempfile(paste0("demo with spaces-", database, "-"))
  process <- callr::r_bg(function(database, path) {
    # This process has an installed package and no repository working directory.
    setwd(tempdir())
    shinyOAuthDB::oauth_db_demo(database, path = path, launch_browser = FALSE)
  }, args = list(database, path), libpath = libpath, supervise = TRUE,
    stdout = file.path(output, "launcher.log"), stderr = file.path(output, "docker.log"))
  chrome <- NULL
  on.exit({
    if (!is.null(chrome)) chrome$close()
    if (process$is_alive()) {
      try(callr::r(function(database, path) {
        shinyOAuthDB::oauth_db_demo(database, action = "stop", path = path)
      }, args = list(database, path), libpath = libpath), silent = TRUE)
      process$wait(10000)
      if (process$is_alive()) process$kill()
    }
  }, add = TRUE)
  deadline <- Sys.time() + 1200
  repeat {
    ready <- tryCatch(curl::curl_fetch_memory("http://localhost:18100")$status_code == 200L,
      error = function(e) FALSE)
    if (ready) break
    if (!process$is_alive() || Sys.time() > deadline) {
      stop("Demo startup failed. See ", output, "/docker.log", call. = FALSE)
    }
    Sys.sleep(0.2)
  }
  chrome <- chromote::Chromote$new()
  value <- function(browser, js) browser$Runtime$evaluate(js, returnByValue = TRUE)$result$value
  wait <- function(browser, js) {
    deadline <- Sys.time() + 40
    repeat {
      if (isTRUE(tryCatch(value(browser, js), error = function(e) FALSE))) return(invisible(TRUE))
      if (Sys.time() > deadline) stop("Demo browser check timed out: ", js, call. = FALSE)
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
    stopifnot(identical(trimws(value(browser, "document.querySelector('#rows').textContent")), ""))
    value(browser, "document.querySelector('#login').click()")
    wait(browser, "Boolean(document.querySelector('#username') && document.querySelector('#kc-login'))")
    value(browser, sprintf(paste0("document.querySelector('#username').value='%s';",
      "document.querySelector('#password').value='%s-fixture-password';",
      "document.querySelector('#kc-login').click()"), user, user))
    wait(browser, sprintf("Boolean(document.querySelector('#rows')?.textContent.includes('%s-visible-1'))", user))
    rows <- value(browser, "document.querySelector('#rows').textContent")
    other <- if (user == "alice") "bob" else "alice"
    stopifnot(grepl(paste0(user, "-visible-2"), rows), !grepl(paste0(other, "-visible"), rows))
    value(browser, "document.querySelector('#logout').click()")
    wait(browser, "Boolean(document.querySelector('#rows') && document.querySelector('#rows').textContent.trim() === '')")
    cat(user, ": sign-in, own rows, other account excluded, sign-out clears output\n")
    if (user == "bob") {
      value(browser, "document.querySelector('#stop').click()")
    }
    browser$close()
    chrome$Target$disposeBrowserContext(context)
  }
  process$wait(30000)
  if (process$is_alive()) stop("Stop demo did not finish cleanup.", call. = FALSE)
  stopifnot(identical(process$get_exit_status(), 0L))
  process$get_result()
  jsonlite::write_json(list(database = database, accounts = c("alice", "bob"),
    installed_package = TRUE, sign_in = TRUE, isolated_rows = TRUE,
    sign_out = TRUE, stopped = TRUE), file.path(output, "result.json"), auto_unbox = TRUE, pretty = TRUE)
  cat(database, ": installed-package Docker/browser demo passed.\n")
}
dir.create(".validation", showWarnings = FALSE)
check_demo()
