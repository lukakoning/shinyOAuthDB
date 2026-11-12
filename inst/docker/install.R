install_demo_package <- function(
  version,
  github_ref = NULL,
  source_path = NULL
) {
  if (!is.null(source_path)) {
    installer <- new.env(parent = globalenv())
    sys.source(file.path(source_path, "install.R"), envir = installer)
    hash <- installer$install_demo_source(
      source_path,
      install = function(archive, library) {
        remotes::install_local(
          archive,
          lib = library,
          dependencies = NA,
          upgrade = "never"
        )
      }
    )
    if (!is.null(hash)) return(invisible(hash))
  }
  parts <- strsplit(version, ".", fixed = TRUE)[[1L]]
  development <- length(parts) > 3L && as.integer(tail(parts, 1L)) >= 9000L
  if (!is.null(github_ref)) {
    if (
      !is.character(github_ref) ||
        length(github_ref) != 1L ||
        is.na(github_ref) ||
        !grepl(
          "^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*@([0-9a-f]{40}|[0-9a-f]{64})$",
          github_ref
        )
    ) {
      stop("Invalid demo GitHub source reference.", call. = FALSE)
    }
    remotes::install_github(github_ref, upgrade = "never")
    package <- find.package("shinyOAuthDB")
    writeLines(github_ref, file.path(package, "Meta", "demo-source.github-ref"))
  } else if (development) {
    stop(
      "A development Docker demo needs the launcher's exact GitHub revision or a staged source archive.",
      call. = FALSE
    )
  } else {
    remotes::install_version(
      "shinyOAuthDB",
      version = version,
      upgrade = "never"
    )
  }
}

install_demo_runtime <- function(version, source_path = NULL) {
  stopifnot(length(version) == 1L, !is.na(version))
  package_version(version)
  options(repos = c(CRAN = "https://cloud.r-project.org"))
  dir.create(Sys.getenv("R_LIBS_USER"), recursive = TRUE, showWarnings = FALSE)
  .libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths()))
  install.packages(c("remotes", "mirai", "codetools", "shinyOAuth"), Ncpus = 2L)
  reference <- if (
    !is.null(source_path) && file.exists(file.path(source_path, "github-ref"))
  ) {
    readLines(file.path(source_path, "github-ref"), warn = FALSE)
  } else {
    NULL
  }
  install_demo_package(version, reference, source_path)
  stopifnot(
    requireNamespace("shinyOAuth"),
    requireNamespace("shinyOAuthDB"),
    requireNamespace("mirai"),
    utils::packageVersion("shinyOAuth") >= package_version("0.7.0"),
    utils::packageVersion("shinyOAuthDB") == package_version(version),
    utils::packageVersion("mirai") >= package_version("2.5.1"),
    "oauth_db_task" %in% getNamespaceExports("shinyOAuthDB")
  )
}

if (sys.nframe() == 0L) {
  source_path <- "/tmp/demo-package"
  install_demo_runtime(
    readLines(file.path(source_path, "version"), warn = FALSE),
    source_path
  )
}
