library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

issuer <- "https://localhost:18443/realms/shinyoauthdb"
client <- oauth_client(
  oauth_provider_oidc_discover(issuer),
  client_id = "shiny-db", client_secret = "demo-client-secret",
  redirect_uri = "http://localhost:18100",
  scopes = c("openid", "profile", "database.read")
)

ui <- oauth_ui(fluidPage(
  h2("postgrest demo"),
  actionButton("login", "Sign in"),
  actionButton("logout", "Sign out"),
  tableOutput("rows"),
  actionButton("stop", "Stop demo")
), id = "auth", client = client)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())
  observeEvent(input$stop, stopApp())

  postgrest <- oauth_db_postgrest_api(
    auth$connection, url = "https://localhost:18444",
    ca_bundle = "/fixtures/tls/ca-cert.pem"
  )
  output$rows <- renderTable({
    postgrest$select("visible_rows", order = "row_id.asc")
  })
}

shinyApp(ui, server, uiPattern = ".*")
