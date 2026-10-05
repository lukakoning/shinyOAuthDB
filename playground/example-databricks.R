# Complete app; configure the environment described in playground/README.md.
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

host <- sub("/$", "", sub("^https://", "", Sys.getenv("OAUTHDB_DATABRICKS_HOST")))
client <- oauth_db_databricks_client(
  host = host, client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = Sys.getenv("OAUTHDB_REDIRECT_URI", "http://localhost:8100")
)

ui <- oauth_ui(fluidPage(
  titlePanel("Databricks SQL"),
  actionButton("login", "Sign in"),
  actionButton("logout", "Sign out"),
  verbatimTextOutput("rows")
), id = "auth", client = client)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  bearer <- oauth_db_token(auth$connection, required_scopes = "all-apis")
  output$rows <- renderPrint({
    brickster::db_sql_query(
      host = host, warehouse_id = Sys.getenv("OAUTHDB_DATABRICKS_WAREHOUSE"),
      statement = "SELECT current_user() AS database_user",
      disposition = "INLINE", show_progress = FALSE, token = bearer()
    )
  })
}

app <- shinyApp(ui, server, uiPattern = ".*")
if (interactive()) runApp(app, port = as.integer(Sys.getenv("OAUTHDB_PORT", "8100")),
                          launch.browser = FALSE)
