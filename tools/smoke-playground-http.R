# Short-lived local HTTP smoke server. No credentials and no cloud calls.
# Run from the repository root, then GET http://127.0.0.1:18199 within 20 seconds.
pkgload::load_all(".", quiet = TRUE)

# Evaluate the real example through app creation, before its interactive runApp.
example <- new.env(parent = globalenv())
for (expr in parse("playground/example-offline.R")) {
  eval(expr, envir = example)
  if (
    is.call(expr) &&
      identical(expr[[1L]], as.name("<-")) &&
      identical(expr[[2L]], as.name("app"))
  ) {
    break
  }
}

later::later(function() shiny::stopApp(), delay = 20)
shiny::runApp(
  example$app,
  host = "127.0.0.1",
  port = 18199,
  launch.browser = FALSE
)
