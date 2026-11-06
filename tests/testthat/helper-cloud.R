cloud_demo_path <- function() {
  file.path(withr::local_tempdir(.local_envir = parent.frame()), "cloud demo with spaces")
}
