demo_source_script <- function() {
  environment <- new.env(parent = globalenv())
  sys.source(
    system.file(
      "docker",
      "package-source",
      "install.R",
      package = "shinyOAuthDB"
    ),
    envir = environment
  )
  environment
}

test_that("demo source references retain the installed GitHub repository and commit", {
  description <- list(
    RemoteType = "github",
    RemoteHost = "api.github.com",
    RemoteUsername = "a-fork",
    RemoteRepo = "shinyOAuthDB",
    RemoteSha = strrep("A", 40L)
  )
  expect_identical(
    .odb_demo_package_reference(description),
    paste0("a-fork/shinyOAuthDB@", strrep("a", 40L))
  )
  for (name in names(description)) {
    missing <- description
    missing[[name]] <- NULL
    if (name != "RemoteHost") expect_null(.odb_demo_package_reference(missing))
  }
  for (field in list(
    list(RemoteType = "git"),
    list(RemoteHost = "github.example"),
    list(RemoteUsername = "other/repository"),
    list(RemoteSha = "main"),
    list(RemoteSha = c(strrep("a", 40L), strrep("b", 40L)))
  )) {
    invalid <- description
    invalid[names(field)] <- field
    expect_null(.odb_demo_package_reference(invalid))
  }
})

test_that("saved demo source metadata follows package updates while keeping app edits", {
  reference <- paste0("lukakoning/shinyOAuthDB@", strrep("a", 40L))
  local_mocked_bindings(.odb_demo_package_reference = function() reference)
  path <- withr::local_tempdir()
  suppressMessages(oauth_db_demo("postgrest", action = "files", path = path))
  source <- file.path(path, "package-source")
  expect_identical(readLines(file.path(source, "github-ref")), reference)
  expect_silent(.odb_demo_source_ready(path))
  writeLines("# edited app", file.path(path, "postgrest", "app.R"))
  reference <- paste0("lukakoning/shinyOAuthDB@", strrep("b", 40L))
  suppressMessages(oauth_db_demo("postgrest", action = "files", path = path))
  expect_identical(readLines(file.path(source, "github-ref")), reference)
  expect_identical(
    readLines(file.path(path, "postgrest", "app.R")),
    "# edited app"
  )
  writeLines("previous archive", file.path(source, "shinyOAuthDB.tar.gz"))
  writeLines(strrep("a", 64L), file.path(source, "source.sha256"))
  suppressMessages(oauth_db_demo("postgrest", action = "files", path = path))
  expect_false(file.exists(file.path(source, "shinyOAuthDB.tar.gz")))
  expect_false(file.exists(file.path(source, "source.sha256")))
  expect_identical(readLines(file.path(source, "github-ref")), reference)
  reference <- NULL
  suppressMessages(oauth_db_demo("postgrest", action = "files", path = path))
  expect_false(file.exists(file.path(source, "github-ref")))
  expect_error(
    .odb_demo_source_ready(path),
    "Supply package_source",
    fixed = TRUE
  )
  unlink(file.path(source, "bootstrap-version"))
  expect_error(.odb_demo_source_ready(path), "new empty path", fixed = TRUE)
})

test_that("local development demos stage source archives with a content fingerprint", {
  local_mocked_bindings(.odb_demo_package_reference = function() NULL)
  path <- withr::local_tempdir()
  archive <- tempfile(fileext = ".tar.gz")
  withr::defer(unlink(archive))
  source <- withr::local_tempdir()
  dir.create(file.path(source, "shinyOAuthDB"))
  writeLines(
    c("Package: shinyOAuthDB", "Version: 0.0.0.9000"),
    file.path(source, "shinyOAuthDB", "DESCRIPTION")
  )
  withr::with_dir(
    source,
    utils::tar(
      archive,
      "shinyOAuthDB",
      compression = "gzip",
      tar = "internal"
    )
  )
  suppressMessages(oauth_db_demo(
    "postgrest",
    action = "files",
    path = path,
    package_source = archive
  ))
  destination <- file.path(path, "package-source", "shinyOAuthDB.tar.gz")
  expect_identical(
    readBin(destination, "raw", file.info(destination)$size),
    readBin(archive, "raw", file.info(archive)$size)
  )
  expect_silent(.odb_demo_source_ready(path))
  expect_match(
    readLines(file.path(path, "package-source", "source.sha256")),
    "^[0-9a-f]{64}$"
  )
  expect_error(
    oauth_db_demo(action = "files", path = path, package_source = source),
    "existing R source archive",
    fixed = TRUE
  )
  expect_error(
    oauth_db_demo(
      action = "files",
      path = path,
      package_source = paste0(archive, "-missing")
    ),
    "existing R source archive",
    fixed = TRUE
  )
})

test_that("demo startup rejects a stale image even when its version is unchanged", {
  library <- withr::local_tempdir()
  package <- file.path(library, "shinyOAuthDB")
  dir.create(file.path(package, "Meta"), recursive = TRUE)
  writeLines(
    c("Package: shinyOAuthDB", "Version: 0.0.0.9000"),
    file.path(package, "DESCRIPTION")
  )
  path <- withr::local_tempdir()
  writeLines("0.0.0.9000", file.path(path, "version"))
  reference <- paste0("lukakoning/shinyOAuthDB@", strrep("a", 40L))
  writeLines(reference, file.path(path, "github-ref"))
  script <- demo_source_script()
  expect_error(
    script$verify_demo_source(path, library),
    "different package source",
    fixed = TRUE
  )
  writeLines(reference, file.path(package, "Meta", "demo-source.github-ref"))
  expect_true(script$verify_demo_source(path, library))
  writeLines(paste0(reference, "b"), file.path(path, "github-ref"))
  expect_error(
    script$verify_demo_source(path, library),
    "Rebuild with build = TRUE",
    fixed = TRUE
  )
  writeLines("1.2.3", file.path(path, "version"))
  expect_error(
    script$verify_demo_source(path, library),
    "different package version",
    fixed = TRUE
  )
  writeLines("0.0.0.9000", file.path(path, "version"))
  unlink(file.path(path, "github-ref"))
  expect_error(
    script$verify_demo_source(path, library),
    "no source identity",
    fixed = TRUE
  )
  hash <- strrep("c", 64L)
  writeLines(hash, file.path(path, "source.sha256"))
  writeLines(hash, file.path(package, "Meta", "demo-source.sha256"))
  expect_true(script$verify_demo_source(path, library))
  writeLines(strrep("d", 64L), file.path(path, "source.sha256"))
  expect_error(
    script$verify_demo_source(path, library),
    "different package source",
    fixed = TRUE
  )
})

test_that("development Docker bootstraps never choose an unrelated snapshot", {
  bootstrap <- new.env(parent = globalenv())
  sys.source(
    system.file("docker", "install.R", package = "shinyOAuthDB"),
    bootstrap
  )
  installed <- NULL
  package <- withr::local_tempdir()
  dir.create(file.path(package, "Meta"))
  bootstrap$find.package <- function(...) package
  local_mocked_bindings(
    install_github = function(repo, ...) {
      installed <<- repo
    },
    .package = "remotes"
  )
  expect_error(
    bootstrap$install_demo_package("0.0.0.9000"),
    "exact GitHub revision",
    fixed = TRUE
  )
  expect_null(installed)
  reference <- paste0("a-fork/shinyOAuthDB@", strrep("e", 40L))
  bootstrap$install_demo_package("0.0.0.9000", reference)
  expect_identical(installed, reference)
  expect_identical(
    readLines(file.path(package, "Meta", "demo-source.github-ref")),
    reference
  )
  for (invalid in list(
    "",
    "owner/repository@main",
    NA_character_,
    c(reference, reference)
  )) {
    expect_error(
      bootstrap$install_demo_package("0.0.0.9000", invalid),
      "Invalid demo GitHub",
      fixed = TRUE
    )
  }
})
