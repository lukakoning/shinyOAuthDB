# Compose the actual shinyOAuth manager with explicitly selected authorizations.
# This adds no login, token-refresh or credential-storage controller.

playground_multiple_labels <- c(app_login = "Application login", database = "Database authorization")

playground_multiple_rows <- function(rows, label) {
  Filter(function(row) {
    is.list(row) && identical(row$client_label, label) &&
      is.character(row$connection_id) && length(row$connection_id) == 1L &&
      !row$status %in% c("disconnected", "unavailable")
  }, rows)
}

playground_multiple_choices <- function(rows, label) {
  rows <- playground_multiple_rows(rows, label)
  ids <- vapply(rows, function(row) row$connection_id, character(1))
  descriptions <- vapply(seq_along(rows), function(index) {
    paste(label, index, paste0("(", rows[[index]]$status, ")"))
  }, character(1))
  c("Choose an authorization" = "", stats::setNames(ids, descriptions))
}

playground_multiple_select <- function(auth, rows, id, label) {
  if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id)) return(NULL)
  matching <- playground_multiple_rows(rows, label)
  ids <- vapply(matching, function(row) row$connection_id, character(1))
  if (!id %in% ids) return(NULL)
  # Always pass an explicit, owner-visible ID. No call to connection() without
  # an ID, and no attempt to use an app-login grant for database access.
  tryCatch(auth$connection(id), error = function(e) NULL)
}

playground_multiple_config <- function() {
  for (package in c("shiny", "shinyOAuth", "shinyOAuthDB", "openssl")) playground_require(package)
  spec <- playground_spec(playground_env("OAUTHDB_MULTIPLE_BACKEND", "azure-sql"))
  if (!identical(spec$provider, "microsoft")) {
    stop("This example uses two Microsoft profiles; configure another provider explicitly for its backend.", call. = FALSE)
  }
  origin <- sub("/$", "", playground_env("OAUTHDB_APP_ORIGIN", "http://localhost:8100"))
  login_redirect <- playground_env("OAUTHDB_LOGIN_REDIRECT_URI", paste0(origin, "/callback/login"))
  database_redirect <- playground_env("OAUTHDB_DB_REDIRECT_URI", paste0(origin, "/callback/database"))
  routes <- c(login_redirect, database_redirect)
  secret <- playground_env("OAUTHDB_LOGIN_CLIENT_SECRET", "")
  login_client <- shinyOAuth::oauth_client(
    provider = shinyOAuth::oauth_provider_microsoft(
      tenant = playground_env("OAUTHDB_LOGIN_TENANT_ID", playground_env("OAUTHDB_TENANT_ID")),
      id_token_validation = TRUE, userinfo_required = FALSE
    ),
    client_id = playground_env("OAUTHDB_LOGIN_CLIENT_ID"),
    client_secret = if (nzchar(secret)) secret else character(),
    redirect_uri = login_redirect, scopes = c("openid", "profile", "offline_access"),
    required_scopes = "openid", label = playground_multiple_labels[["app_login"]],
    authorization_server_mode = "multi_redirect_uri",
    authorization_server_redirect_uris = routes
  )
  database_client <- shinyOAuthDB::oauth_db_microsoft_client(
    spec$source, tenant_id = playground_env("OAUTHDB_TENANT_ID"),
    client_id = playground_env("OAUTHDB_CLIENT_ID"),
    client_secret = playground_env("OAUTHDB_CLIENT_SECRET", ""),
    redirect_uri = database_redirect, label = playground_multiple_labels[["database"]],
    authorization_server_mode = "multi_redirect_uri",
    authorization_server_redirect_uris = routes
  )
  manager <- shinyOAuth::oauth_connections(
    clients = list(app_login = login_client, database = database_client),
    app_origin = origin, retention = "browser",
    owner_policy = shinyOAuth::oauth_browser_owner(allow_http_loopback = TRUE),
    store = shinyOAuth::oauth_connection_store_memory(),
    # These private demo keys live for one R process. Deployment-held keys and
    # owner policy belong to the app's existing shinyOAuth configuration.
    keys = list(credentials = openssl::rand_bytes(32L), owner = openssl::rand_bytes(32L))
  )
  list(spec = spec, manager = manager, app_origin = origin)
}

playground_multiple_ui <- function(spec) {
  shiny::fluidPage(
    shiny::titlePanel("Separate application login and database authorization"),
    shiny::p("Both profiles use shinyOAuth's connection manager. Select each authorization explicitly; logging into the app alone does not authorize database access."),
    shiny::h4("Application login"),
    shiny::actionButton("login", "Authorize app login"),
    shiny::selectInput("app_login_id", "Application login authorization", choices = c("Choose an authorization" = "")),
    shiny::h4("Database authorization"),
    shiny::actionButton("authorize_database", "Add database authorization"),
    shiny::selectInput("database_id", "Database authorization", choices = c("Choose an authorization" = "")),
    shiny::actionButton("disconnect_database", "Disconnect selected database authorization"),
    shiny::actionButton("logout", "Clear all local authorizations"),
    shiny::p(spec$note),
    shiny::numericInput("value", "Bound example value", 7L, min = 0, max = 1000000, step = 1),
    shiny::actionButton("run_sync", "Run native call"),
    shiny::actionButton("run_async", "Run in background"),
    shiny::actionButton("cancel", "Discard background result"),
    shiny::h4("Authorization and connection status"),
    shiny::textOutput("selection_status"), shiny::textOutput("authorization_error"),
    shiny::verbatimTextOutput("status"),
    shiny::h4("Native result"), shiny::textOutput("sync_error"), shiny::verbatimTextOutput("sync_result"),
    shiny::h4("Background status and result"),
    shiny::verbatimTextOutput("async_status"), shiny::verbatimTextOutput("async_result")
  )
}

playground_multiple_server <- function(spec, manager, executor = "mirai",
                                       manager_factory = function(id, manager) {
                                         shinyOAuth::oauth_connections_server(id, manager,
                                           async = TRUE, refresh_proactively = TRUE)
                                       }) {
  force(spec)
  force(manager)
  function(input, output, session) {
    auth <- manager_factory("authorizations", manager)
    records <- shiny::reactive(auth$connections())
    selected_login <- shiny::reactive(playground_multiple_select(
      auth, records(), input$app_login_id, playground_multiple_labels[["app_login"]]
    ))
    login_id <- shiny::reactive({
      reference <- selected_login()
      # Grant liveness is separate from token lifetime: refresh or expiry of
      # the same login grant must not switch the application's database user.
      if (is.null(reference) || !isTRUE(reference$has_scopes("openid"))) NULL else reference$id
    })
    active_database_id <- shiny::reactiveVal(NULL)
    active_login_id <- shiny::reactiveVal(NULL)
    shiny::observeEvent(list(input$app_login_id, input$database_id,
                             input$run_sync, input$run_async, input$cancel), {
      # Only explicit input events extend browser-owner activity. Neither
      # reactive credential reads nor automatic refresh count as user activity.
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
      reference <- playground_multiple_select(
        auth, records(), input$database_id, playground_multiple_labels[["database"]]
      )
      active_database_id(if (is.null(login_id()) || is.null(reference)) NULL else reference$id)
    }, ignoreNULL = FALSE, priority = 100)
    database_authorization <- shiny::reactive({
      if (is.null(login_id())) return(NULL)
      playground_multiple_select(auth, records(), active_database_id(),
                                 playground_multiple_labels[["database"]])
    })
    shiny::observe({
      rows <- records()
      for (kind in c("app_login", "database")) {
        input_id <- if (kind == "app_login") "app_login_id" else "database_id"
        choices <- playground_multiple_choices(rows, playground_multiple_labels[[kind]])
        selected <- shiny::isolate(input[[input_id]])
        if (is.null(selected) || !selected %in% unname(choices)) selected <- ""
        shiny::updateSelectInput(session, input_id, choices = choices, selected = selected)
      }
    })
    shiny::observeEvent(input$authorize_database, {
      shiny::req(login_id())
      auth$connect("database")
    })
    shiny::observeEvent(input$disconnect_database, {
      reference <- database_authorization()
      shiny::req(reference)
      # Disconnect only this local grant; no implication that an upstream grant
      # is revoked, since providers may share grants across authorizations.
      auth$disconnect(reference$id, revoke = FALSE)
      active_database_id(NULL)
      shiny::updateSelectInput(session, "database_id", selected = "")
    })
    adapted_factory <- function(input, output, session) list(
      connection = function() database_authorization(),
      request_login = function() auth$connect("app_login"),
      logout = function() {
        active_database_id(NULL)
        auth$logout(revoke = FALSE, reload = TRUE)
        shiny::updateSelectInput(session, "app_login_id", selected = "")
        shiny::updateSelectInput(session, "database_id", selected = "")
      }
    )
    bridge <- playground_server(spec, auth_factory = adapted_factory, executor = executor)(input, output, session)
    db <- bridge$db
    task <- bridge$task
    sync_result <- bridge$sync_result
    output$selection_status <- shiny::renderText({
      if (is.null(login_id())) "Select an active application login authorization." else if (
        is.null(database_authorization())) "Select a separate database authorization." else "App login and database authorization are selected independently."
    })
    output$authorization_error <- shiny::renderText({
      if (length(auth$errors())) "An authorization needs attention; retry the appropriate profile." else ""
    })
    invisible(list(auth = auth, db = db, task = task, sync_result = sync_result))
  }
}

oauth_db_multiple_playground <- function(config = playground_multiple_config(), executor = "mirai") {
  ui <- shinyOAuth::oauth_connections_ui(playground_multiple_ui(config$spec),
    id = "authorizations", manager = config$manager)
  shiny::shinyApp(ui, playground_multiple_server(config$spec, config$manager, executor), uiPattern = ".*")
}

run_oauth_db_multiple_playground <- function() {
  executor <- playground_env("OAUTHDB_EXECUTOR", "mirai")
  playground_require(executor)
  if (executor == "mirai") {
    mirai::daemons(2L)
    on.exit(mirai::daemons(0L), add = TRUE)
  } else if (executor == "future") {
    old_plan <- future::plan(future::multisession, workers = 2L)
    on.exit(future::plan(old_plan), add = TRUE)
  } else stop("OAUTHDB_EXECUTOR must be 'mirai' or 'future'.", call. = FALSE)
  config <- playground_multiple_config()
  port <- suppressWarnings(as.integer(playground_env("OAUTHDB_PORT", "8100")))
  if (is.na(port) || port < 1L || port > 65535L) stop("OAUTHDB_PORT must be a valid TCP port.", call. = FALSE)
  message("Open OAUTHDB_APP_ORIGIN in your browser; select login and database grants separately.")
  shiny::runApp(oauth_db_multiple_playground(config, executor), host = "127.0.0.1", port = port, launch.browser = FALSE)
}
