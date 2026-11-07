# Self-hosted PostgreSQL OAuth; see vignettes/postgres.Rmd for server setup.
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

issuer <- Sys.getenv("OAUTHDB_POSTGRES_ISSUER")
database_scope <- Sys.getenv("OAUTHDB_POSTGRES_SCOPE", "database.read")
provider <- oauth_provider_oidc_discover(issuer, id_token_validation = TRUE)
client <- oauth_client(
  provider,
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = Sys.getenv("OAUTHDB_REDIRECT_URI", "http://localhost:8100"),
  scopes = c(
    "openid",
    "profile",
    strsplit(database_scope, " ", fixed = TRUE)[[1L]]
  )
)

ui <- oauth_ui(
  fluidPage(
    titlePanel("Self-hosted PostgreSQL"),
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
    host = Sys.getenv("OAUTHDB_POSTGRES_HOST"),
    dbname = Sys.getenv("OAUTHDB_DATABASE"),
    user = function() {
      reference <- req(auth$connection())
      identity <- reference$identity(claims = "preferred_username")
      req(identity$id_token_claims$preferred_username)
    },
    issuer = issuer,
    scope = database_scope,
    sslrootcert = Sys.getenv("OAUTHDB_POSTGRES_SSLROOTCERT")
  )
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(
      connection,
      paste(
        "SELECT current_user::text AS database_user, table_schema, table_name",
        "FROM information_schema.tables ORDER BY table_schema, table_name LIMIT 20"
      )
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
