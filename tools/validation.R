validation_dependencies <- function(path = "DESCRIPTION") {
  description <- read.dcf(path)
  fields <- intersect(c("Imports", "Suggests"), colnames(description))
  declarations <- trimws(unlist(strsplit(
    paste(description[1L, fields], collapse = ","),
    ","
  )))
  packages <- sub("[[:space:]]*\\(.*$", "", declarations)
  minimum <- ifelse(
    grepl("\\(", declarations),
    sub("^.*\\(>= *([^ )]+)\\)$", "\\1", declarations),
    "0"
  )
  if (any(grepl("[()]", minimum))) {
    stop("Unsupported dependency version constraint.", call. = FALSE)
  }
  stats::setNames(minimum, packages)
}

validation_check_dependencies <- function(
  packages = validation_dependencies()
) {
  missing <- vapply(
    names(packages),
    function(package) {
      !requireNamespace(package, quietly = TRUE) ||
        utils::compareVersion(
          as.character(utils::packageVersion(package)),
          packages[[package]]
        ) <
          0L
    },
    logical(1)
  )
  if (any(missing)) {
    stop(
      "Full validation requires installed dependencies at their declared minimum versions: ",
      paste(
        paste0(names(packages)[missing], " (>= ", packages[missing], ")"),
        collapse = ", "
      ),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

validation_check_exact_dependencies <- function(packages) {
  validation_check_dependencies(packages)
  actual <- vapply(
    names(packages),
    function(package) {
      as.character(utils::packageVersion(package))
    },
    ""
  )
  if (!identical(actual, packages)) {
    stop(
      "Compatibility tests require exact dependency versions: ",
      paste(paste0(names(packages), " == ", packages), collapse = ", "),
      call. = FALSE
    )
  }
  invisible(actual)
}

validation_source <- function(path = ".") {
  root <- normalizePath(path, winslash = "/", mustWork = TRUE)
  git <- Sys.which("git")
  git_read <- function(args) {
    if (!nzchar(git)) {
      return(NULL)
    }
    value <- suppressWarnings(system2(
      git,
      c("-C", shQuote(root), "-c", "core.quotepath=false", args),
      stdout = TRUE,
      stderr = FALSE
    ))
    if (is.null(attr(value, "status"))) value else NULL
  }
  top <- git_read(c("rev-parse", "--show-toplevel"))
  repository <- length(top) == 1L &&
    identical(normalizePath(top, winslash = "/", mustWork = TRUE), root)
  revision <- if (repository) {
    git_read(c("rev-parse", "HEAD"))
  } else {
    Sys.getenv("GITHUB_SHA", unset = NA_character_)
  }
  if (
    length(revision) != 1L ||
      is.na(revision) ||
      !grepl("^[0-9a-f]{40,64}$", revision)
  ) {
    revision <- NA_character_
  }
  files <- if (repository) {
    git_read(c(
      "ls-files",
      "--cached",
      "--others",
      "--exclude-standard",
      "--",
      "."
    ))
  } else {
    directories <- c(
      "R",
      "src",
      "man",
      "tests",
      "vignettes",
      "inst",
      "tools",
      "integration",
      "docs",
      ".github"
    )
    c(
      c(
        "DESCRIPTION",
        "NAMESPACE",
        "LICENSE",
        "NEWS.md",
        "README.md",
        "configure",
        "configure.win",
        "cleanup",
        ".Rbuildignore",
        ".gitattributes",
        "_pkgdown.yml",
        "air.toml",
        "jarl.toml"
      ),
      unlist(
        lapply(directories, function(directory) {
          paste0(
            directory,
            "/",
            list.files(
              file.path(root, directory),
              recursive = TRUE,
              all.files = TRUE
            )
          )
        }),
        use.names = FALSE
      )
    )
  }
  if (!repository) {
    files <- files[
      file.exists(file.path(root, files)) &
        !dir.exists(file.path(root, files))
    ]
    files <- files[
      !grepl(
        "(^|/)([.]generated|results|[.]env|[.]Renviron)(/|$)|[.](o|so|dll|gcda|gcno)$|^src/Makevars$",
        files
      )
    ]
  }
  files <- sort(unique(files))
  hashes <- stats::setNames(
    vapply(
      file.path(root, files),
      function(path) {
        if (!file.exists(path) || dir.exists(path)) {
          return(NA_character_)
        }
        connection <- file(path, "rb")
        on.exit(close(connection), add = TRUE)
        unclass(as.character(openssl::sha256(connection)))
      },
      ""
    ),
    files
  )
  status <- if (repository) {
    git_read(c("status", "--porcelain", "--untracked-files=all", "--", "."))
  }
  list(
    root = root,
    revision = revision,
    dirty = if (repository && !is.null(status)) length(status) > 0L else NA,
    source_sha256 = unclass(as.character(openssl::sha256(charToRaw(enc2utf8(
      paste(names(hashes), hashes, collapse = "\n")
    ))))),
    source_files = as.list(hashes)
  )
}

validation_check_source <- function(before, after, output = NULL) {
  changed <- !is.null(before) &&
    !identical(before$source_sha256, after$source_sha256)
  if (!is.null(output)) {
    jsonlite::write_json(
      list(before = before, after = after, changed = changed),
      file.path(output, "source-provenance.json"),
      auto_unbox = TRUE,
      pretty = TRUE,
      null = "null"
    )
  }
  if (changed) {
    stop(
      "Package source changed during validation; rerun against a stable source tree.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

validation_check_results <- function(
  counts,
  output,
  packages = validation_dependencies(),
  source_before = NULL
) {
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  details <- counts[!vapply(counts, is.list, logical(1))]
  utils::write.csv(
    details,
    file.path(output, "test-results.csv"),
    row.names = FALSE
  )
  source_after <- validation_source(
    if (is.null(source_before)) "." else source_before$root
  )
  summary <- list(
    revision = source_after$revision,
    dirty = source_after$dirty,
    source_sha256 = source_after$source_sha256,
    R = as.character(getRversion()),
    platform = R.version$platform,
    scenarios = nrow(counts),
    passed = sum(counts$passed),
    failed = sum(counts$failed),
    errors = sum(counts$error),
    warnings = sum(counts$warning),
    skipped = sum(counts$skipped)
  )
  jsonlite::write_json(
    summary,
    file.path(output, "test-summary.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  versions <- vapply(
    names(packages),
    function(package) {
      as.character(utils::packageVersion(package))
    },
    ""
  )
  jsonlite::write_json(
    as.list(versions),
    file.path(output, "dependency-versions.json"),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  cat(
    "\nPassing assertions:",
    summary$passed,
    "; skipped scenarios:",
    summary$skipped,
    "\n"
  )
  validation_check_source(source_before, source_after, output)
  if (
    !nrow(counts) ||
      !summary$passed ||
      anyNA(unlist(summary[c(
        "passed",
        "failed",
        "errors",
        "warnings",
        "skipped"
      )])) ||
      any(
        counts$failed > 0L | counts$error | counts$warning > 0L | counts$skipped
      )
  ) {
    stop(
      "Full source tests require passing assertions and zero failures, errors, warnings or skips.",
      call. = FALSE
    )
  }
  invisible(summary)
}
