options(repos = c(CRAN = "https://cloud.r-project.org"))
dir.create(Sys.getenv("R_LIBS_USER"), recursive = TRUE, showWarnings = FALSE)
.libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths()))
install.packages(c("remotes", "mirai"), Ncpus = 2L)
# Fixed revisions keep the standalone container independent of local checkouts.
remotes::install_github(
  "lukakoning/shinyOAuth@42176847f6ab82c2b49095f81a829cdd8ce60260",
  upgrade = "never"
)
remotes::install_github(
  "lukakoning/shinyOAuthDB@2097f2ce16395f9bd60fb841afc0c9cd1c5bad7b",
  upgrade = "never"
)
stopifnot(requireNamespace("shinyOAuth"), requireNamespace("shinyOAuthDB"))
