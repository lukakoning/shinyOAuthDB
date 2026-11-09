pkgs <- c("shiny", "shinyOAuth", "shinyOAuthDB", "mirai", "openssl")
for (pkg in pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg)
  }
}

# Use independent Azure SQL and Databricks sign-ins in one app.
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

app_origin <- Sys.getenv("OAUTHDB_APP_ORIGIN", "http://localhost:8100")
redirects <- paste0(app_origin, c("/callback/sql", "/callback/databricks"))
sql_client <- oauth_db_microsoft_client(
  services = "sql",
  tenant_id = Sys.getenv("OAUTHDB_TENANT_ID"),
  client_id = Sys.getenv("OAUTHDB_SQL_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_SQL_CLIENT_SECRET"),
  redirect_uri = redirects[[1L]],
  label = "Azure SQL",
  authorization_server_mode = "multi_redirect_uri",
  authorization_server_redirect_uris = redirects
)
databricks_client <- oauth_db_databricks_client(
  host = Sys.getenv("OAUTHDB_DATABRICKS_HOST"),
  client_id = Sys.getenv("OAUTHDB_DATABRICKS_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_DATABRICKS_CLIENT_SECRET"),
  redirect_uri = redirects[[2L]],
  label = "Databricks",
  authorization_server_mode = "multi_redirect_uri",
  authorization_server_redirect_uris = redirects
)
manager <- oauth_connections(
  clients = list(database = sql_client, warehouse = databricks_client),
  app_origin = app_origin,
  retention = "browser",
  owner_policy = oauth_browser_owner(allow_http_loopback = TRUE),
  store = oauth_connection_store_memory(),
  # Demo keys last for this process. Configure persistent keys/store in production.
  keys = list(
    credentials = openssl::rand_bytes(32L),
    owner = openssl::rand_bytes(32L)
  )
)
ui <- oauth_connections_ui(
  fluidPage(
    titlePanel("Independent Azure SQL and Databricks authorizations"),
    actionButton("connect_sql", "Authorize Azure SQL"),
    selectInput("sql_id", "SQL authorization", choices = c("Choose" = "")),
    actionButton("disconnect_sql", "Remove SQL authorization"),
    actionButton("load_sql", "Load SQL rows"),
    tableOutput("sql_rows"),
    actionButton("connect_databricks", "Authorize Databricks"),
    selectInput(
      "databricks_id",
      "Databricks authorization",
      choices = c("Choose" = "")
    ),
    actionButton("disconnect_databricks", "Remove Databricks authorization"),
    actionButton("load_databricks", "Load Databricks rows"),
    tableOutput("databricks_rows")
  ),
  id = "authorizations",
  manager = manager
)

server <- function(input, output, session) {
  auth <- oauth_connections_server("authorizations", manager, async = TRUE)
  observeEvent(input$connect_sql, auth$connect("database"))
  observeEvent(input$connect_databricks, auth$connect("warehouse"))
  observeEvent(
    input$disconnect_sql,
    auth$disconnect(req(input$sql_id), revoke = FALSE)
  )
  observeEvent(
    input$disconnect_databricks,
    auth$disconnect(req(input$databricks_id), revoke = FALSE)
  )
  observeEvent(input$sql_id, auth$touch(), ignoreInit = TRUE)
  observeEvent(input$databricks_id, auth$touch(), ignoreInit = TRUE)
  update_picker <- function(input_id, client_label) {
    records <- Filter(
      function(x) {
        identical(x$client_label, client_label) &&
          !x$status %in% c("disconnected", "unavailable")
      },
      auth$connections()
    )
    ids <- vapply(records, function(x) x$connection_id, character(1))
    selected <- isolate(input[[input_id]])
    if (is.null(selected) || !selected %in% ids) {
      selected <- ""
    }
    updateSelectInput(
      session,
      input_id,
      choices = c(
        "Choose" = "",
        stats::setNames(
          ids,
          paste("Authorization", seq_along(ids), recycle0 = TRUE)
        )
      ),
      selected = selected
    )
  }
  observe({
    update_picker("sql_id", "Azure SQL")
    update_picker("databricks_id", "Databricks")
  })
  sql <- oauth_db_azure_sql(
    function() auth$connection(req(input$sql_id)),
    server = Sys.getenv("OAUTHDB_SERVER"),
    database = Sys.getenv("OAUTHDB_DATABASE")
  )
  databricks <- oauth_db_databricks(
    function() auth$connection(req(input$databricks_id)),
    host = Sys.getenv("OAUTHDB_DATABRICKS_HOST"),
    warehouse_id = Sys.getenv("OAUTHDB_DATABRICKS_WAREHOUSE")
  )
  sql_task <- oauth_db_task(sql)
  databricks_task <- oauth_db_task(databricks)
  observeEvent(input$load_sql, {
    sql_task$invoke("SELECT CURRENT_USER AS database_user")
  })
  observeEvent(input$load_databricks, {
    databricks_task$invoke("SELECT current_user() AS database_user")
  })
  output$sql_rows <- renderTable(sql_task$result())
  output$databricks_rows <- renderTable(databricks_task$result())
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
# (viewers in RStudio/Positron/etc. cannot perform necessary redirects)
