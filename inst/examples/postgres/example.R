library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

demo <- oauth_db_demo("postgrest", action = "services")

client <- oauth_client(
  demo$provider,
  client_id = "shiny-db",
  client_secret = "demo-client-secret",
  redirect_uri = "http://localhost:18100",
  scopes = c("openid", "profile", "database.read")
)

ui <- oauth_ui(
  fluidPage(
    actionButton("login", "Sign in"),
    actionButton("logout", "Sign out"),

    actionButton("load", "Load rows"),
    textOutput("account"),
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

  output$account <- renderText({
    if (is.null(auth$connection())) {
      "Not signed in"
    } else {
      "Signed in. Click Load rows."
    }
  })

  postgres <- oauth_db_postgrest_api(auth$connection, url = demo$url)

  query_task <- oauth_db_task(postgres, method = "select")

  observeEvent(input$load, {
    query_task$invoke("visible_rows", order = "row_id.asc")
  })

  output$rows <- renderTable(query_task$result())
}

runApp(
  shinyApp(ui, server, uiPattern = ".*", onStart = function() {
    onStop(demo$stop)

    mirai::daemons(2)

    onStop(function() mirai::daemons(0))
  }),
  port = 18100,
  launch.browser = FALSE
)

# Open the app in your regular browser at its registered redirect URI.
