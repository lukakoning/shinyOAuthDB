options(repos = c(CRAN = "https://cloud.r-project.org"))
dir.create(Sys.getenv("R_LIBS_USER"), recursive = TRUE, showWarnings = FALSE)
.libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths()))
install.packages(c("remotes", "mirai", "codetools"), Ncpus = 2L)
# Fixed revisions keep the standalone container independent of local checkouts.
remotes::install_github(
  "lukakoning/shinyOAuth@42176847f6ab82c2b49095f81a829cdd8ce60260",
  upgrade = "never"
)
remotes::install_github(
  "lukakoning/shinyOAuthDB@2ad177f82fbe5b9fe37ddf28bc7a8bf3deb89d29",
  upgrade = "never"
)
stopifnot(
  requireNamespace("shinyOAuth"),
  requireNamespace("shinyOAuthDB"),
  requireNamespace("mirai"),
  utils::packageVersion("mirai") >= package_version("2.5.1"),
  "oauth_db_task" %in% getNamespaceExports("shinyOAuthDB")
)
