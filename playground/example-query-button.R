# Query only on demand; clear app-owned results when authorization changes.
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

client <- oauth_db_microsoft_client(
  services = "sql", tenant_id = Sys.getenv("OAUTHDB_TENANT_ID"),
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = Sys.getenv("OAUTHDB_REDIRECT_URI", "http://localhost:8100")
)
ui <- oauth_ui(fluidPage(
  titlePanel("Query on demand"),
  actionButton("login", "Sign in"), actionButton("logout", "Sign out"),
  actionButton("run", "Run query"), tableOutput("rows")
), id = "auth", client = client)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())
  permissions <- "https://database.windows.net//user_impersonation"
  authorization <- reactive({
    grant <- auth$connection()
    if (is.null(grant) || !grant$has_scopes(permissions, target = "sql")) return(NULL)
    grant
  })
  con <- oauth_db_azure_sql(auth$connection, scopes = permissions,
    server = Sys.getenv("OAUTHDB_SERVER"), database = Sys.getenv("OAUTHDB_DATABASE"))

  rows <- reactiveVal(NULL)
  observeEvent(authorization(), rows(NULL), ignoreNULL = FALSE, priority = 100)
  observeEvent(input$run, {
    rows(NULL)
    grant <- req(authorization())
    value <- tryCatch({
      connection <- con()
      DBI::dbGetQuery(connection, "SELECT CURRENT_USER AS database_user")
    }, error = identity)
    rows(list(authorization = grant, value = value))
  })
  output$rows <- renderTable({
    grant <- req(authorization())
    result <- req(rows())
    req(identical(result$authorization, grant))
    if (inherits(result$value, "error")) stop(result$value)
    result$value
  })
}

app <- shinyApp(ui, server, uiPattern = ".*")
if (interactive()) runApp(app, port = as.integer(Sys.getenv("OAUTHDB_PORT", "8100")),
                          launch.browser = FALSE)
