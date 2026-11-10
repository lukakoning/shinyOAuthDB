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

    actionButton("load", "Load rows"),
    tableOutput("rows")
  ),

  id = "auth",
  client = client
)

server <- function(input, output, session) {
  auth <- oauth_module_server(
    "auth",
    client,
    auto_redirect = FALSE,
    async = TRUE
  )

  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  con <- oauth_db_redshift(
    auth$connection,
    server = Sys.getenv("OAUTHDB_REDSHIFT_SERVER"),
    database = Sys.getenv("OAUTHDB_DATABASE"),
    driver = Sys.getenv("OAUTHDB_REDSHIFT_DRIVER", "Amazon Redshift (x64)"),
    target = "redshift"
  )

  query_task <- oauth_db_task(con)

  observeEvent(input$load, {
    query_task$invoke("SELECT current_user AS database_user")
  })

  output$rows <- renderTable(query_task$result())
}

app <- shinyApp(ui, server, uiPattern = ".*", onStart = function() {
  mirai::daemons(2)

  onStop(function() mirai::daemons(0))
})

if (interactive()) {
  runApp(
    app,
    port = as.integer(Sys.getenv("OAUTHDB_PORT", "8100")),
    launch.browser = FALSE
  )
}

# Open the app in your regular browser at its registered redirect URI.
