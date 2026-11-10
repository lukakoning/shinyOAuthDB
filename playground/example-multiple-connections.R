library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

app_origin <- Sys.getenv("OAUTHDB_APP_ORIGIN", "http://localhost:8100")

client <- oauth_db_microsoft_client(
  services = "sql",
  tenant_id = Sys.getenv("OAUTHDB_TENANT_ID"),
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = paste0(app_origin, "/callback/database")
)

manager <- oauth_connections(
  clients = list(database = client),
  app_origin = app_origin,
  retention = "browser",
  owner_policy = oauth_browser_owner(allow_http_loopback = TRUE),
  store = oauth_connection_store_memory(),
  keys = list(
    credentials = openssl::rand_bytes(32L),
    owner = openssl::rand_bytes(32L)
  )
)

ui <- oauth_connections_ui(
  fluidPage(
    titlePanel("Choose a database authorization"),

    actionButton("connect", "Add authorization"),

    selectInput(
      "authorization_id",
      "Use authorization",
      choices = c(Choose = "")
    ),

    actionButton("disconnect", "Remove selected authorization"),

    actionButton("load", "Load rows"),
    tableOutput("rows")
  ),

  id = "authorizations",
  manager = manager
)

server <- function(input, output, session) {
  auth <- oauth_connections_server("authorizations", manager, async = TRUE)

  observeEvent(input$connect, auth$connect("database"))

  observeEvent(input$disconnect, {
    req(input$authorization_id)

    auth$disconnect(input$authorization_id, revoke = FALSE)
  })

  observeEvent(input$authorization_id, auth$touch(), ignoreInit = TRUE)

  observe({
    records <- Filter(
      function(x) !x$status %in% c("disconnected", "unavailable"),
      auth$connections()
    )

    ids <- vapply(records, function(x) x$connection_id, character(1))
    labels <- paste("Authorization", seq_along(ids), recycle0 = TRUE)
    selected <- isolate(input$authorization_id)

    if (is.null(selected) || !selected %in% ids) {
      selected <- ""
    }

    updateSelectInput(
      session,
      "authorization_id",
      choices = c(Choose = "", stats::setNames(ids, labels)),
      selected = selected
    )
  })

  authorization <- reactive({
    id <- input$authorization_id

    if (is.null(id) || !nzchar(id)) {
      return(NULL)
    }

    auth$connection(id)
  })

  con <- oauth_db_azure_sql(
    authorization,
    server = Sys.getenv("OAUTHDB_SERVER"),
    database = Sys.getenv("OAUTHDB_DATABASE")
  )

  query_task <- oauth_db_task(con)

  observeEvent(input$load, {
    query_task$invoke("SELECT CURRENT_USER AS database_user")
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
