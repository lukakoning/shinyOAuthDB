install_demo_source <- function(path, library = .libPaths()[[1L]]) {
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
  package <- find.package("shinyOAuthDB", lib.loc = library)
  writeLines(actual, file.path(package, "Meta", "demo-source.sha256"))
  invisible(actual)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  install_demo_source(
    if (length(args)) args[[1L]] else "/tmp/demo-package",
    if (length(args) > 1L) args[[2L]] else .libPaths()[[1L]]
  )
}
