library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

provider <- oauth_provider_oidc_discover(
  issuer = Sys.getenv("OAUTHDB_TRINO_ISSUER")
)
client <- oauth_client(
  provider,
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = Sys.getenv("OAUTHDB_REDIRECT_URI", "http://localhost:8100"),
  scopes = c("openid", "profile", "email", "offline_access")
)

ui <- oauth_ui(fluidPage(
  actionButton("login", "Sign in"),
  actionButton("logout", "Sign out"),
  tableOutput("rows")
), id = "auth", client = client)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  con <- oauth_db_trino(
    auth$connection,
    host = Sys.getenv("OAUTHDB_TRINO_HOST"),
    catalog = Sys.getenv("OAUTHDB_TRINO_CATALOG"),
    schema = Sys.getenv("OAUTHDB_TRINO_SCHEMA"),
    user = function() req(auth$token@userinfo$email)
  )
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, "SELECT current_user AS database_user")
  })
}

app <- shinyApp(ui, server, uiPattern = ".*")
if (interactive()) runApp(app, port = as.integer(Sys.getenv("OAUTHDB_PORT", "8100")),
                          launch.browser = FALSE)
