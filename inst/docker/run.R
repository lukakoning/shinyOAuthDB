options(shinyOAuth.allowed_hosts = c("localhost", "127.0.0.1", "::1"))
backend <- Sys.getenv("OAUTHDB_DEMO")
prepare <- file.path(backend, "prepare.R")
if (file.exists(prepare)) {
  source(prepare)
}
app <- source(file.path(backend, "app.R"))$value
shiny::runApp(app, host = "0.0.0.0", port = 18100L, launch.browser = FALSE)
