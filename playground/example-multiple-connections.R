# Run from the repository root after setting playground/README.md's Azure SQL
# and separate app-login environment variables. Both callbacks must be registered.
# All application code is here: configuration, OAuth, UI, server, and queries.

library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)
library(DBI)
library(odbc)

required <- c("OAUTHDB_SERVER", "OAUTHDB_DATABASE", "OAUTHDB_TENANT_ID",
              "OAUTHDB_CLIENT_ID", "OAUTHDB_LOGIN_CLIENT_ID")
missing <- required[!nzchar(Sys.getenv(required))]
if (length(missing)) stop("Set these environment variables: ", paste(missing, collapse = ", "))

app_origin <- sub("/$", "", Sys.getenv("OAUTHDB_APP_ORIGIN", "http://localhost:8100"))
port <- suppressWarnings(as.integer(Sys.getenv("OAUTHDB_PORT", "8100")))
if (is.na(port) || port < 1L || port > 65535L) stop("OAUTHDB_PORT must be a valid TCP port.")
login_redirect <- Sys.getenv("OAUTHDB_LOGIN_REDIRECT_URI", paste0(app_origin, "/callback/login"))
database_redirect <- Sys.getenv("OAUTHDB_DB_REDIRECT_URI", paste0(app_origin, "/callback/database"))
redirects <- c(login_redirect, database_redirect)
login_label <- "Application login"
database_label <- "Database authorization"

database_source <- shinyOAuthDB::oauth_db_azure_sql(
  server = Sys.getenv("OAUTHDB_SERVER"),
  database = Sys.getenv("OAUTHDB_DATABASE"),
  driver = Sys.getenv("OAUTHDB_SQL_DRIVER", "ODBC Driver 18 for SQL Server")
)
login_secret <- Sys.getenv("OAUTHDB_LOGIN_CLIENT_SECRET", "")
login_client <- shinyOAuth::oauth_client(
  provider = shinyOAuth::oauth_provider_microsoft(
    tenant = Sys.getenv("OAUTHDB_LOGIN_TENANT_ID", Sys.getenv("OAUTHDB_TENANT_ID")),
    id_token_validation = TRUE, userinfo_required = FALSE
  ),
  client_id = Sys.getenv("OAUTHDB_LOGIN_CLIENT_ID"),
  client_secret = if (nzchar(login_secret)) login_secret else character(),
  redirect_uri = login_redirect,
  scopes = c("openid", "profile", "offline_access"), required_scopes = "openid",
  label = login_label,
  authorization_server_mode = "multi_redirect_uri",
  authorization_server_redirect_uris = redirects
)
database_client <- shinyOAuthDB::oauth_db_microsoft_client(
  database_source,
  tenant_id = Sys.getenv("OAUTHDB_TENANT_ID"),
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET", ""),
  redirect_uri = database_redirect, label = database_label,
  authorization_server_mode = "multi_redirect_uri",
  authorization_server_redirect_uris = redirects
)
manager <- shinyOAuth::oauth_connections(
  clients = list(app_login = login_client, database = database_client),
  app_origin = app_origin, retention = "browser",
  owner_policy = shinyOAuth::oauth_browser_owner(allow_http_loopback = TRUE),
  store = shinyOAuth::oauth_connection_store_memory(),
  # Demo-only private keys encrypt this process's in-memory credentials and
  # authenticate its browser-owner cookie. A process restart forgets the grants.
  keys = list(credentials = openssl::rand_bytes(32L), owner = openssl::rand_bytes(32L))
)

executor <- Sys.getenv("OAUTHDB_EXECUTOR", "mirai")

ui <- shinyOAuth::oauth_connections_ui(shiny::fluidPage(
  shiny::titlePanel("Separate application login and Azure SQL authorization"),
  shiny::p("Select each authorization explicitly. App login alone does not authorize database access."),
  shiny::h4("Application login"),
  shiny::actionButton("login", "Authorize app login"),
  shiny::selectInput("app_login_id", "Application login authorization", choices = c("Choose an authorization" = "")),
  shiny::h4("Database authorization"),
  shiny::actionButton("authorize_database", "Add database authorization"),
  shiny::selectInput("database_id", "Database authorization", choices = c("Choose an authorization" = "")),
  shiny::actionButton("disconnect_database", "Disconnect selected database authorization"),
  shiny::actionButton("logout", "Clear all local authorizations"),
  shiny::p("Azure SQL enforces the selected database user's permissions; the input below is a bound query parameter."),
  shiny::numericInput("value", "Bound example value", 7L, min = 0, max = 1000000, step = 1),
  shiny::actionButton("run_sync", "Run native query"),
  shiny::actionButton("run_async", "Run in background"),
  shiny::actionButton("cancel", "Discard background result"),
  shiny::h4("Authorization and connection status"),
  shiny::textOutput("selection_status"), shiny::textOutput("authorization_error"),
  shiny::verbatimTextOutput("status"),
  shiny::h4("Native result"), shiny::textOutput("sync_error"), shiny::verbatimTextOutput("sync_result"),
  shiny::h4("Background status and result"),
  shiny::verbatimTextOutput("async_status"), shiny::verbatimTextOutput("async_result")
), id = "authorizations", manager = manager)

server <- function(input, output, session) {
  auth <- shinyOAuth::oauth_connections_server("authorizations", manager,
    async = TRUE, refresh_proactively = TRUE)
  records <- shiny::reactive(auth$connections())

  # Restrict each selector to this browser owner's live grants for that profile.
  profile_rows <- function(rows, label) Filter(function(row) {
    is.list(row) && identical(row$client_label, label) &&
      is.character(row$connection_id) && length(row$connection_id) == 1L &&
      !row$status %in% c("disconnected", "unavailable")
  }, rows)
  selected_authorization <- function(id, label) {
    if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id)) return(NULL)
    rows <- profile_rows(records(), label)
    ids <- vapply(rows, function(row) row$connection_id, character(1))
    if (!id %in% ids) return(NULL)
    # Never call connection() without an ID or substitute an app-login grant.
    tryCatch(auth$connection(id), error = function(e) NULL)
  }
  selected_login <- shiny::reactive(selected_authorization(input$app_login_id, login_label))
  login_id <- shiny::reactive({
    reference <- selected_login()
    # Grant liveness differs from token lifetime: refreshing the same login must
    # not switch the database user or repeat a query.
    if (is.null(reference) || !isTRUE(reference$has_scopes("openid"))) NULL else reference$id
  })
  active_login_id <- shiny::reactiveVal(NULL)
  active_database_id <- shiny::reactiveVal(NULL)
  shiny::observeEvent(list(input$app_login_id, input$database_id,
                           input$run_sync, input$run_async, input$cancel), {
    # Only explicit input events count as browser-owner activity.
    tryCatch(auth$touch(), error = function(e) invisible(NULL))
  }, ignoreInit = TRUE, priority = 300)
  shiny::observeEvent(login_id(), {
    next_login <- login_id()
    if (!identical(active_login_id(), next_login)) {
      active_login_id(next_login)
      active_database_id(NULL)
      shiny::updateSelectInput(session, "database_id", selected = "")
    }
  }, ignoreNULL = FALSE, priority = 200)
  shiny::observeEvent(input$database_id, {
    reference <- selected_authorization(input$database_id, database_label)
    active_database_id(if (is.null(login_id()) || is.null(reference)) NULL else reference$id)
  }, ignoreNULL = FALSE, priority = 100)
  database_authorization <- shiny::reactive({
    if (is.null(login_id())) return(NULL)
    selected_authorization(active_database_id(), database_label)
  })
  shiny::observe({
    for (kind in c("app_login", "database")) {
      input_id <- if (kind == "app_login") "app_login_id" else "database_id"
      label <- if (kind == "app_login") login_label else database_label
      rows <- profile_rows(records(), label)
      ids <- vapply(rows, function(row) row$connection_id, character(1))
      labels <- vapply(seq_along(rows), function(index) {
        paste(label, index, paste0("(", rows[[index]]$status, ")"))
      }, character(1))
      choices <- c("Choose an authorization" = "", stats::setNames(ids, labels))
      selected <- shiny::isolate(input[[input_id]])
      if (is.null(selected) || !selected %in% unname(choices)) selected <- ""
      shiny::updateSelectInput(session, input_id, choices = choices, selected = selected)
    }
  })

  db <- shinyOAuthDB::oauth_db_session(database_source,
    authorization = database_authorization, session = session, connection_policy = "session")
  task <- shinyOAuthDB::oauth_db_task(db, DBI::dbGetQuery, executor = executor,
    effect = "read", pending = "latest")
  last_result <- shiny::reactiveVal(NULL)
  last_error <- shiny::reactiveVal(NULL)
  owner <- shiny::reactive({
    reference <- database_authorization()
    if (is.null(reference)) NULL else list(id = reference$id, generation = db$generation())
  })
  observed_owner <- shiny::reactiveVal(NULL)
  shiny::observeEvent(owner(), {
    if (!identical(observed_owner(), owner())) {
      observed_owner(owner())
      last_result(NULL)
      last_error(NULL)
    }
  }, ignoreNULL = FALSE, priority = 100)

  shiny::observeEvent(input$login, auth$connect("app_login"))
  shiny::observeEvent(input$authorize_database, {
    shiny::req(login_id())
    auth$connect("database")
  })
  shiny::observeEvent(input$disconnect_database, {
    reference <- database_authorization()
    shiny::req(reference)
    auth$disconnect(reference$id, revoke = FALSE)
    active_database_id(NULL)
    shiny::updateSelectInput(session, "database_id", selected = "")
  })
  shiny::observeEvent(input$logout, {
    active_database_id(NULL)
    auth$logout(revoke = FALSE, reload = TRUE)
    shiny::updateSelectInput(session, "app_login_id", selected = "")
    shiny::updateSelectInput(session, "database_id", selected = "")
  })

  statement <- "SELECT CURRENT_USER AS database_user, CAST(? AS int) AS requested_value"
  query_value <- function() {
    value <- input$value
    shiny::req(is.numeric(value), length(value) == 1L, is.finite(value),
               value >= 0, value <= 1000000, value == floor(value))
    as.integer(value)
  }
  shiny::observeEvent(input$run_sync, {
    captured_owner <- owner()
    shiny::req(captured_owner)
    last_result(NULL)
    last_error(NULL)
    tryCatch({
      value <- suppressWarnings(suppressMessages(DBI::dbGetQuery(
        db$connection(), statement, params = list(query_value())
      )))
      if (identical(captured_owner, owner())) last_result(list(owner = captured_owner, value = value))
    }, error = function(e) {
      if (identical(captured_owner, owner())) last_error(list(owner = captured_owner,
        message = "The query failed. Check the selected user's grants and database configuration."))
    })
  })
  shiny::observeEvent(input$run_async, {
    shiny::req(owner())
    task$invoke(statement = statement, params = list(query_value()))
  })
  shiny::observeEvent(input$cancel, task$cancel())
  sync_result <- shiny::reactive({
    result <- last_result()
    shiny::req(result, identical(result$owner, owner()))
    result$value
  })
  output$selection_status <- shiny::renderText({
    if (is.null(login_id())) "Select an active application login authorization." else if (
      is.null(database_authorization())) "Select a separate database authorization." else
        "App login and database authorization are selected independently."
  })
  output$authorization_error <- shiny::renderText({
    if (length(auth$errors())) "An authorization needs attention; retry the appropriate profile." else ""
  })
  output$status <- shiny::renderPrint(db$status())
  output$sync_error <- shiny::renderText({
    error <- last_error()
    shiny::req(error, identical(error$owner, owner()))
    error$message
  })
  output$sync_result <- shiny::renderPrint(sync_result())
  output$async_status <- shiny::renderPrint(task$status())
  output$async_result <- shiny::renderPrint(task$result())
}

app <- shiny::shinyApp(ui, server, uiPattern = ".*")
# Configure background workers once for the app, outside the Shiny server.
if (executor == "mirai") {
  mirai::daemons(2L)
} else if (executor == "future") {
  previous_future_plan <- future::plan(future::multisession, workers = 2L)
} else stop("OAUTHDB_EXECUTOR must be 'mirai' or 'future'.")
tryCatch(
  shiny::runApp(app, host = "127.0.0.1", port = port, launch.browser = FALSE),
  finally = {
    if (executor == "mirai") mirai::daemons(0L) else future::plan(previous_future_plan)
  }
)
