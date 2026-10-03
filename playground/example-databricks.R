# Run from the shinyOAuthDB repository root after configuring the environment
# described in playground/README.md. This example opens no browser automatically.
# This is a complete app: adapt its source, native call, UI and server.
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)
library(brickster)

# Endpoint and OAuth settings are trusted server configuration.
config <- list(
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  host = Sys.getenv("OAUTHDB_DATABRICKS_HOST"),
  warehouse_id = Sys.getenv("OAUTHDB_DATABRICKS_WAREHOUSE"),
  redirect_uri = Sys.getenv("OAUTHDB_REDIRECT_URI", "http://localhost:8100")
)
if (any(!nzchar(unlist(config[c("client_id", "host", "warehouse_id" )], use.names = FALSE)))) {
  stop("Set the required OAuth and backend environment variables listed in playground/README.md.",
       call. = FALSE)
}
port <- suppressWarnings(as.integer(Sys.getenv("OAUTHDB_PORT", "8100")))
if (is.na(port) || port < 1L || port > 65535L) {
  stop("OAUTHDB_PORT must be a valid TCP port.", call. = FALSE)
}
executor <- match.arg(Sys.getenv("OAUTHDB_EXECUTOR", "mirai"), c("mirai", "future"))

db_source <- shinyOAuthDB::oauth_db_databricks(
  host = config$host, warehouse_id = config$warehouse_id,
  auth_mode = "databricks_oauth", scopes = "sql"
)
# Browser input is a named parameter, never SQL text, a workspace or a grant.
statement <- "SELECT current_user() AS database_user, CAST(:value AS INT) AS requested_value"

# Reuse brickster provider discovery and shinyOAuth's real browser flow.
# Register this OAuth application for the workspace and exact callback.
client <- shinyOAuth::oauth_client(
  provider = brickster::db_oauth_provider(
    host = config$host,
    token_auth_style = if (nzchar(config$client_secret)) "header" else "public"
  ),
  client_id = config$client_id, client_secret = config$client_secret,
  redirect_uri = config$redirect_uri,
  scopes = c("openid", "profile", "offline_access", "sql")
)

ui <- shinyOAuth::oauth_ui(
  shiny::fluidPage(
    shiny::titlePanel("shinyOAuthDB: Databricks SQL"),
    shiny::p("Run parameterized SQL as the selected Databricks user."),
    shiny::actionButton("login", "Sign in"),
    shiny::actionButton("logout", "Sign out"),
    shiny::numericInput("value", "Bound SQL value", 7L, min = 0, max = 1000000, step = 1),
    shiny::actionButton("run_sync", "Run native call"),
    shiny::actionButton("run_async", "Run in background"),
    shiny::actionButton("cancel", "Discard background result"),
    shiny::h4("Authorization status"), shiny::verbatimTextOutput("status"),
    shiny::h4("Native result"), shiny::textOutput("sync_error"),
    shiny::verbatimTextOutput("sync_result"),
    shiny::h4("Background status and result"),
    shiny::verbatimTextOutput("async_status"),
    shiny::verbatimTextOutput("async_result")
  ),
  id = "auth", client = client
)

server <- function(input, output, session) {
  auth <- shinyOAuth::oauth_module_server(
    "auth", client, auto_redirect = FALSE,
    async = TRUE, refresh_proactively = TRUE
  )
  # Follow the module's modern connection object; shinyOAuth owns refresh.
  authorization <- shiny::reactive(auth$connection())
  db <- shinyOAuthDB::oauth_db_session(
    db_source, authorization = authorization, session = session,
    connection_policy = "session"
  )
  # The adapter supplies trusted source bindings and a fixed worker token.
  # Live Shiny authorizations/providers stay in the owning Shiny process.
  task_error <- NULL
  task <- tryCatch(
    shinyOAuthDB::oauth_db_task(
      db, brickster::db_sql_query, executor = executor,
      effect = "read", pending = "latest"
    ),
    error = function(e) {
      task_error <<- "Background execution is unavailable. Check source capabilities and worker dependencies."
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

  query_args <- function() {
    value <- input$value
    shiny::req(is.numeric(value), length(value) == 1L, is.finite(value),
               value >= 0, value <= 1000000, value == floor(value))
    list(statement = statement,
         parameters = list(list(name = "value", value = as.character(as.integer(value)), type = "INT")),
         disposition = "INLINE", show_progress = FALSE)
  }
  shiny::observeEvent(input$login, auth$request_login())
  shiny::observeEvent(input$logout, auth$logout())
  shiny::observeEvent(input$run_sync, {
    captured_owner <- owner()
    shiny::req(captured_owner)
    args <- query_args()
    last_result(NULL)
    last_error(NULL)
    tryCatch({
      value <- suppressWarnings(suppressMessages(
        brickster::db_sql_query(
          host = config$host, warehouse_id = config$warehouse_id,
          statement = args$statement, parameters = args$parameters,
          disposition = args$disposition, show_progress = args$show_progress,
          token = db$token_provider()
        )
      ))
      if (identical(captured_owner, owner())) {
        last_result(list(owner = captured_owner, value = value))
      }
    }, error = function(e) {
      # Native conditions may contain sensitive request details. Render only a
      # safe message belonging to the still-current authorization.
      if (identical(captured_owner, owner())) {
        last_error(list(owner = captured_owner,
                        message = "The operation failed. Check the user's grants and backend configuration."))
      }
    })
  })
  shiny::observeEvent(input$run_async, {
    shiny::req(task, owner())
    args <- query_args()
    task$invoke(statement = args$statement, parameters = args$parameters,
                disposition = args$disposition, show_progress = args$show_progress)
  })
  shiny::observeEvent(input$cancel, {
    if (!is.null(task)) task$cancel()
  })

  sync_result <- shiny::reactive({
    saved <- last_result()
    shiny::req(saved, identical(saved$owner, owner()))
    saved$value
  })
  output$status <- shiny::renderPrint(db$status())
  output$sync_error <- shiny::renderText({
    saved <- last_error()
    shiny::req(saved, identical(saved$owner, owner()))
    saved$message
  })
  output$sync_result <- shiny::renderPrint(sync_result())
  output$async_status <- shiny::renderPrint({
    if (is.null(task)) task_error else task$status()
  })
  # oauth_db_task hides background results/errors after authorization changes.
  output$async_result <- shiny::renderPrint({
    shiny::req(task)
    task$result()
  })
}

app <- shiny::shinyApp(ui = ui, server = server, uiPattern = ".*")

# Configure workers once outside server(), then restore them when the app ends.
if (identical(executor, "mirai")) {
  library(mirai)
  mirai::daemons(2L)
} else {
  library(future)
  previous_plan <- future::plan(future::multisession, workers = 2L)
}
message("Open the exact OAUTHDB_REDIRECT_URI in your browser, then click Sign in.")
tryCatch(
  shiny::runApp(app, host = "127.0.0.1", port = port, launch.browser = FALSE),
  finally = {
    if (identical(executor, "mirai")) mirai::daemons(0L)
    else future::plan(previous_plan)
  }
)
