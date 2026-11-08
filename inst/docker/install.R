options(repos = c(CRAN = "https://cloud.r-project.org"))
dir.create(Sys.getenv("R_LIBS_USER"), recursive = TRUE, showWarnings = FALSE)
.libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths()))
install.packages("remotes", Ncpus = 2L)
# Fixed revisions keep the standalone container independent of local checkouts.
remotes::install_github(
  "lukakoning/shinyOAuth@42176847f6ab82c2b49095f81a829cdd8ce60260",
  upgrade = "never"
)
remotes::install_github(
  "lukakoning/shinyOAuthDB@3d567584ab6ec518ba81e835a61ad86fe8ae282d",
  upgrade = "never"
)
stopifnot(requireNamespace("shinyOAuth"), requireNamespace("shinyOAuthDB"))
