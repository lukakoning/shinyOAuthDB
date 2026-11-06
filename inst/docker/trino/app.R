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
  h2("trino demo"),
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

  con <- oauth_db_trino(
    auth$connection, host = "https://localhost:18444",
    catalog = "memory", schema = "reporting",
    user = function() req(auth$token@userinfo$preferred_username),
    ca_bundle = "/fixtures/tls/ca-cert.pem"
  )
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, "SELECT marker FROM visible_rows ORDER BY id")
  })
}

shinyApp(ui, server, uiPattern = ".*")
