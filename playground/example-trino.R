pkgs <- c("shiny", "shinyOAuth", "shinyOAuthDB", "mirai", "RTrino")
for (pkg in pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg)
  }
}

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
  con <- oauth_db_trino(
    auth$connection,
    host = Sys.getenv("OAUTHDB_TRINO_HOST"),
    catalog = Sys.getenv("OAUTHDB_TRINO_CATALOG"),
    schema = Sys.getenv("OAUTHDB_TRINO_SCHEMA"),
    user = function() req(auth$token@userinfo$email)
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
