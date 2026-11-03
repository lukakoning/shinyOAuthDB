# Run from the checkout: source("playground/postgres/run.R")
# Docker supplies R, Shiny, PostgreSQL, Keycloak and the native OAuth libraries.
local({
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  fixture <- file.path(root, "integration", "postgres-keycloak")
  if (!file.exists(file.path(fixture, "compose.yml"))) {
    stop("Run this script from the shinyOAuthDB repository root.", call. = FALSE)
  }
  if (!file.exists(file.path(dirname(root), "shinyOAuth", "DESCRIPTION"))) {
    stop("Check out lukakoning/shinyOAuth beside shinyOAuthDB first.", call. = FALSE)
  }
  docker <- Sys.which("docker")
  if (!nzchar(docker)) stop("Install and start Docker with Linux containers.", call. = FALSE)
  status <- system2(docker, "info", stdout = FALSE, stderr = FALSE)
  if (status != 0L) stop("Start Docker with Linux containers first.", call. = FALSE)

  message("Building and starting the PostgreSQL OAuth playground.")
  message("Open http://localhost:18100 after Shiny starts.")
  message("Sign in as alice / alice-fixture-password or bob / bob-fixture-password.")
  message("Click Stop playground in the app to remove its containers and test data.")
  launch <- function() {
    project <- basename(tempfile("shinyoauthdb-postgres-playground-"))
    compose <- c("compose", "--project-name", project, "--file",
      shQuote(file.path(fixture, "compose.yml")))
    message("Cleanup after a forced exit: ", paste(c("docker", compose,
      "down", "--volumes", "--remove-orphans"), collapse = " "))
    run <- function(args) {
      status <- system2(docker, c(compose, args))
      if (status != 0L) stop("The Docker playground command failed; see the output above.", call. = FALSE)
      invisible(status)
    }
    # Cleanup also runs when the user interrupts this function in RStudio.
    on.exit(system2(docker, c(compose, "down", "--volumes", "--remove-orphans")), add = TRUE)
    run(c("config", "--quiet"))
    if (!identical(Sys.getenv("OAUTHDB_SKIP_BUILD"), "1")) {
      run(c("build", "postgres", "test-runner"))
    }
    run(c("up", "--detach", "--wait", "--wait-timeout", "240", "postgres"))
    run(c("run", "--rm", "--no-deps", "test-runner", "Rscript",
      "integration/postgres-keycloak/run-tests.R", "--playground"))
  }
  launch()
})
