# Query BigQuery with Google sign-in; see playground/README.md for setup.
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

client <- oauth_db_bigquery_client(
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = Sys.getenv("OAUTHDB_REDIRECT_URI", "http://localhost:8100")
)

ui <- oauth_ui(
  fluidPage(
    actionButton("login", "Sign in"),
    actionButton("logout", "Sign out"),
    tableOutput("rows")
  ),
  id = "auth",
  client = client
)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  bigquery <- oauth_db_bigquery_api(
    auth$connection,
    project = Sys.getenv("OAUTHDB_BIGQUERY_PROJECT"),
    location = Sys.getenv("OAUTHDB_BIGQUERY_LOCATION", "EU")
  )
  output$rows <- renderTable({
    bigquery$query("SELECT SESSION_USER() AS database_user")
  })
}

app <- shinyApp(ui, server, uiPattern = ".*")
if (interactive()) {
  runApp(
    app,
    port = as.integer(Sys.getenv("OAUTHDB_PORT", "8100")),
    launch.browser = FALSE
  )
}
