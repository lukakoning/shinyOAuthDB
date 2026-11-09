# Native Flight SQL transport checks; no Dremio deployment or user credentials.
# Rscript --vanilla tools/check-dremio.R <python> [additional R libraries ...]
main <- function() {
  arguments <- commandArgs(trailingOnly = TRUE)
  if (!length(arguments)) {
    stop(
      "Supply a Python executable with integration/dremio-flightsql/requirements.txt installed.",
      call. = FALSE
    )
  }
  python <- arguments[[1L]]
  if (length(arguments) > 1L) {
    .libPaths(c(arguments[-1L], .libPaths()))
  }
  Sys.setenv(LC_ALL = "C", LANG = "C", LANGUAGE = "en")
  for (package in c("pkgload", "testthat", "processx", "jsonlite")) {
    if (!requireNamespace(package, quietly = TRUE)) stop("Install ", package)
  }
  pkgload::load_all(quiet = TRUE)
  library(testthat)
  source("tests/testthat/helper-authorization.R")
  output <- tempfile("dremio-flightsql-")
  dir.create(output)
  server <- processx::process$new(
    python,
    c("integration/dremio-flightsql/server.py", "--output", output),
    stdout = "|",
    stderr = "|",
    windows_hide_window = TRUE
  )
  on.exit(server$kill(), add = TRUE)
  ready <- file.path(output, "ready.json")
  deadline <- Sys.time() + 30
  while (!file.exists(ready)) {
    if (!server$is_alive() || Sys.time() > deadline) {
      server$kill()
      stop(
        "Flight SQL fixture failed: ",
        server$read_all_error(),
        call. = FALSE
      )
    }
    Sys.sleep(0.1)
  }
  withr::local_envvar(c(OAUTHDB_DREMIO_FIXTURE = ready))
  testthat::test_file(
    "integration/dremio-flightsql/test-native.R",
    reporter = "summary",
    stop_on_failure = TRUE
  )
}
main()
