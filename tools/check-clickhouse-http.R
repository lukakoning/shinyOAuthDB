arguments <- commandArgs(trailingOnly = TRUE)
if (length(setdiff(arguments, "--skip-build"))) {
  .libPaths(c(setdiff(arguments, "--skip-build"), .libPaths()))
}
local({
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  stopifnot(file.exists(file.path(root, "DESCRIPTION")))
  project <- paste0(
    "oauthdb-clickhouse-",
    paste(sample(c(letters, 0:9), 12L, replace = TRUE), collapse = "")
  )
  compose <- c(
    "compose",
    "--project-name",
    project,
    "--file",
    file.path(root, "integration/clickhouse-http/compose.yml")
  )
  docker <- function(args, check = TRUE) {
    # Docker Desktop can retain child stdout pipes after a completed container.
    # File output lets processx wait for the CLI without waiting on those pipes.
    log <- tempfile("clickhouse-docker-", fileext = ".log")
    on.exit(unlink(log), add = TRUE)
    result <- processx::run(
      "docker",
      args,
      stdout = log,
      stderr = "2>&1",
      error_on_status = FALSE
    )
    if (file.exists(log)) {
      cat(readLines(log, warn = FALSE), sep = "\n")
    }
    if (check && result$status != 0L) {
      stop("ClickHouse fixture command failed.", call. = FALSE)
    }
    result$status
  }
  if (
    Sys.getenv("OAUTHDB_SKIP_BASE_BUILD") != "1" &&
      !"--skip-build" %in% arguments
  ) {
    docker(c(
      "build",
      "--target",
      "runner",
      "--tag",
      "shinyoauthdb-local-runner:1",
      file.path(root, "integration/local")
    ))
    docker(c(
      "build",
      "--target",
      "tls",
      "--tag",
      "shinyoauthdb-local-tls:1",
      file.path(root, "integration/local")
    ))
  }
  on.exit(
    docker(c(compose, "down", "--volumes", "--remove-orphans"), check = FALSE),
    add = TRUE
  )
  docker(c(compose, "config", "--quiet"))
  docker(c(
    compose,
    "up",
    "--detach",
    "--wait",
    "--wait-timeout",
    "180",
    "https"
  ))
  docker(c(
    compose,
    "run",
    "--rm",
    "--no-deps",
    "--interactive=false",
    "-T",
    "test-runner"
  ))
})
