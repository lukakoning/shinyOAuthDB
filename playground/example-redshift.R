# Query Redshift with Microsoft sign-in; see playground/README.md for setup.
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

client <- oauth_db_microsoft_client(
  tenant_id = Sys.getenv("OAUTHDB_TENANT_ID"),
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = Sys.getenv("OAUTHDB_REDIRECT_URI", "http://localhost:8100"),
  token_targets = list(
    redshift = list(
      resource = Sys.getenv("OAUTHDB_REDSHIFT_RESOURCE"),
      scopes = Sys.getenv("OAUTHDB_REDSHIFT_SCOPE")
    )
  )
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

  con <- oauth_db_redshift(
    auth$connection,
    server = Sys.getenv("OAUTHDB_REDSHIFT_SERVER"),
    database = Sys.getenv("OAUTHDB_DATABASE"),
    driver = Sys.getenv("OAUTHDB_REDSHIFT_DRIVER", "Amazon Redshift (x64)"),
    target = "redshift"
  )
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, "SELECT current_user AS database_user")
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
