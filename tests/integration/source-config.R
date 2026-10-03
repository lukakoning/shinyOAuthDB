# Configuration for the opt-in CLI transport tests; no Shiny app factories.
# The standalone playground apps show their own configuration and native calls.

live_require <- function(package) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop(sprintf("Install '%s' before running the live transport check.", package), call. = FALSE)
  }
}

live_env <- function(name, default = NULL, required = is.null(default)) {
  value <- Sys.getenv(name, unset = if (is.null(default)) "" else default)
  if (required && !nzchar(value)) {
    stop(sprintf("Set %s before running the live transport check.", name), call. = FALSE)
  }
  value
}

live_client <- function(source, provider = "microsoft") {
  redirect_uri <- live_env("OAUTHDB_REDIRECT_URI", "http://localhost:8100")
  if (identical(provider, "microsoft")) {
    return(shinyOAuthDB::oauth_db_microsoft_client(
      sources = list(source),
      tenant_id = live_env("OAUTHDB_TENANT_ID"),
      client_id = live_env("OAUTHDB_CLIENT_ID"),
      client_secret = live_env("OAUTHDB_CLIENT_SECRET", ""),
      redirect_uri = redirect_uri
    ))
  }
  if (identical(provider, "databricks")) {
    # Reuse brickster's actual public OAuth provider rather than maintaining
    # another workspace discovery implementation here.
    secret <- live_env("OAUTHDB_CLIENT_SECRET", "")
    return(shinyOAuth::oauth_client(
      provider = brickster::db_oauth_provider(
        host = live_env("OAUTHDB_DATABRICKS_HOST"),
        token_auth_style = if (nzchar(secret)) "header" else "public"
      ),
      client_id = live_env("OAUTHDB_CLIENT_ID"),
      client_secret = secret,
      redirect_uri = redirect_uri,
      scopes = c("openid", "profile", "offline_access", "sql")
    ))
  }
  stop("Unknown live transport provider.", call. = FALSE)
}

# The specification is operator configuration. No browser input changes an
# endpoint, role, OAuth target, SQL text, GraphQL document, or DAX expression.
live_spec <- function(backend) {
  live_require("shinyOAuthDB")
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
    live_require("DBI")
    live_require("odbc")
    driver <- live_env("OAUTHDB_SQL_DRIVER", "ODBC Driver 18 for SQL Server")
    database <- live_env("OAUTHDB_DATABASE")
    server <- live_env("OAUTHDB_SERVER")
    if (identical(backend, "azure-sql")) {
      source <- shinyOAuthDB::oauth_db_azure_sql(server, database, driver = driver)
    } else if (identical(backend, "sql-server")) {
      enabled <- identical(live_env("OAUTHDB_SQL_SERVER_ENTRA_ENABLED", "false"), "true")
      source <- shinyOAuthDB::oauth_db_sql_server(server, database, driver = driver, entra_enabled = enabled)
    } else {
      live_require("fabricQueryR")
      source <- shinyOAuthDB::oauth_db_fabric_sql(server, database, driver = driver)
    }
    return(sql_spec(source, "SELECT CURRENT_USER AS database_user, CAST(? AS int) AS requested_value"))
  }
  if (identical(backend, "azure-postgres")) {
    live_require("DBI")
    live_require("RPostgres")
    source <- shinyOAuthDB::oauth_db_azure_postgres(
      host = live_env("OAUTHDB_POSTGRES_HOST"),
      database = live_env("OAUTHDB_DATABASE"),
      user = live_env("OAUTHDB_POSTGRES_USER"),
      sslrootcert = live_env("OAUTHDB_POSTGRES_SSLROOTCERT")
    )
    return(sql_spec(source, "SELECT current_user AS database_user, $1::integer AS requested_value"))
  }
  if (identical(backend, "snowflake")) {
    live_require("DBI")
    live_require("odbc")
    source <- shinyOAuthDB::oauth_db_snowflake(
      server = live_env("OAUTHDB_SNOWFLAKE_SERVER"),
      database = live_env("OAUTHDB_DATABASE"),
      schema = live_env("OAUTHDB_SNOWFLAKE_SCHEMA"),
      warehouse = live_env("OAUTHDB_SNOWFLAKE_WAREHOUSE"),
      role = live_env("OAUTHDB_SNOWFLAKE_ROLE"),
      driver = live_env("OAUTHDB_SNOWFLAKE_DRIVER", "SnowflakeDSIIDriver"),
      auth_mode = "external_oauth", provider_family = "microsoft",
      resource = live_env("OAUTHDB_SNOWFLAKE_RESOURCE"),
      scopes = strsplit(live_env("OAUTHDB_SNOWFLAKE_SCOPES"), " +")[[1L]]
    )
    return(sql_spec(source, "SELECT CURRENT_USER() AS database_user, CURRENT_ROLE() AS database_role, CAST(? AS INTEGER) AS requested_value"))
  }
  if (identical(backend, "databricks")) {
    live_require("brickster")
    host <- live_env("OAUTHDB_DATABRICKS_HOST")
    warehouse <- live_env("OAUTHDB_DATABRICKS_WAREHOUSE")
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

  live_require("fabricQueryR")
  service <- sub("^fabric-", "", backend)
  fixed <- list()
  endpoint_hosts <- character()
  if (identical(service, "kql")) {
    fixed <- list(cluster = live_env("OAUTHDB_KQL_CLUSTER"), database = live_env("OAUTHDB_KQL_DATABASE"))
    native_args <- function(value) list(
      query = "declare query_parameters(value:int); print requested_value = value",
      parameters = list(value = value)
    )
    fun <- "fabric_kql_query"
  } else if (identical(service, "dax")) {
    fixed <- list(workspace_id = live_env("OAUTHDB_FABRIC_WORKSPACE"), dataset_id = live_env("OAUTHDB_FABRIC_MODEL"))
    native_args <- function(value) list(dax = "EVALUATE ROW(\"Connected\", 1)", result = "tibble")
    fun <- "fabric_pbi_dax_query"
  } else if (identical(service, "graphql")) {
    fixed <- list(api = live_env("OAUTHDB_GRAPHQL_API"), workspace_id = live_env("OAUTHDB_FABRIC_WORKSPACE", ""))
    if (!nzchar(fixed$workspace_id)) fixed$workspace_id <- NULL
    configured_hosts <- trimws(live_env("OAUTHDB_GRAPHQL_ENDPOINT_HOSTS", ""))
    if (nzchar(configured_hosts)) endpoint_hosts <- strsplit(configured_hosts, "[[:space:]]+")[[1L]]
    # Configure a read-only query document appropriate for your API. It stays
    # server-side and is never edited in the browser.
    query <- live_env("OAUTHDB_GRAPHQL_QUERY", "query Playground { __typename }")
    native_args <- function(value) list(query = query, error_policy = "error")
    fun <- "fabric_graphql_query"
  } else if (identical(service, "onelake")) {
    fixed <- list(workspace = live_env("OAUTHDB_FABRIC_WORKSPACE"), item = live_env("OAUTHDB_ONELAKE_ITEM"))
    path <- live_env("OAUTHDB_ONELAKE_PATH", "Files")
    native_args <- function(value) list(path = path, recursive = FALSE)
    fun <- "fabric_onelake_list"
  } else if (identical(service, "discovery")) {
    service <- "fabric"
    native_args <- function(value) list()
    fun <- "fabric_workspaces"
  } else {
    stop("Unknown live transport backend.", call. = FALSE)
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
