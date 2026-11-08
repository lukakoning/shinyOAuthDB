demo_source_prepare <- function(root, path, output) {
  archive <- pkgbuild::build(
    root,
    dest_path = output,
    vignettes = FALSE,
    manual = FALSE,
    quiet = TRUE
  )
  destination <- file.path(path, "package-source")
  dir.create(destination, recursive = TRUE, showWarnings = FALSE)
  copied <- file.path(destination, "shinyOAuthDB.tar.gz")
  if (!file.copy(archive, copied, overwrite = TRUE)) {
    stop(
      "Could not stage the package source for the Docker demo.",
      call. = FALSE
    )
  }
  hash <- unclass(as.character(openssl::sha256(readBin(
    copied,
    "raw",
    n = file.info(copied)$size
  ))))
  writeLines(hash, file.path(destination, "source.sha256"))
  list(
    source_sha256 = hash,
    version = unname(read.dcf(file.path(root, "DESCRIPTION"))[1L, "Version"])
  )
}

demo_source_identity <- function(docker, project, expected) {
  run <- function(args) {
    value <- system2(
      docker,
      vapply(args, shQuote, ""),
      stdout = TRUE,
      stderr = TRUE
    )
    if (!is.null(attr(value, "status"))) {
      stop("Could not inspect the Docker demo package runtime.", call. = FALSE)
    }
    value
  }
  container <- run(c(
    "ps",
    "--filter",
    paste0("label=com.docker.compose.project=", project),
    "--filter",
    "label=com.docker.compose.service=app",
    "--format",
    "{{.ID}}"
  ))
  if (length(container) != 1L || !grepl("^[0-9a-f]{12,64}$", container)) {
    stop("Expected one running Docker demo app container.", call. = FALSE)
  }
  identity <- run(c(
    "exec",
    container,
    "Rscript",
    "--vanilla",
    "-e",
    paste0(
      'cat(readLines(system.file("Meta", "demo-source.sha256", ',
      'package = "shinyOAuthDB", mustWork = TRUE)), ',
      'as.character(packageVersion("shinyOAuthDB")), sep = "\\n")'
    )
  ))
  if (!identical(identity, c(expected$source_sha256, expected$version))) {
    stop(
      "The Docker demo app is not using the candidate package source.",
      call. = FALSE
    )
  }
  list(
    container = container,
    source_sha256 = identity[[1L]],
    version = identity[[2L]]
  )
}
