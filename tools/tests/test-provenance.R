source(file.path("..", "..", "integration", "provenance.R"), local = TRUE)
testthat::test_that("integration fingerprints change with dirty source and exclude generated results", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "R"))
  dir.create(file.path(root, "integration", ".generated"), recursive = TRUE)
  writeLines("Package: fixture", file.path(root, "DESCRIPTION"))
  writeLines("x <- 1", file.path(root, "R", "code.R"))
  before <- integration_provenance(root, packages = "DBI")
  writeLines(
    "ignored",
    file.path(root, "integration", ".generated", "result.R")
  )
  testthat::expect_identical(
    integration_provenance(root, packages = "DBI")$source_sha256,
    before$source_sha256
  )
  writeLines("x <- 2", file.path(root, "R", "code.R"))
  after <- integration_provenance(root, packages = "DBI")
  testthat::expect_false(identical(after$source_sha256, before$source_sha256))
  testthat::expect_identical(
    names(after$source_files),
    c("DESCRIPTION", "R/code.R")
  )
  testthat::expect_match(after$source_sha256, "^[a-f0-9]{64}$")
  testthat::expect_identical(
    after$dependencies$DBI,
    as.character(utils::packageVersion("DBI"))
  )
  testthat::expect_error(jsonlite::toJSON(after, auto_unbox = TRUE), NA)
  absent <- integration_provenance(root, packages = "nonexistentFixturePackage")
  testthat::expect_true(is.na(absent$dependencies$nonexistentFixturePackage))
})
