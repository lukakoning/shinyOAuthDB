library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

host <- sub(
  "/$",
  "",
  sub("^https://", "", Sys.getenv("OAUTHDB_DATABRICKS_HOST"))
)

client <- oauth_db_databricks_client(
  host = host,
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = Sys.getenv("OAUTHDB_REDIRECT_URI", "http://localhost:8100")
)

ui <- oauth_ui(
  fluidPage(
    titlePanel("Databricks SQL"),

    actionButton("login", "Sign in"),
    actionButton("logout", "Sign out"),

    actionButton("load", "Load rows"),
    verbatimTextOutput("rows")
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

  databricks <- oauth_db_databricks_api(auth$connection, host = host)

  query_task <- oauth_db_task(databricks, method = "call")

  observeEvent(input$load, {
    query_task$invoke(
      brickster::db_sql_query,
      warehouse_id = Sys.getenv("OAUTHDB_DATABRICKS_WAREHOUSE"),
      statement = "SELECT current_user() AS database_user",
      disposition = "INLINE",
      show_progress = FALSE
    )
  })

  output$rows <- renderPrint(query_task$result())
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
