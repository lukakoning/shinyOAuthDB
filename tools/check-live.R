# Install this checkout and run a trusted cloud fixture. No provisioning occurs.
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) .libPaths(c(arguments, .libPaths()))
local({
  if (!identical(Sys.getenv("OAUTHDB_LIVE_TESTS"), "true")) stop("Live tests are disabled.", call. = FALSE)
  output <- "tests/integration/results"
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  source("integration/provenance.R", local = TRUE)
  jsonlite::write_json(list(status = "fail", stage = "setup", provenance = integration_provenance()),
    file.path(output, "live.json"), auto_unbox = TRUE, pretty = TRUE)
  source("tests/integration/cloud-credentials.R", local = TRUE)
  tryCatch({
    live_apply_config()
    mode <- Sys.getenv("OAUTHDB_LIVE_CREDENTIAL_MODE", "fixed-token")
    if (mode == "google-refresh") {
      # Only this reviewed BigQuery fixture uses the Google renewal path.
      if (!identical(Sys.getenv("OAUTHDB_LIVE_FIXTURE"), "tests/integration/bigquery.fixture.R"))
        stop("Google renewal requires the BigQuery fixture.", call. = FALSE)
      live_google_refresh("A")
      live_google_refresh("B")
    } else if (mode != "fixed-token") stop("Unknown credential mode.", call. = FALSE)
    library <- tempfile("cloud-acceptance-library-")
    stage <- tempfile("cloud-acceptance-source-")
    dir.create(library)
    dir.create(stage)
    on.exit(unlink(c(library, stage), recursive = TRUE), add = TRUE)
    stopifnot(all(file.copy(c("DESCRIPTION", "NAMESPACE", "LICENSE", "R", "man", "src", "configure", "cleanup"),
      stage, recursive = TRUE)))
    .libPaths(c(library, .libPaths()))
    Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
    pkgbuild::rcmd_build_tools("INSTALL", c("--preclean", "--no-byte-compile", paste0("--library=", library), stage))
    stopifnot(identical(normalizePath(find.package("shinyOAuthDB")), normalizePath(file.path(library, "shinyOAuthDB"))))
    source("tests/integration/run-live.R", local = TRUE)
  }, error = function(e) {
    # Credentials and native connection errors never enter CI logs/artifacts.
    stop("Cloud acceptance failed. Review configuration, credentials, drivers and fixture grants.", call. = FALSE)
  })
})
