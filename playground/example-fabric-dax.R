# Complete app; configure the environment described in playground/README.md.
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

client <- oauth_db_microsoft_client(
  services = "dax",
  tenant_id = Sys.getenv("OAUTHDB_TENANT_ID"),
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = Sys.getenv("OAUTHDB_REDIRECT_URI", "http://localhost:8100")
)

ui <- oauth_ui(fluidPage(
  titlePanel("Fabric DAX"),
  actionButton("login", "Sign in"),
  actionButton("logout", "Sign out"),
  verbatimTextOutput("rows")
), id = "auth", client = client)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  token <- oauth_db_fabric(auth$connection, service = "dax")
  output$rows <- renderPrint({
    credential <- token()
    fabricQueryR::fabric_pbi_dax_query(
      workspace_id = Sys.getenv("OAUTHDB_FABRIC_WORKSPACE"),
      dataset_id = Sys.getenv("OAUTHDB_FABRIC_MODEL"),
      dax = "EVALUATE ROW(\"message\", \"Hello from DAX\")", token = credential
    )
  })
}

app <- shinyApp(ui, server, uiPattern = ".*")
if (interactive()) runApp(app, port = as.integer(Sys.getenv("OAUTHDB_PORT", "8100")),
                          launch.browser = FALSE)
