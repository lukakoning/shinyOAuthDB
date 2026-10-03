# Run from the repository root; only shiny, shinyOAuthDB and RSQLite are needed.
source("playground/shared.R", local = TRUE)
source("playground/offline.R", local = TRUE)
shiny::runApp(playground_offline_app(), host = "127.0.0.1", port = 8100, launch.browser = FALSE)
