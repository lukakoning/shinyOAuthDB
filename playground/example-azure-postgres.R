# Query Azure PostgreSQL as the signed-in user; see playground/README.md for setup.
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

client <- oauth_db_microsoft_client(
  services = "postgres",
  tenant_id = Sys.getenv("OAUTHDB_TENANT_ID"),
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = Sys.getenv("OAUTHDB_REDIRECT_URI", "http://localhost:8100")
)

ui <- oauth_ui(
  fluidPage(
    titlePanel("Azure PostgreSQL"),
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

  con <- oauth_db_azure_postgres(
    auth$connection,
    host = Sys.getenv("OAUTHDB_POSTGRES_HOST"),
    dbname = Sys.getenv("OAUTHDB_DATABASE"),
    user = Sys.getenv("OAUTHDB_POSTGRES_USER"),
    sslrootcert = Sys.getenv("OAUTHDB_POSTGRES_SSLROOTCERT")
  )
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(
      connection,
      "SELECT table_schema, table_name FROM information_schema.tables LIMIT 20"
    )
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
