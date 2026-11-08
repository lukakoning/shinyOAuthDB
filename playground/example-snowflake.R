# Query Snowflake as the signed-in user; see playground/README.md for setup.
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

server_name <- Sys.getenv("OAUTHDB_SNOWFLAKE_SERVER")
role <- Sys.getenv("OAUTHDB_SNOWFLAKE_ROLE")
client <- oauth_db_snowflake_client(
  server = server_name,
  role = role,
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = Sys.getenv("OAUTHDB_REDIRECT_URI", "http://localhost:8100")
)

ui <- oauth_ui(
  fluidPage(
    titlePanel("Snowflake OAuth"),
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

  con <- oauth_db_snowflake(
    auth$connection,
    server = server_name,
    database = Sys.getenv("OAUTHDB_DATABASE"),
    schema = Sys.getenv("OAUTHDB_SNOWFLAKE_SCHEMA"),
    warehouse = Sys.getenv("OAUTHDB_SNOWFLAKE_WAREHOUSE"),
    role = role
  )
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(
      connection,
      "SELECT CURRENT_USER() AS database_user, CURRENT_ROLE() AS database_role"
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

# Open the app in your regular browser at its registered redirect URI.
# (viewers in RStudio/Positron/etc. cannot perform necessary redirects)
