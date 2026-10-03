# Browser smoke of the actual integrated app against existing sandbox discovery.
# Reads shared sandbox settings from .Renviron. Does not start/pause capacity.
main <- function() {
  libraries <- commandArgs(trailingOnly = TRUE)
  if (length(libraries)) .libPaths(c(libraries, .libPaths()))
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  port <- httpuv::randomPort()
  server <- callr::r_bg(function(root, libraries, port) {
    .libPaths(libraries)
    Sys.setenv(FABRIC_SHINY_AUTH = "sandbox")
    pkgload::load_all(root, quiet = TRUE)
    shiny::runApp(file.path(root, "playground", "fabric"), port = port,
      host = "127.0.0.1", launch.browser = FALSE)
  }, args = list(root, .libPaths(), port), supervise = TRUE)
  on.exit(server$kill(), add = TRUE)
  url <- paste0("http://127.0.0.1:", port)
  ready <- FALSE
  for (i in seq_len(60L)) {
    if (!server$is_alive()) stop(paste(server$read_error_lines(), collapse = "\n"))
    ready <- tryCatch(httr2::resp_status(httr2::req_perform(httr2::request(url))) == 200L,
      error = function(e) FALSE)
    if (ready) break
    Sys.sleep(0.5)
  }
  stopifnot(ready)
  browser <- chromote::ChromoteSession$new()
  on.exit(browser$close(), add = TRUE)
  browser$Page$navigate(url)
  js <- function(code) browser$Runtime$evaluate(code, returnByValue = TRUE)$result$value
  for (i in seq_len(120L)) {
    if (isTRUE(js("!!(window.Shiny && Shiny.shinyapp && document.querySelector('#items table'))"))) break
    Sys.sleep(0.5)
  }
  stopifnot(isTRUE(js("document.body.innerText.includes('Shared sandbox identity')")))
  stopifnot(js("Object.keys(document.querySelector('#source').selectize.options).length") == 10L)
  stopifnot(js("document.querySelectorAll('#items tbody tr').length") > 0L)
  js("document.querySelector('#source').selectize.setValue('discovery'); Shiny.setInputValue('run', 1, {priority:'event'});")
  for (i in seq_len(120L)) {
    if (isTRUE(js("!!document.querySelector('#rows table')"))) break
    Sys.sleep(0.5)
  }
  stopifnot(js("document.querySelectorAll('#rows tbody tr').length") > 0L)
  dir.create("tests/integration/results", recursive = TRUE, showWarnings = FALSE)
  screenshot <- browser$Page$captureScreenshot()$data
  writeBin(base64enc::base64decode(screenshot), "tests/integration/results/fabric-browser.png")
  cat("Browser passed: shared identity banner, ten sources, live item discovery and rendered rows.\n")
}
main()
