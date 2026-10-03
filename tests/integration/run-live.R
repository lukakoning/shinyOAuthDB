# Run from the repository root with an installed shinyOAuthDB package.
# No cloud calls happen without both an explicit flag and a trusted fixture file.
if (!identical(Sys.getenv("OAUTHDB_LIVE_TESTS"), "true")) {
  stop(
    "Live tests are disabled. See tests/integration/README.md.",
    call. = FALSE
  )
}

source("tests/integration/source-config.R", local = TRUE)
source("tests/integration/live-transport.R", local = TRUE)
fixture_path <- live_env("OAUTHDB_LIVE_FIXTURE")
if (!file.exists(fixture_path)) {
  stop(
    "OAUTHDB_LIVE_FIXTURE must name an existing trusted R file.",
    call. = FALSE
  )
}

fixture_environment <- new.env(parent = globalenv())
sys.source(fixture_path, envir = fixture_environment)
if (!exists("fixture", envir = fixture_environment, inherits = FALSE)) {
  stop(
    "The fixture file must define fixture. See fixture.example.R.",
    call. = FALSE
  )
}

success <- tryCatch(
  suppressWarnings(suppressMessages(run_live_transport(
    fixture_environment$fixture
  ))),
  error = function(e) {
    # Driver errors may contain tokens or connection strings. Do not print the
    # condition, call, raw result or fixture contents in this runner.
    message(
      "Live transport check failed. Review fixture setup, expiry, grants, driver installation and network access."
    )

    FALSE
  }
)

if (!isTRUE(success)) {
  quit(save = "no", status = 1L)
}

message(
  "Live A/B transport, authorization replacement and cleanup checks passed."
)
