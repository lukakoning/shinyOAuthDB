# Shared code for the small, intentionally similar playground apps.
# Source this file from the shinyOAuthDB repository root.

playground_require <- function(package) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop(sprintf("Install '%s' before running this playground.", package), call. = FALSE)
  }
}

playground_env <- function(name, default = NULL, required = is.null(default)) {
  value <- Sys.getenv(name, unset = if (is.null(default)) "" else default)
  if (required && !nzchar(value)) {
    stop(sprintf("Set %s in your environment before starting this app.", name), call. = FALSE)
  }
  value
}

playground_client <- function(source, provider = "microsoft") {
  redirect_uri <- playground_env("OAUTHDB_REDIRECT_URI", "http://localhost:8100")
  if (identical(provider, "microsoft")) {
    return(shinyOAuthDB::oauth_db_microsoft_client(
      sources = list(source),
      tenant_id = playground_env("OAUTHDB_TENANT_ID"),
      client_id = playground_env("OAUTHDB_CLIENT_ID"),
      client_secret = playground_env("OAUTHDB_CLIENT_SECRET", ""),
      redirect_uri = redirect_uri
    ))
  }
  if (identical(provider, "databricks")) {
    # Reuse brickster's actual public OAuth provider rather than maintaining
    # another workspace discovery implementation here.
    secret <- playground_env("OAUTHDB_CLIENT_SECRET", "")
    return(shinyOAuth::oauth_client(
      provider = brickster::db_oauth_provider(
        host = playground_env("OAUTHDB_DATABRICKS_HOST"),
        token_auth_style = if (nzchar(secret)) "header" else "public"
      ),
      client_id = playground_env("OAUTHDB_CLIENT_ID"),
      client_secret = secret,
      redirect_uri = redirect_uri,
      scopes = c("openid", "profile", "offline_access", "sql")
    ))
  }
  stop("Unknown playground provider.", call. = FALSE)
}

# The specification is operator configuration. No browser input changes an
# endpoint, role, OAuth target, SQL text, GraphQL document, or DAX expression.
playground_spec <- function(backend) {
  playground_require("shinyOAuthDB")
  sql_spec <- function(source, query, package = "DBI") {
    list(
      title = backend, source = source, provider = "microsoft",
      package = package, fun = "dbGetQuery",
      native_args = function(value) list(statement = query, params = list(value)),
      sync = function(db, args) do.call(DBI::dbGetQuery, c(list(conn = db$connection()), args)),
      note = "The browser value is bound as a query parameter; the native DBI connection is reused within this Shiny session."
    )
  }
  if (backend %in% c("azure-sql", "sql-server", "fabric-sql")) {
    playground_require("DBI")
    playground_require("odbc")
    driver <- playground_env("OAUTHDB_SQL_DRIVER", "ODBC Driver 18 for SQL Server")
    database <- playground_env("OAUTHDB_DATABASE")
    server <- playground_env("OAUTHDB_SERVER")
    if (identical(backend, "azure-sql")) {
      source <- shinyOAuthDB::oauth_db_azure_sql(server, database, driver = driver)
    } else if (identical(backend, "sql-server")) {
      enabled <- identical(playground_env("OAUTHDB_SQL_SERVER_ENTRA_ENABLED", "false"), "true")
      source <- shinyOAuthDB::oauth_db_sql_server(server, database, driver = driver, entra_enabled = enabled)
    } else {
      playground_require("fabricQueryR")
      source <- shinyOAuthDB::oauth_db_fabric_sql(server, database, driver = driver)
    }
    return(sql_spec(source, "SELECT CURRENT_USER AS database_user, CAST(? AS int) AS requested_value"))
  }
  if (identical(backend, "azure-postgres")) {
    playground_require("DBI")
    playground_require("RPostgres")
    source <- shinyOAuthDB::oauth_db_azure_postgres(
      host = playground_env("OAUTHDB_POSTGRES_HOST"),
      database = playground_env("OAUTHDB_DATABASE"),
      user = playground_env("OAUTHDB_POSTGRES_USER"),
      sslrootcert = playground_env("OAUTHDB_POSTGRES_SSLROOTCERT")
    )
    return(sql_spec(source, "SELECT current_user AS database_user, $1::integer AS requested_value"))
  }
  if (identical(backend, "snowflake")) {
    playground_require("DBI")
    playground_require("odbc")
    source <- shinyOAuthDB::oauth_db_snowflake(
      server = playground_env("OAUTHDB_SNOWFLAKE_SERVER"),
      database = playground_env("OAUTHDB_DATABASE"),
      schema = playground_env("OAUTHDB_SNOWFLAKE_SCHEMA"),
      warehouse = playground_env("OAUTHDB_SNOWFLAKE_WAREHOUSE"),
      role = playground_env("OAUTHDB_SNOWFLAKE_ROLE"),
      driver = playground_env("OAUTHDB_SNOWFLAKE_DRIVER", "SnowflakeDSIIDriver"),
      auth_mode = "external_oauth", provider_family = "microsoft",
      resource = playground_env("OAUTHDB_SNOWFLAKE_RESOURCE"),
      scopes = strsplit(playground_env("OAUTHDB_SNOWFLAKE_SCOPES"), " +")[[1L]]
    )
    return(sql_spec(source, "SELECT CURRENT_USER() AS database_user, CURRENT_ROLE() AS database_role, CAST(? AS INTEGER) AS requested_value"))
  }
  if (identical(backend, "databricks")) {
    playground_require("brickster")
    host <- playground_env("OAUTHDB_DATABRICKS_HOST")
    warehouse <- playground_env("OAUTHDB_DATABRICKS_WAREHOUSE")
    source <- shinyOAuthDB::oauth_db_databricks(
      host = host, warehouse_id = warehouse, auth_mode = "databricks_oauth", scopes = "sql"
    )
    return(list(
      title = backend, source = source, provider = "databricks",
      package = "brickster", fun = "db_sql_query",
      native_args = function(value) list(
        statement = "SELECT current_user() AS database_user, CAST(:value AS INT) AS requested_value",
        parameters = list(list(name = "value", value = as.character(value), type = "INT")),
        disposition = "INLINE", show_progress = FALSE
      ),
      sync = function(db, args) do.call(brickster::db_sql_query, c(
        list(host = host, warehouse_id = warehouse, token = db$token_provider()), args
      )),
      note = "brickster performs the SQL request using the selected user's workspace-bound token provider."
    ))
  }

  playground_require("fabricQueryR")
  service <- sub("^fabric-", "", backend)
  fixed <- list()
  endpoint_hosts <- character()
  if (identical(service, "kql")) {
    fixed <- list(cluster = playground_env("OAUTHDB_KQL_CLUSTER"), database = playground_env("OAUTHDB_KQL_DATABASE"))
    native_args <- function(value) list(
      query = "declare query_parameters(value:int); print requested_value = value",
      parameters = list(value = value)
    )
    fun <- "fabric_kql_query"
  } else if (identical(service, "dax")) {
    fixed <- list(workspace_id = playground_env("OAUTHDB_FABRIC_WORKSPACE"), dataset_id = playground_env("OAUTHDB_FABRIC_MODEL"))
    native_args <- function(value) list(dax = "EVALUATE ROW(\"Connected\", 1)", result = "tibble")
    fun <- "fabric_pbi_dax_query"
  } else if (identical(service, "graphql")) {
    fixed <- list(api = playground_env("OAUTHDB_GRAPHQL_API"), workspace_id = playground_env("OAUTHDB_FABRIC_WORKSPACE", ""))
    if (!nzchar(fixed$workspace_id)) fixed$workspace_id <- NULL
    configured_hosts <- trimws(playground_env("OAUTHDB_GRAPHQL_ENDPOINT_HOSTS", ""))
    if (nzchar(configured_hosts)) endpoint_hosts <- strsplit(configured_hosts, "[[:space:]]+")[[1L]]
    # Configure a read-only query document appropriate for your API. It stays
    # server-side and is never edited in the browser.
    query <- playground_env("OAUTHDB_GRAPHQL_QUERY", "query Playground { __typename }")
    native_args <- function(value) list(query = query, error_policy = "error")
    fun <- "fabric_graphql_query"
  } else if (identical(service, "onelake")) {
    fixed <- list(workspace = playground_env("OAUTHDB_FABRIC_WORKSPACE"), item = playground_env("OAUTHDB_ONELAKE_ITEM"))
    path <- playground_env("OAUTHDB_ONELAKE_PATH", "Files")
    native_args <- function(value) list(path = path, recursive = FALSE)
    fun <- "fabric_onelake_list"
  } else if (identical(service, "discovery")) {
    service <- "fabric"
    native_args <- function(value) list()
    fun <- "fabric_workspaces"
  } else {
    stop("Unknown playground backend.", call. = FALSE)
  }
  source <- do.call(shinyOAuthDB::oauth_db_fabric,
                    c(list(service = service, endpoint_hosts = endpoint_hosts), fixed))
  bindings <- fixed
  if (identical(service, "fabric")) bindings$output <- "list"
  operation <- getExportedValue("fabricQueryR", fun)
  list(
    title = backend, source = source, provider = "microsoft",
    package = "fabricQueryR", fun = fun, native_args = native_args,
    sync = function(db, args) do.call(operation, c(bindings, list(token = db$token_provider()), args)),
    note = sprintf("%s retains request and result semantics. This app only supplies the selected user's delegated credentials.", fun)
  )
}

playground_auth_factory <- function(client) {
  function(input, output, session) {
    shinyOAuth::oauth_module_server("auth", client, auto_redirect = FALSE,
                                   async = TRUE, refresh_proactively = TRUE)
  }
}

# Injectable factories allow offline Shiny smoke tests without browser grants,
# actual database drivers, or network activity.
playground_server <- function(spec, client = NULL,
                              auth_factory = playground_auth_factory(client),
                              db_factory = shinyOAuthDB::oauth_db_session,
                              task_factory = shinyOAuthDB::oauth_db_task,
                              executor = "mirai") {
  force(spec)
  force(auth_factory)
  force(db_factory)
  force(task_factory)
  function(input, output, session) {
    auth <- auth_factory(input, output, session)
    authorization <- shiny::reactive(auth$connection())
    db <- db_factory(spec$source, authorization = authorization, session = session,
                     connection_policy = "session")
    operation <- getExportedValue(spec$package, spec$fun)
    task_error <- NULL
    task <- tryCatch(task_factory(db, operation, executor = executor,
                                  effect = "read", pending = "latest"),
                     error = function(e) {
                       task_error <<- "Background execution is unavailable for this source or executor; see oauth_db_capabilities(source)."
                       NULL
                     })
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
      }
    }, ignoreNULL = FALSE, priority = 100)
    shiny::observeEvent(input$login, auth$request_login())
    shiny::observeEvent(input$logout, auth$logout())
    invocation_args <- function() {
      value <- input$value
      shiny::req(is.numeric(value), length(value) == 1L, is.finite(value),
                 value >= 0, value <= 1000000, value == floor(value))
      spec$native_args(as.integer(value))
    }
    shiny::observeEvent(input$run_sync, {
      captured_owner <- owner()
      shiny::req(captured_owner)
      last_result(NULL)
      last_error(NULL)
      tryCatch({
        value <- suppressWarnings(suppressMessages(spec$sync(db, invocation_args())))
        if (identical(captured_owner, owner())) {
          last_result(list(owner = captured_owner, value = value))
        }
      }, error = function(e) {
        if (identical(captured_owner, owner())) {
          # Keep raw upstream conditions and request details out of the UI.
          last_error(list(owner = captured_owner,
                          message = "The operation failed. Check the selected user's grants, source setup, and server-side diagnostics."))
        }
      })
    })
    shiny::observeEvent(input$run_async, {
      shiny::req(task, owner())
      do.call(task$invoke, invocation_args())
    })
    shiny::observeEvent(input$cancel, if (!is.null(task)) task$cancel())
    sync_result <- shiny::reactive({
      result <- last_result()
      shiny::req(result, identical(result$owner, owner()))
      result$value
    })
    output$status <- shiny::renderPrint(db$status())
    output$sync_error <- shiny::renderText({
      error <- last_error()
      shiny::req(error, identical(error$owner, owner()))
      error$message
    })
    output$sync_result <- shiny::renderPrint(sync_result())
    output$async_status <- shiny::renderPrint(if (is.null(task)) task_error else task$status())
    output$async_result <- shiny::renderPrint({ shiny::req(task); task$result() })
    # Used by testServer; these are local variables, never global user data.
    invisible(list(db = db, task = task, sync_result = sync_result))
  }
}

playground_ui <- function(spec) {
  shiny::fluidPage(
    shiny::titlePanel(paste("shinyOAuthDB:", spec$title)),
    shiny::p(spec$note),
    shiny::actionButton("login", "Sign in"),
    shiny::actionButton("logout", "Sign out"),
    shiny::numericInput("value", "Bound example value", 7L, min = 0, max = 1000000, step = 1),
    shiny::actionButton("run_sync", "Run native call"),
    shiny::actionButton("run_async", "Run in background"),
    shiny::actionButton("cancel", "Discard background result"),
    shiny::h4("Connection status"), shiny::verbatimTextOutput("status"),
    shiny::h4("Native result"), shiny::textOutput("sync_error"), shiny::verbatimTextOutput("sync_result"),
    shiny::h4("Background status and result"),
    shiny::verbatimTextOutput("async_status"), shiny::verbatimTextOutput("async_result")
  )
}

oauth_db_playground <- function(backend, executor = "mirai") {
  playground_require("shiny")
  playground_require("shinyOAuth")
  spec <- playground_spec(backend)
  client <- playground_client(spec$source, spec$provider)
  ui <- shinyOAuth::oauth_ui(playground_ui(spec), id = "auth", client = client)
  shiny::shinyApp(ui, playground_server(spec, client, executor = executor), uiPattern = ".*")
}

run_oauth_db_playground <- function(backend) {
  # Choose and configure one executor once, outside server().
  executor <- playground_env("OAUTHDB_EXECUTOR", "mirai")
  if (identical(executor, "mirai")) {
    playground_require("mirai")
    mirai::daemons(2L)
    on.exit(mirai::daemons(0L), add = TRUE)
  } else if (identical(executor, "future")) {
    playground_require("future")
    old_plan <- future::plan(future::multisession, workers = 2L)
    on.exit(future::plan(old_plan), add = TRUE)
  } else stop("OAUTHDB_EXECUTOR must be 'mirai' or 'future'.", call. = FALSE)
  port <- suppressWarnings(as.integer(playground_env("OAUTHDB_PORT", "8100")))
  if (is.na(port) || port < 1L || port > 65535L) stop("OAUTHDB_PORT must be a valid TCP port.", call. = FALSE)
  message("Open the exact OAUTHDB_REDIRECT_URI in your browser to use this app.")
  shiny::runApp(oauth_db_playground(backend, executor), host = "127.0.0.1", port = port, launch.browser = FALSE)
}
