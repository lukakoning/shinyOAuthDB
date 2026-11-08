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
    tableOutput("rows")
  ),
  id = "auth",
  client = client
)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  postgres <- oauth_db_postgrest_api(
    auth$connection,
    url = demo$url
  )
  output$rows <- renderTable({
    postgres$select("visible_rows", order = "row_id.asc")
  })
}

runApp(
  shinyApp(ui, server, uiPattern = ".*", onStart = function() {
    onStop(demo$stop)
  }),
  port = 18100,
  launch.browser = FALSE
)

# Open the app in your regular browser at http://localhost:18100
# (viewers in RStudio/Positron/etc. cannot perform necessary redirects)
