# Run with RETICULATE_PYTHON set to Python with the fixture requirements.
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments)) {
  .libPaths(c(arguments, .libPaths()))
}
Sys.setenv(LC_ALL = "C", LANG = "C", LANGUAGE = "en")
root <- normalizePath(".", winslash = "/", mustWork = TRUE)
python <- Sys.getenv("RETICULATE_PYTHON")
if (!nzchar(python) || !file.exists(python)) {
  stop(
    "Set RETICULATE_PYTHON to Python with integration/mongodb-oidc/requirements.txt installed.",
    call. = FALSE
  )
}
library_path <- tempfile("oauthdb-mongodb-library-")
dir.create(library_path)
.libPaths(c(library_path, .libPaths()))
Sys.setenv(
  R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
  R_LIBS_USER = paste(.libPaths(), collapse = .Platform$path.sep),
  SHINYOAUTHDB_POSTGRES_OAUTH = "disabled"
)
pkgbuild::rcmd_build_tools(
  "INSTALL",
  c(paste0("--library=", library_path), root)
)
driver_status <- system2(
  python,
  shQuote(file.path(root, "integration/mongodb-oidc/test-driver.py"))
)
if (driver_status != 0L) {
  stop("MongoDB Python boundary tests failed.", call. = FALSE)
}
status <- system2(
  python,
  c(
    shQuote(file.path(root, "integration/mongodb-oidc/run.py")),
    "--root",
    shQuote(root),
    "--rscript",
    shQuote(file.path(R.home("bin"), "Rscript"))
  )
)
if (status != 0L) {
  stop("MongoDB native validation failed.", call. = FALSE)
}
