library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

issuer <- "https://localhost:18443/realms/shinyoauthdb"
client <- oauth_client(
  oauth_provider_oidc_discover(issuer),
  client_id = "shiny-db",
  client_secret = "demo-client-secret",
  redirect_uri = "http://localhost:18100",
  scopes = c("openid", "profile", "database.read")
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

  con <- oauth_db_postgres(
    auth$connection,
    host = "localhost",
    dbname = "oauthdb_fixture",
    user = function() req(auth$token@userinfo$preferred_username),
    issuer = issuer,
    scope = "database.read",
    sslrootcert = "/fixtures/tls/ca-cert.pem"
  )
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(
      connection,
      "SELECT marker FROM visible_rows ORDER BY row_id"
    )
  })
}

shinyApp(ui, server, uiPattern = ".*")
