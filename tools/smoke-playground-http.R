# Short-lived local HTTP smoke server. No credentials and no cloud calls.
# Run from the repository root, then GET http://127.0.0.1:18199 within 20 seconds.
pkgload::load_all(".", quiet = TRUE)
source("playground/shared.R", local = TRUE)
source("playground/offline.R", local = TRUE)
later::later(function() shiny::stopApp(), delay = 20)
shiny::runApp(playground_offline_app(), host = "127.0.0.1", port = 18199, launch.browser = FALSE)
