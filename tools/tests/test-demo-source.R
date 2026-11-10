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

testthat::test_that("the default Docker bootstrap includes the shipped response fixes", {
  root <- normalizePath(file.path("..", ".."), winslash = "/")
  library <- withr::local_tempdir()
  observed <- callr::r(
    function(root, library) {
      Sys.setenv(
        R_LIBS_USER = library,
        SHINYOAUTHDB_POSTGRES_OAUTH = "disabled"
      )
      references <- character()
      testthat::local_mocked_bindings(
        install_github = function(repo, ...) {
          references <<- c(references, repo)
          prefix <- "lukakoning/shinyOAuthDB@"
          if (!startsWith(repo, prefix)) {
            stopifnot(requireNamespace("shinyOAuth", quietly = TRUE))
            return(invisible(NULL))
          }
          revision <- substring(repo, nchar(prefix) + 1L)
          stopifnot(grepl("^[0-9a-f]{40}$", revision))
          source <- tempfile("default-demo-source-")
          dir.create(source)
          archive <- tempfile(fileext = ".tar")
          status <- system2(
            Sys.which("git"),
            c(
              "-C",
              shQuote(root),
              "archive",
              "--format=tar",
              shQuote(paste0("--output=", archive)),
              revision
            )
          )
          if (status != 0L) {
            stop("Fetch the pinned demo revision before running this check.")
          }
          utils::untar(archive, exdir = source)
          pkgbuild::rcmd_build_tools(
            "INSTALL",
            c(
              "--no-multiarch",
              "--no-docs",
              paste0("--library=", library),
              source
            )
          )
          invisible(NULL)
        },
        .package = "remotes"
      )
      bootstrap <- new.env(parent = globalenv())
      bootstrap$install.packages <- function(...) invisible(NULL)
      sys.source(file.path(root, "inst", "docker", "install.R"), bootstrap)
      bootstrap$install_demo_runtime("0.0.0.9000")
      package <- find.package("shinyOAuthDB")
      canary <- tempfile(fileext = ".json")
      writeLines('{"proof":"local file"}', canary)
      response <- function(body) {
        httr2::response(
          status_code = 200L,
          headers = list(`Content-Type` = "application/json"),
          body = charToRaw(body)
        )
      }
      parser <- getFromNamespace(".odb_http_json", "shinyOAuthDB")
      parsed <- tryCatch(parser(response(canary), "demo"), error = identity)
      sent <- NULL
      httr2::local_mocked_responses(function(req) {
        if (grepl("libsql.example", req$url, fixed = TRUE)) {
          return(response(
            '{"baton":null,"results":[{"type":"ok","response":{"type":"execute","result":{"cols":[{"name":"n","decltype":"REAL"}],"rows":[[{"type":"float","value":9007199254740994}]],"affected_row_count":0,"last_insert_rowid":null}}},{"type":"ok","response":{"type":"close"}}]}'
          ))
        }
        render <- getFromNamespace("req_body_render", "httr2")
        sent <<- jsonlite::parse_json(render(req))
        response('{"cols":[],"col_types":[],"rows":[],"rowcount":0}')
      })
      provider <- function() function(...) "fixture-token"
      libsql <- getFromNamespace(".odb_libsql_api", "shinyOAuthDB")$new(
        provider,
        "https://libsql.example",
        30,
        NULL
      )
      real <- tryCatch(
        libsql$query("SELECT CAST(9007199254740994 AS REAL)"),
        error = identity
      )
      crate <- getFromNamespace(".odb_cratedb_api", "shinyOAuthDB")$new(
        provider,
        "https://crate.example/_sql",
        NULL,
        30,
        NULL
      )
      values <- list(1.0000000000000002, 1e-100)
      crate$query("SELECT $1, $2", values)
      testthat::local_mocked_bindings(
        dbConnect = function(...) {
          error <- simpleError("native connection failed")
          error$frame <- parent.frame()
          stop(error)
        },
        .package = "DBI"
      )
      credential <- "docker-credential-canary"
      native_error <- tryCatch(
        getFromNamespace(".odb_odbc_connect", "shinyOAuthDB")(
          list(drv = "fixture", pwd = credential)
        ),
        error = identity
      )
      list(
        references = references,
        isolated = identical(
          normalizePath(package, winslash = "/"),
          normalizePath(file.path(library, "shinyOAuthDB"), winslash = "/")
        ),
        rejects_file_response = inherits(
          parsed,
          "shinyOAuthDB_invalid_response"
        ),
        real = if (is.data.frame(real)) real$n else NULL,
        parameters = sent$args,
        expected_parameters = values,
        retains_credential = grepl(
          credential,
          rawToChar(serialize(native_error, NULL, ascii = TRUE)),
          fixed = TRUE
        )
      )
    },
    args = list(root, library),
    libpath = .libPaths()
  )
  testthat::expect_length(observed$references, 1L)
  testthat::expect_true(observed$isolated)
  testthat::expect_true(observed$rejects_file_response)
  testthat::expect_identical(observed$real, 9007199254740994)
  testthat::expect_identical(observed$parameters, observed$expected_parameters)
  testthat::expect_false(observed$retains_credential)
})

testthat::test_that("released Docker demos install the launcher's exact CRAN version", {
  bootstrap <- new.env(parent = globalenv())
  sys.source(file.path("..", "..", "inst", "docker", "install.R"), bootstrap)
  installed <- NULL
  testthat::local_mocked_bindings(
    install_version = function(package, version, upgrade) {
      installed <<- list(package, version, upgrade)
    },
    install_github = function(...) stop("Released demos must use CRAN"),
    .package = "remotes"
  )
  bootstrap$install_demo_package("1.2.3")
  testthat::expect_identical(installed, list("shinyOAuthDB", "1.2.3", "never"))
})

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
