source(file.path("..", "demo-source.R"), local = TRUE)
source(
  file.path("..", "..", "inst", "docker", "package-source", "install.R"),
  local = TRUE
)

demo_source_fixture <- function(root) {
  dir.create(file.path(root, "R"), recursive = TRUE)
  writeLines(
    c(
      "Package: shinyOAuthDB",
      "Version: 0.0.0.9000",
      "Title: Demo Source Fixture",
      "Description: Tests that the Docker demo installs the supplied package source.",
      "Author: Fixture Author",
      "Maintainer: Fixture Author <fixture@example.invalid>",
      "License: MIT"
    ),
    file.path(root, "DESCRIPTION")
  )
  writeLines("export(candidate_marker)", file.path(root, "NAMESPACE"))
  writeLines(
    'candidate_marker <- function() "checkout source"',
    file.path(root, "R", "marker.R")
  )
}

testthat::test_that("demo source staging installs the candidate code with its fingerprint", {
  root <- file.path(withr::local_tempdir(), "source")
  demo_source_fixture(root)
  path <- file.path(withr::local_tempdir(), "demo with spaces")
  output <- withr::local_tempdir()
  expected <- demo_source_prepare(root, path, output)
  source <- file.path(path, "package-source")
  testthat::expect_identical(
    readLines(file.path(source, "source.sha256")),
    expected$source_sha256
  )
  testthat::expect_match(expected$source_sha256, "^[0-9a-f]{64}$")
  library <- withr::local_tempdir()
  testthat::expect_identical(
    install_demo_source(source, library),
    expected$source_sha256
  )
  actual <- callr::r(
    function() {
      list(
        marker = shinyOAuthDB::candidate_marker(),
        hash = readLines(system.file(
          "Meta",
          "demo-source.sha256",
          package = "shinyOAuthDB"
        ))
      )
    },
    libpath = c(library, .libPaths())
  )
  testthat::expect_identical(actual$marker, "checkout source")
  testthat::expect_identical(actual$hash, expected$source_sha256)

  writeLines(
    'candidate_marker <- function() "changed source"',
    file.path(root, "R", "marker.R")
  )
  changed <- demo_source_prepare(root, path, output)
  testthat::expect_false(identical(
    changed$source_sha256,
    expected$source_sha256
  ))
})

testthat::test_that("demo source installation rejects incomplete or modified payloads", {
  path <- withr::local_tempdir()
  testthat::expect_null(install_demo_source(path))
  archive <- file.path(path, "shinyOAuthDB.tar.gz")
  manifest <- file.path(path, "source.sha256")
  writeLines("not a package", archive)
  testthat::expect_error(install_demo_source(path), "both be present")
  writeLines("invalid", manifest)
  testthat::expect_error(install_demo_source(path), "hash is invalid")
  writeLines(strrep("0", 64L), manifest)
  testthat::expect_error(install_demo_source(path), "does not match")
  unlink(archive)
  testthat::expect_error(install_demo_source(path), "both be present")
})

testthat::test_that("demo runtime verification rejects a different package source or version", {
  env <- new.env(parent = baseenv())
  sys.source(file.path("..", "demo-source.R"), envir = env)
  expected <- list(source_sha256 = strrep("a", 64L), version = "0.0.0.9000")
  actual <- c(expected$source_sha256, expected$version)
  containers <- "0123456789ab"
  env$system2 <- function(command, args, ...) {
    testthat::expect_identical(command, "docker")
    if (grepl("ps", args[[1L]], fixed = TRUE)) containers else actual
  }
  runtime <- env$demo_source_identity("docker", "demo-project", expected)
  testthat::expect_identical(runtime$source_sha256, expected$source_sha256)
  testthat::expect_identical(runtime$container, containers)
  actual <- c(strrep("b", 64L), expected$version)
  testthat::expect_error(
    env$demo_source_identity("docker", "demo-project", expected),
    "candidate package source"
  )
  actual <- c(expected$source_sha256, "0.0.0.1")
  testthat::expect_error(
    env$demo_source_identity("docker", "demo-project", expected),
    "candidate package source"
  )
  containers <- character()
  testthat::expect_error(
    env$demo_source_identity("docker", "demo-project", expected),
    "one running"
  )
})
