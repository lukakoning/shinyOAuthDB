# Load the actual standalone example through its app definition. Leave worker
# startup and runApp() to interactive use, so server behavior can be tested here.
playground_load_example <- function(filename) {
  path <- testthat::test_path("..", "..", "playground", filename)
  if (!file.exists(path)) {
    testthat::skip("Standalone playground examples require a source checkout.")
  }

  envir <- new.env(parent = globalenv())
  for (expr in parse(path)) {
    if (is.call(expr) && identical(expr[[1L]], as.name("library"))) {
      next
    }

    eval(expr, envir = envir)
    if (
      is.call(expr) &&
        is.symbol(expr[[1L]]) &&
        as.character(expr[[1L]]) %in% c("<-", "=") &&
        identical(expr[[2L]], as.name("app"))
    ) {
      stopifnot(inherits(envir$app, "shiny.appobj"))

      return(envir)
    }
  }

  stop("No standalone Shiny app definition found in ", filename, call. = FALSE)
}
