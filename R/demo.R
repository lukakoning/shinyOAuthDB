#' Run a local database OAuth demo
#'
#' Start a database, Keycloak sign-in and a small Shiny app using Docker.
#' The installed package includes the configuration, accounts and sample data;
#' no source checkout, cloud account or local database driver is needed.
#'
#' @param database Demo to run: `"postgres"` (the default), `"postgrest"`,
#'   `"trino"`, `"starrocks"`, `"duckdb"` (Quack), `"libsql"`, `"cratedb"`,
#'   or `"opensearch"`.
#' @param action `"start"` runs the demo until you stop it or interrupt R.
#'   `"stop"` removes its containers and data, including after a forced exit.
#'   `"files"` copies the configuration without starting Docker.
#' @param path Directory for the demo files. Defaults to a database-specific
#'   directory in R's user cache. Existing demo files are kept so you can edit
#'   the app or configuration. An unrelated nonempty directory is refused.
#' @param launch_browser Open the app in your browser once it is ready.
#' @param build Build Docker images before starting. Set to `FALSE` to reuse
#'   images from a previous successful build.
#' @return Invisibly, the directory containing the demo configuration.
#' @details
#' Install and start Docker with Linux containers and Docker Compose v2.
#' The first build downloads images, R packages and pinned package sources
#' from GitHub. PostgreSQL also compiles its native OAuth runtime. Allow
#' several minutes and a few GB of disk space. StarRocks uses amd64 images
#' and needs about 4 GB of Docker memory; other architectures need emulation.
#' DuckDB installs a matching R client and Quack extensions; the client
#' compiles from source if a Linux binary isn't available.
#' OpenSearch needs about 2 GB of Docker memory for its database container.
#'
#' Open `http://localhost:18100` and sign in as `alice` with password
#' `alice-fixture-password`, or `bob` with password `bob-fixture-password`.
#' Keycloak uses a generated test certificate at `https://localhost:18443`;
#' your browser may ask you to accept it for this local demo.
#'
#' Run one demo at a time: they share the same loopback ports. All accounts
#' are public demo accounts. Containers bind browser ports to loopback only.
#' Clicking **Stop demo**, or interrupting the foreground R call, removes
#' the demo's containers and volumes. The copied files and cached images stay.
#' A separate R session can use `action = "stop"` after a forced exit.
#'
#' To edit an example, first use `action = "files"`, edit the returned
#' directory, then call with the same `path`. `app.R` in the selected
#' database's subdirectory is the Shiny app. Stop the demo before rebuilding.
#' @examples
#' \dontrun{
#' oauth_db_demo()
#' oauth_db_demo("postgrest")
#' oauth_db_demo("trino")
#' oauth_db_demo("starrocks")
#' oauth_db_demo("duckdb")
#' oauth_db_demo("libsql")
#' oauth_db_demo("cratedb")
#' oauth_db_demo("opensearch")
#' oauth_db_demo(action = "stop")
#' path <- oauth_db_demo(action = "files")
#' }
#' @seealso [oauth_db_postgres()], [oauth_db_postgrest_api()],
#'   [oauth_db_trino()], [oauth_db_starrocks()], [oauth_db_duckdb()],
#'   [oauth_db_libsql_api()], [oauth_db_cratedb_api()], [oauth_db_opensearch_api()].
#' @export
oauth_db_demo <- function(
  database = c("postgres", "postgrest", "trino", "starrocks",
    "duckdb", "libsql", "cratedb", "opensearch"),
  action = c("start", "stop", "files"), path = NULL,
  launch_browser = interactive(), build = TRUE
) {
  database <- match.arg(database)
  action <- match.arg(action)
  if (is.null(path)) {
    path <- file.path(tools::R_user_dir("shinyOAuthDB", "cache"), "demo", database)
  }
  .odb_string(path, "path")
  for (flag in list(launch_browser = launch_browser, build = build)) {
    if (!is.logical(flag) || length(flag) != 1L || is.na(flag)) {
      stop("launch_browser and build must each be TRUE or FALSE.", call. = FALSE)
    }
  }
  source <- system.file("docker", package = "shinyOAuthDB", mustWork = TRUE)
  marker <- file.path(path, ".shinyOAuthDB-demo")
  if (action == "stop" && !file.exists(marker)) {
    stop("No demo configuration at this path. Use the path from the launcher.", call. = FALSE)
  }
  if (!file.exists(marker)) {
    if (dir.exists(path) && length(list.files(path, all.files = TRUE, no.. = TRUE))) {
      stop("path must be empty or contain a shinyOAuthDB demo.", call. = FALSE)
    }
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
    files <- list.files(source, all.files = TRUE, no.. = TRUE, full.names = TRUE)
    if (!all(file.copy(files, path, recursive = TRUE))) {
      stop("Could not copy the demo configuration to path.", call. = FALSE)
    }
    writeLines(as.character(utils::packageVersion("shinyOAuthDB")), marker)
  }
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  if (action == "files") return(invisible(path))
  docker <- .odb_demo_docker()
  project <- paste0("shinyoauthdb-demo-", database, "-",
    substr(openssl::sha256(charToRaw(path)), 1L, 8L))
  compose <- c("compose", "--project-name", project, "--project-directory", path,
    "--file", file.path(path, "compose.yml"),
    "--file", file.path(path, paste0("compose.", database, ".yml")))
  run <- function(args, check = TRUE) .odb_demo_command(docker, c(compose, args), check)
  cleanup <- function() run(c("down", "--volumes", "--remove-orphans"), check = FALSE)
  if (action == "stop") {
    if (cleanup() != 0L) stop("Docker could not stop the demo; see its output above.", call. = FALSE)
    return(invisible(path))
  }
  run(c("config", "--quiet"))
  message("Demo files: ", path)
  message("After a forced exit, run oauth_db_demo(\"", database,
    "\", action = \"stop\", path = ", deparse(path), ")")
  on.exit({
    if (cleanup() != 0L) warning("Demo cleanup failed. Use action = 'stop' after Docker is available.", call. = FALSE)
  }, add = TRUE)
  started <- run(c("up", "--detach", "--wait", "--wait-timeout", "360",
    if (build) "--build" else "--no-build", "app"), check = FALSE)
  if (started != 0L) {
    run(c("logs", "--tail", "50"), check = FALSE)
    stop("Docker could not start the demo; see its logs above.", call. = FALSE)
  }
  message("Open http://localhost:18100. Sign in as alice / alice-fixture-password",
    " or bob / bob-fixture-password. Click Stop demo or interrupt R to finish.")
  if (launch_browser) utils::browseURL("http://localhost:18100")
  run(c("logs", "--follow", "app"))
  invisible(path)
}

.odb_demo_docker <- function() {
  docker <- Sys.which("docker")
  if (!nzchar(docker)) stop("Install Docker with Linux containers and Compose v2 first.", call. = FALSE)
  os <- suppressWarnings(system2(docker, c("info", "--format", shQuote("{{.OSType}}")),
    stdout = TRUE, stderr = TRUE))
  if (!is.null(attr(os, "status")) || !"linux" %in% os) {
    stop("Start Docker with Linux containers before running the demo.", call. = FALSE)
  }
  .odb_demo_command(docker, c("compose", "version"))
  docker
}

.odb_demo_command <- function(docker, args, check = TRUE) {
  status <- system2(docker, vapply(args, shQuote, ""))
  if (check && status != 0L) {
    stop("Docker could not run the demo command; see its output above.", call. = FALSE)
  }
  invisible(status)
}
