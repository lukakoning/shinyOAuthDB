# Source-checkout smoke; these scripts are not installed package assets.
# Run from the repository root: Rscript tools/check-playground.R [--test]
if (
  !file.exists("playground/example-offline.R") || !file.exists("DESCRIPTION")
) {
  stop(
    "Run this source-only smoke check from the shinyOAuthDB repository root.",
    call. = FALSE
  )
}

paths <- c(
  list.files("playground", pattern = "\\.R$", full.names = TRUE),
  list.files("tests/integration", pattern = "\\.R$", full.names = TRUE),
  list.files(
    "integration/postgres-keycloak",
    pattern = "\\.R$",
    full.names = TRUE,
    recursive = TRUE
  )
)

for (path in paths) {
  parse(path)
}

cat(length(paths), "playground/integration scripts parsed successfully.\n")
if ("--test" %in% commandArgs(trailingOnly = TRUE)) {
  if (
    !requireNamespace("pkgload", quietly = TRUE) ||
      !requireNamespace("testthat", quietly = TRUE)
  ) {
    stop(
      "Install pkgload and testthat to run the offline smoke scenarios.",
      call. = FALSE
    )
  }

  pkgload::load_all(".", quiet = TRUE)

  testthat::test_dir(
    "tests/testthat",
    filter = "playground|multiple-connections|standalone-apps",
    stop_on_failure = TRUE
  )
}
