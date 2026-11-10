install_demo_package <- function(version) {
  parts <- strsplit(version, ".", fixed = TRUE)[[1L]]
  if (length(parts) > 3L && as.integer(tail(parts, 1L)) >= 9000L) {
    # The development snapshot includes the native credential-frame fixes.
    remotes::install_github(
      "lukakoning/shinyOAuthDB@c0d954d5afef9bc2d0aecf0c01a588371d7da64c",
      upgrade = "never"
    )
  } else {
    remotes::install_version(
      "shinyOAuthDB",
      version = version,
      upgrade = "never"
    )
  }
}

install_demo_runtime <- function(version) {
  stopifnot(length(version) == 1L, !is.na(version))
  package_version(version)
  options(repos = c(CRAN = "https://cloud.r-project.org"))
  dir.create(Sys.getenv("R_LIBS_USER"), recursive = TRUE, showWarnings = FALSE)
  .libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths()))
  install.packages(c("remotes", "mirai", "codetools", "shinyOAuth"), Ncpus = 2L)
  install_demo_package(version)
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
  install_demo_runtime(readLines("/tmp/demo-version", warn = FALSE))
}
