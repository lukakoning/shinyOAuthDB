integration_provenance <- function(
  root = ".",
  packages = c("shinyOAuth", "shinyOAuthDB", "DBI", "httr2")
) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  hash <- function(file) {
    unclass(as.character(openssl::sha256(readBin(
      file,
      "raw",
      n = file.info(file)$size
    ))))
  }
  files <- c(
    "DESCRIPTION",
    "NAMESPACE",
    "configure",
    "cleanup",
    unlist(lapply(
      c("R", "src", "tests/testthat", "tests/integration", "integration"),
      function(path) {
        paste0(
          path,
          "/",
          list.files(
            file.path(root, path),
            recursive = TRUE,
            full.names = FALSE
          )
        )
      }
    ))
  )
  files <- sort(unique(files[
    !grepl(
      "(^|/)(\\.generated|results|native/build)(/|$)|\\.(o|so|dll|gcda|gcno)$",
      files
    )
  ]))
  files <- files[
    file.exists(file.path(root, files)) & !dir.exists(file.path(root, files))
  ]
  hashes <- stats::setNames(vapply(file.path(root, files), hash, ""), files)
  revision <- Sys.getenv("GITHUB_SHA", unset = NA_character_)
  head <- file.path(root, ".git", "HEAD")
  if (is.na(revision) && file.exists(head)) {
    ref <- readLines(head, warn = FALSE, n = 1L)
    if (startsWith(ref, "ref: ")) {
      path <- file.path(root, ".git", sub("^ref: ", "", ref))
      if (file.exists(path)) revision <- readLines(path, warn = FALSE, n = 1L)
    } else {
      revision <- ref
    }
  }
  if (!is.na(revision) && !grepl("^[0-9a-f]{40,64}$", revision)) {
    revision <- NA_character_
  }
  versions <- lapply(packages, function(package) {
    path <- find.package(package, lib.loc = .libPaths(), quiet = TRUE)
    if (length(path)) {
      as.character(utils::packageVersion(package, lib.loc = .libPaths()))
    } else {
      NA_character_
    }
  })
  list(
    revision = revision,
    source_sha256 = unclass(as.character(openssl::sha256(charToRaw(paste(
      names(hashes),
      hashes,
      collapse = "\n"
    ))))),
    source_files = as.list(hashes),
    fixture_version = 1L,
    R = as.character(getRversion()),
    platform = R.version$platform,
    dependencies = stats::setNames(versions, packages)
  )
}
