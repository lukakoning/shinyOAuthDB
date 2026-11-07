args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 3L)
options(shiny.autoreload = TRUE)
result <- shiny::runApp(
  args[[1L]],
  host = "127.0.0.1",
  port = as.integer(args[[2L]]),
  launch.browser = identical(args[[3L]], "TRUE")
)
if (identical(result, "setup")) {
  quit(save = "no", status = 10L)
}
