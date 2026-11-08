source(file.path("..", "validation.R"), local = TRUE)

validation_git_fixture <- function() {
  testthat::skip_if(!nzchar(Sys.which("git")), "Git is unavailable")
  root <- tempfile("validation source ")
  dir.create(root)
  run <- function(...) {
    result <- system2(
      Sys.which("git"),
      c("-C", shQuote(root), ...),
      stdout = TRUE,
      stderr = TRUE
    )
    stopifnot(is.null(attr(result, "status")))
    invisible(result)
  }
  run("init", "-q")
  dir.create(file.path(root, "R"))
  writeLines("value <- 1", file.path(root, "R", "code.R"))
  writeLines(
    c(".validation/", "src/*.o", "src/Makevars"),
    file.path(root, ".gitignore")
  )
  run("add", ".")
  run(
    "-c",
    "user.name=Validation",
    "-c",
    "user.email=validation@example.invalid",
    "-c",
    "commit.gpgsign=false",
    "commit",
    "-qm",
    shQuote("Fixture source")
  )
  list(root = root, run = run)
}

testthat::test_that("source provenance records local commits, dirty files and exact content", {
  fixture <- validation_git_fixture()
  on.exit(unlink(fixture$root, recursive = TRUE), add = TRUE)
  before <- validation_source(fixture$root)
  testthat::expect_match(before$revision, "^[0-9a-f]{40}$")
  testthat::expect_false(before$dirty)
  testthat::expect_true("R/code.R" %in% names(before$source_files))
  writeLines("value <- 2", file.path(fixture$root, "R", "code.R"))
  changed <- validation_source(fixture$root)
  testthat::expect_true(changed$dirty)
  testthat::expect_identical(changed$revision, before$revision)
  testthat::expect_false(identical(changed$source_sha256, before$source_sha256))
  testthat::expect_error(
    validation_check_source(before, changed),
    "source changed during validation"
  )
  writeLines("value <- 1", file.path(fixture$root, "R", "code.R"))
  dir.create(file.path(fixture$root, ".validation"))
  writeLines("generated", file.path(fixture$root, ".validation", "output"))
  testthat::expect_identical(
    validation_source(fixture$root)$source_sha256,
    before$source_sha256
  )
  writeLines("extra <- 1", file.path(fixture$root, "R", "extra.R"))
  added <- validation_source(fixture$root)
  testthat::expect_true(added$dirty)
  testthat::expect_true("R/extra.R" %in% names(added$source_files))
  testthat::expect_false(identical(added$source_sha256, before$source_sha256))
  unlink(file.path(fixture$root, "R", "code.R"))
  testthat::expect_true(is.na(
    validation_source(fixture$root)$source_files[["R/code.R"]]
  ))
})

testthat::test_that("source provenance supports linked worktrees and ignores an archive's parent repository", {
  withr::local_envvar(c(GITHUB_SHA = NA))
  fixture <- validation_git_fixture()
  worktree <- tempfile("validation linked ")
  on.exit(
    {
      fixture$run("worktree", "remove", "--force", shQuote(worktree))
      unlink(fixture$root, recursive = TRUE)
    },
    add = TRUE
  )
  fixture$run("worktree", "add", "--detach", shQuote(worktree), "HEAD")
  testthat::expect_identical(
    validation_source(worktree)$revision,
    validation_source(fixture$root)$revision
  )
  archive <- file.path(fixture$root, "archive")
  dir.create(archive)
  dir.create(file.path(archive, "R"))
  writeLines("value <- 1", file.path(archive, "R", "code.R"))
  source <- validation_source(archive)
  testthat::expect_true(is.na(source$revision))
  testthat::expect_true(is.na(source$dirty))
  testthat::expect_true("R/code.R" %in% names(source$source_files))
  dir.create(file.path(archive, "src"))
  writeLines("generated", file.path(archive, "src", "generated.o"))
  testthat::expect_identical(
    validation_source(archive)$source_sha256,
    source$source_sha256
  )
})

testthat::test_that("validation persists source provenance and refuses changed source", {
  fixture <- validation_git_fixture()
  on.exit(unlink(fixture$root, recursive = TRUE), add = TRUE)
  output <- file.path(fixture$root, ".validation")
  before <- validation_source(fixture$root)
  passing <- data.frame(
    test = "fixture",
    passed = 1L,
    failed = 0L,
    error = FALSE,
    warning = 0L,
    skipped = FALSE
  )
  validation_check_results(
    passing,
    output,
    packages = c(stats = "0"),
    source_before = before
  )
  summary <- jsonlite::read_json(file.path(output, "test-summary.json"))
  provenance <- jsonlite::read_json(file.path(output, "source-provenance.json"))
  testthat::expect_identical(summary$revision, before$revision)
  testthat::expect_identical(summary$source_sha256, before$source_sha256)
  testthat::expect_false(provenance$changed)
  writeLines("value <- 2", file.path(fixture$root, "R", "code.R"))
  testthat::expect_error(
    validation_check_results(
      passing,
      output,
      packages = c(stats = "0"),
      source_before = before
    ),
    "source changed during validation"
  )
  provenance <- jsonlite::read_json(file.path(output, "source-provenance.json"))
  testthat::expect_true(provenance$changed)
  testthat::expect_identical(
    provenance$before$source_sha256,
    before$source_sha256
  )
  testthat::expect_false(identical(
    provenance$after$source_sha256,
    before$source_sha256
  ))
})

testthat::test_that("full validation refuses missing and outdated dependencies", {
  testthat::expect_error(
    validation_check_dependencies(c(oauthdb_absent_backend = "1.0.0")),
    "oauthdb_absent_backend"
  )
  testthat::expect_error(
    validation_check_dependencies(c(stats = "9999.0.0")),
    "stats"
  )
  testthat::expect_true(validation_check_dependencies(c(stats = "0")))
})

testthat::test_that("dependency requirements include optional backends and their minimum versions", {
  path <- tempfile()
  on.exit(unlink(path), add = TRUE)
  writeLines(
    c(
      "Package: fixture",
      "Imports: DBI (>= 1.2.0)",
      "Suggests: odbc (>= 1.4.2),",
      "    RSQLite"
    ),
    path
  )
  testthat::expect_identical(
    validation_dependencies(path),
    c(DBI = "1.2.0", odbc = "1.4.2", RSQLite = "0")
  )
})

testthat::test_that("exact compatibility validation rejects silently upgraded SDKs", {
  actual <- c(stats = as.character(utils::packageVersion("stats")))
  testthat::expect_identical(
    validation_check_exact_dependencies(actual),
    actual
  )
  testthat::expect_error(
    validation_check_exact_dependencies(c(stats = "0")),
    "exact dependency versions"
  )
  testthat::expect_error(
    validation_check_exact_dependencies(c(stats = "9999.0.0")),
    "declared minimum"
  )
  testthat::expect_error(
    validation_check_exact_dependencies(c(oauthdb_absent_backend = "1.0.0")),
    "oauthdb_absent_backend"
  )
})

testthat::test_that("skips, warnings, failures and empty runs cannot pass full validation", {
  # Keep metadata lookup independent of the caller's working directory.
  validation_dependencies <- function(...) c(stats = "0")
  environment(validation_check_results) <- environment()
  output <- tempfile()
  on.exit(unlink(output, recursive = TRUE), add = TRUE)
  passing <- data.frame(
    test = "fixture",
    passed = 1L,
    failed = 0L,
    error = FALSE,
    warning = 0L,
    skipped = FALSE
  )
  passing$result <- I(list(list(list(message = "expectation details"))))
  testthat::expect_identical(
    validation_check_results(passing, output)$passed,
    1L
  )
  for (field in c("failed", "error", "warning", "skipped")) {
    counts <- passing
    counts[[field]] <- 1L
    testthat::expect_error(
      validation_check_results(counts, output),
      "zero failures"
    )
    report <- jsonlite::read_json(file.path(output, "test-summary.json"))
    name <- switch(field, error = "errors", warning = "warnings", field)
    testthat::expect_equal(report[[name]], 1L)
  }
  testthat::expect_error(
    validation_check_results(passing[FALSE, ], output),
    "passing assertions"
  )
  testthat::expect_true(file.exists(file.path(output, "test-results.csv")))
})
