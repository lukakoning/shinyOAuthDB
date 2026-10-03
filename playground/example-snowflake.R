# Standalone Shiny app. Run from the repository root after configuring the
# environment described in playground/README.md; source("playground/example-snowflake.R").
# The Microsoft External OAuth integration must map the audience, scopes and
# subject to the configured Snowflake role. The ODBC driver uses the user token.
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)
library(DBI)
library(odbc)

# Deployment configuration stays server-side; do not accept endpoints or roles from inputs.
tenant_id <- Sys.getenv("OAUTHDB_TENANT_ID")
client_id <- Sys.getenv("OAUTHDB_CLIENT_ID")
client_secret <- Sys.getenv("OAUTHDB_CLIENT_SECRET")
redirect_uri <- Sys.getenv("OAUTHDB_REDIRECT_URI", "http://localhost:8100")
executor <- Sys.getenv("OAUTHDB_EXECUTOR", "mirai")
port <- suppressWarnings(as.integer(Sys.getenv("OAUTHDB_PORT", "8100")))
if (is.na(port) || port < 1L || port > 65535L) {
  stop("OAUTHDB_PORT must be a valid TCP port.", call. = FALSE)
}
account_server <- Sys.getenv("OAUTHDB_SNOWFLAKE_SERVER")
database <- Sys.getenv("OAUTHDB_DATABASE")
schema <- Sys.getenv("OAUTHDB_SNOWFLAKE_SCHEMA")
warehouse <- Sys.getenv("OAUTHDB_SNOWFLAKE_WAREHOUSE")
role <- Sys.getenv("OAUTHDB_SNOWFLAKE_ROLE")
resource <- Sys.getenv("OAUTHDB_SNOWFLAKE_RESOURCE")
scope_text <- trimws(Sys.getenv("OAUTHDB_SNOWFLAKE_SCOPES"))
scopes <- strsplit(scope_text, "[[:space:]]+")[[1L]]
driver <- Sys.getenv("OAUTHDB_SNOWFLAKE_DRIVER", "SnowflakeDSIIDriver")
required_config <- c(OAUTHDB_TENANT_ID = tenant_id, OAUTHDB_CLIENT_ID = client_id,
                     OAUTHDB_SNOWFLAKE_SERVER = account_server, OAUTHDB_DATABASE = database,
                     OAUTHDB_SNOWFLAKE_SCHEMA = schema, OAUTHDB_SNOWFLAKE_WAREHOUSE = warehouse,
                     OAUTHDB_SNOWFLAKE_ROLE = role, OAUTHDB_SNOWFLAKE_RESOURCE = resource,
                     OAUTHDB_SNOWFLAKE_SCOPES = scope_text)
missing_config <- names(required_config)[!nzchar(required_config)]
if (length(missing_config)) {
  stop(paste("Set these environment variables:", paste(missing_config, collapse = ", ")), call. = FALSE)
}

db_source <- shinyOAuthDB::oauth_db_snowflake(
  server = account_server, database = database, schema = schema, warehouse = warehouse,
  role = role, driver = driver, auth_mode = "external_oauth", provider_family = "microsoft",
  resource = resource, scopes = scopes
)
client <- shinyOAuthDB::oauth_db_microsoft_client(
  sources = list(database = db_source), tenant_id = tenant_id, client_id = client_id,
  client_secret = client_secret, redirect_uri = redirect_uri
)

# Replace this trusted read query with one for your own tables to demonstrate database grants.
query_sql <- "SELECT CURRENT_USER() AS database_user, CURRENT_ROLE() AS database_role, CAST(? AS INTEGER) AS requested_value"
query_args <- function(value) {
  shiny::req(is.numeric(value), length(value) == 1L, is.finite(value),
             value >= 0, value <= 1000000, value == floor(value))
  list(statement = query_sql, params = list(as.integer(value)))
}

ui <- shinyOAuth::oauth_ui(
  shiny::fluidPage(
    shiny::titlePanel("shinyOAuthDB: Snowflake External OAuth"),
    shiny::p("The database authenticates the signed-in user. Browser input is a bound query parameter."),
    shiny::actionButton("login", "Sign in"), shiny::actionButton("logout", "Sign out"),
    shiny::numericInput("value", "Bound example value", 7L, min = 0, max = 1000000, step = 1),
    shiny::actionButton("run_sync", "Run native call"),
    shiny::actionButton("run_async", "Run in background"),
    shiny::actionButton("cancel", "Discard background result"),
    shiny::h4("Connection status"), shiny::verbatimTextOutput("status"),
    shiny::h4("Native result"), shiny::textOutput("sync_error"),
    shiny::verbatimTextOutput("sync_result"),
    shiny::h4("Background status and result"), shiny::verbatimTextOutput("async_status"),
    shiny::verbatimTextOutput("async_result")
  ),
  id = "auth", client = client
)

server <- function(input, output, session) {
  auth <- shinyOAuth::oauth_module_server(
    "auth", client, auto_redirect = FALSE, async = TRUE, refresh_proactively = TRUE
  )
  # Use shinyOAuth's connection object; the bridge does not manage another login.
  authorization <- shiny::reactive(auth$connection())
  db <- shinyOAuthDB::oauth_db_session(
    db_source, authorization = authorization, session = session,
    connection_policy = "session"
  )
  # Workers open their own DBI connection; they never serialize db$connection().
  task_error <- NULL
  task <- tryCatch(
    shinyOAuthDB::oauth_db_task(
      db, DBI::dbGetQuery, executor = executor, effect = "read", pending = "latest"
    ),
    error = function(e) {
      task_error <<- "Background queries are unavailable; inspect oauth_db_capabilities(db_source)."
      NULL
    }
  )
  last_result <- shiny::reactiveVal(NULL)
  last_error <- shiny::reactiveVal(NULL)
  owner <- shiny::reactive({
    connection <- authorization()
    if (is.null(connection)) NULL else list(id = connection$id, generation = db$generation())
  })
  observed_owner <- shiny::reactiveVal(NULL)
  shiny::observeEvent(owner(), {
    next_owner <- owner()
    if (!identical(observed_owner(), next_owner)) {
      observed_owner(next_owner)
      last_result(NULL)
      last_error(NULL)
      if (!is.null(task)) task$cancel()
    }
  }, ignoreNULL = FALSE, priority = 100)

  shiny::observeEvent(input$login, auth$request_login())
  shiny::observeEvent(input$logout, auth$logout())
  shiny::observeEvent(input$run_sync, {
    captured_owner <- owner()
    shiny::req(captured_owner)
    args <- query_args(input$value)
    last_result(NULL)
    last_error(NULL)
    tryCatch({
      # This is an ordinary native DBI call using the session's reused connection.
      rows <- suppressWarnings(suppressMessages(DBI::dbGetQuery(
        conn = db$connection(), statement = query_sql, params = args$params
      )))
      if (identical(captured_owner, owner())) {
        last_result(list(owner = captured_owner, value = rows))
      }
    }, error = function(e) {
      if (identical(captured_owner, owner())) {
        last_error(list(owner = captured_owner,
                        message = "The query failed. Check the user's database grants and server configuration."))
      }
    })
  })
  shiny::observeEvent(input$run_async, {
    shiny::req(task, owner())
    args <- query_args(input$value)
    task$invoke(statement = query_sql, params = args$params)
  })
  # This discards a local result; it does not cancel an already submitted SQL statement.
  shiny::observeEvent(input$cancel, if (!is.null(task)) task$cancel())
  sync_result <- shiny::reactive({
    saved <- last_result()
    shiny::req(saved, identical(saved$owner, owner()))
    saved$value
  })
  output$status <- shiny::renderPrint(db$status())
  output$sync_result <- shiny::renderPrint(sync_result())
  output$sync_error <- shiny::renderText({
    error <- last_error()
    shiny::req(error, identical(error$owner, owner()))
    error$message
  })
  output$async_status <- shiny::renderPrint(if (is.null(task)) task_error else task$status())
  output$async_result <- shiny::renderPrint({ shiny::req(task); task$result() })
}

app <- shiny::shinyApp(ui, server, uiPattern = ".*")
# Configure the executor once for the app, outside individual Shiny sessions.
old_plan <- NULL
if (identical(executor, "mirai")) {
  library(mirai)
  mirai::daemons(2L)
} else if (identical(executor, "future")) {
  library(future)
  old_plan <- future::plan(future::multisession, workers = 2L)
} else {
  stop("OAUTHDB_EXECUTOR must be 'mirai' or 'future'.", call. = FALSE)
}
message("Open the exact OAUTHDB_REDIRECT_URI in your browser, then click Sign in.")
tryCatch(
  shiny::runApp(app, host = "127.0.0.1", port = port, launch.browser = FALSE),
  finally = {
    if (identical(executor, "mirai")) mirai::daemons(0L) else future::plan(old_plan)
  }
)
