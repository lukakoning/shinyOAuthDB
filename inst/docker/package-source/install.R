install_demo_source <- function(
  path,
  library = .libPaths()[[1L]],
  install = NULL
) {
  archive <- file.path(path, "shinyOAuthDB.tar.gz")
  manifest <- file.path(path, "source.sha256")
  if (!file.exists(archive) && !file.exists(manifest)) {
    return(invisible(NULL))
  }
  if (!file.exists(archive) || !file.exists(manifest)) {
    stop(
      "The demo package source archive and hash must both be present.",
      call. = FALSE
    )
  }
  expected <- readLines(manifest, warn = FALSE)
  actual <- unclass(as.character(openssl::sha256(readBin(
    archive,
    "raw",
    n = file.info(archive)$size
  ))))
  if (length(expected) != 1L || !grepl("^[0-9a-f]{64}$", expected)) {
    stop("The demo package source hash is invalid.", call. = FALSE)
  }
  if (!identical(actual, expected)) {
    stop(
      "The demo package source hash does not match the archive.",
      call. = FALSE
    )
  }
  if (is.null(install)) {
    windows <- .Platform$OS.type == "windows"
    command <- file.path(R.home("bin"), if (windows) "Rcmd.exe" else "R")
    status <- system2(
      command,
      c(
        if (!windows) "CMD",
        "INSTALL",
        shQuote(paste0("--library=", library)),
        shQuote(archive)
      )
    )
    if (status != 0L) {
      stop("The demo package source could not be installed.", call. = FALSE)
    }
  } else {
    install(archive, library)
  }
  package <- find.package("shinyOAuthDB", lib.loc = library)
  writeLines(actual, file.path(package, "Meta", "demo-source.sha256"))
  invisible(actual)
}

verify_demo_source <- function(path, library = .libPaths()) {
  package <- find.package("shinyOAuthDB", lib.loc = library)
  expected_version <- readLines(file.path(path, "version"), warn = FALSE)
  actual_version <- as.character(utils::packageVersion(
    "shinyOAuthDB",
    lib.loc = library
  ))
  if (!identical(expected_version, actual_version)) {
    stop(
      "The demo image has a different package version. Rebuild with build = TRUE.",
      call. = FALSE
    )
  }
  for (name in c("source.sha256", "github-ref")) {
    expected <- file.path(path, name)
    if (file.exists(expected)) {
      marker <- if (name == "source.sha256") {
        "demo-source.sha256"
      } else {
        "demo-source.github-ref"
      }
      actual <- file.path(package, "Meta", marker)
      if (
        !file.exists(actual) ||
          !identical(
            readLines(expected, warn = FALSE),
            readLines(actual, warn = FALSE)
          )
      ) {
        stop(
          "The demo image has different package source. Rebuild with build = TRUE.",
          call. = FALSE
        )
      }
      return(invisible(TRUE))
    }
  }
  parts <- strsplit(actual_version, ".", fixed = TRUE)[[1L]]
  if (length(parts) > 3L && as.integer(tail(parts, 1L)) >= 9000L) {
    stop(
      "The development demo has no source identity. Rebuild with a GitHub revision or source archive.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  install_demo_source(
    if (length(args)) args[[1L]] else "/tmp/demo-package",
    if (length(args) > 1L) args[[2L]] else .libPaths()[[1L]]
  )
}
