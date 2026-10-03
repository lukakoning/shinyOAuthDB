# Trusted opt-in fixture configuration. bind() is called inside a Shiny session.
live_require <- function(package) {
  if (!requireNamespace(package, quietly = TRUE)) {
    stop(sprintf("Install '%s' before running the live transport check.", package), call. = FALSE)
  }
}

live_env <- function(name, default = NULL, required = is.null(default)) {
  value <- Sys.getenv(name, unset = if (is.null(default)) "" else default)
  if (required && !nzchar(value)) stop(sprintf("Set %s before running the live transport check.", name), call. = FALSE)
  value
}

live_client <- function(spec) {
  args <- list(client_id = live_env("OAUTHDB_CLIENT_ID"),
    client_secret = live_env("OAUTHDB_CLIENT_SECRET", ""),
    redirect_uri = live_env("OAUTHDB_REDIRECT_URI", "http://localhost:8100"))
  if (spec$service == "databricks") {
    return(do.call(shinyOAuthDB::oauth_db_databricks_client,
      c(list(host = live_env("OAUTHDB_DATABRICKS_HOST")), args)))
  }
  if (spec$service == "snowflake") {
    scopes <- strsplit(live_env("OAUTHDB_SNOWFLAKE_SCOPES"), " +")[[1L]]
    return(do.call(shinyOAuth::oauth_client, c(list(
      provider = shinyOAuth::oauth_provider_microsoft(tenant = live_env("OAUTHDB_TENANT_ID")),
      scopes = c("openid", "profile", scopes),
      token_targets = list(snowflake = list(resource = live_env("OAUTHDB_SNOWFLAKE_RESOURCE"), scopes = scopes)),
      default_token_target = "snowflake"), args)))
  }
  do.call(shinyOAuthDB::oauth_db_microsoft_client,
    c(list(services = spec$service, tenant_id = live_env("OAUTHDB_TENANT_ID")), args))
}

live_spec <- function(backend) {
  live_require("shinyOAuthDB")
  sql_spec <- function(bind, query, service = "sql") list(
    service = service, bind = bind,
    native_args = function(value) list(statement = query, params = list(value)),
    query = function(native, args) do.call(DBI::dbGetQuery, c(list(conn = native), args)))

  if (backend %in% c("azure-sql", "sql-server", "fabric-sql")) {
    fixed <- list(server = live_env("OAUTHDB_SERVER"), database = live_env("OAUTHDB_DATABASE"))
    driver <- live_env("OAUTHDB_SQL_DRIVER", "ODBC Driver 18 for SQL Server")
    if (backend == "fabric-sql") {
      binding <- shinyOAuthDB::oauth_db_fabric_sql
      fixed$odbc_driver <- driver
    } else {
      binding <- if (backend == "azure-sql") shinyOAuthDB::oauth_db_azure_sql else shinyOAuthDB::oauth_db_sql_server
      fixed$driver <- driver
    }
    return(sql_spec(function(auth) do.call(binding, c(list(authorization = auth), fixed)),
      "SELECT CURRENT_USER AS database_user, CAST(? AS int) AS requested_value"))
  }
  if (backend == "azure-postgres") {
    fixed <- list(host = live_env("OAUTHDB_POSTGRES_HOST"), database = live_env("OAUTHDB_DATABASE"),
      user = live_env("OAUTHDB_POSTGRES_USER"), sslrootcert = live_env("OAUTHDB_POSTGRES_SSLROOTCERT"))
    return(sql_spec(function(auth) do.call(shinyOAuthDB::oauth_db_azure_postgres,
      c(list(authorization = auth), fixed)),
      "SELECT current_user AS database_user, $1::integer AS requested_value", "postgres"))
  }
  if (backend == "snowflake") {
    fixed <- list(server = live_env("OAUTHDB_SNOWFLAKE_SERVER"), database = live_env("OAUTHDB_DATABASE"),
      schema = live_env("OAUTHDB_SNOWFLAKE_SCHEMA"), warehouse = live_env("OAUTHDB_SNOWFLAKE_WAREHOUSE"),
      role = live_env("OAUTHDB_SNOWFLAKE_ROLE"), driver = live_env("OAUTHDB_SNOWFLAKE_DRIVER", "SnowflakeDSIIDriver"),
      scopes = strsplit(live_env("OAUTHDB_SNOWFLAKE_SCOPES"), " +")[[1L]], target = "snowflake")
    return(sql_spec(function(auth) do.call(shinyOAuthDB::oauth_db_snowflake,
      c(list(authorization = auth), fixed)),
      "SELECT CURRENT_USER() AS database_user, CURRENT_ROLE() AS database_role, CAST(? AS INTEGER) AS requested_value", "snowflake"))
  }
  if (backend == "databricks") {
    host <- sub("/$", "", sub("^https://", "", live_env("OAUTHDB_DATABRICKS_HOST")))
    warehouse <- live_env("OAUTHDB_DATABRICKS_WAREHOUSE")
    return(list(service = "databricks",
      bind = function(auth) shinyOAuthDB::oauth_db_databricks(auth),
      native_args = function(value) list(
        statement = "SELECT current_user() AS database_user, CAST(:value AS INT) AS requested_value",
        parameters = list(list(name = "value", value = as.character(value), type = "INT")),
        disposition = "INLINE", show_progress = FALSE),
      query = function(native, args) do.call(brickster::db_sql_query,
        c(list(host = host, warehouse_id = warehouse, token = native), args))))
  }

  live_require("fabricQueryR")
  service <- sub("^fabric-", "", backend)
  fixed <- list()
  if (service == "kql") {
    fixed <- list(cluster = live_env("OAUTHDB_KQL_CLUSTER"), database = live_env("OAUTHDB_KQL_DATABASE"))
    native_args <- function(value) list(query = "declare query_parameters(value:int); print requested_value = value",
      parameters = list(value = value))
    operation <- fabricQueryR::fabric_kql_query
  } else if (service == "dax") {
    fixed <- list(workspace_id = live_env("OAUTHDB_FABRIC_WORKSPACE"), dataset_id = live_env("OAUTHDB_FABRIC_MODEL"))
    native_args <- function(value) list(dax = "EVALUATE ROW(\"Connected\", 1)", result = "tibble")
    operation <- fabricQueryR::fabric_pbi_dax_query
  } else if (service == "graphql") {
    fixed <- list(api = live_env("OAUTHDB_GRAPHQL_API"))
    workspace <- live_env("OAUTHDB_FABRIC_WORKSPACE", "")
    if (nzchar(workspace)) fixed$workspace_id <- workspace
    query <- live_env("OAUTHDB_GRAPHQL_QUERY", "query Playground { __typename }")
    native_args <- function(value) list(query = query, error_policy = "error")
    operation <- fabricQueryR::fabric_graphql_query
  } else if (service == "onelake") {
    fixed <- list(workspace = live_env("OAUTHDB_FABRIC_WORKSPACE"), item = live_env("OAUTHDB_ONELAKE_ITEM"))
    path <- live_env("OAUTHDB_ONELAKE_PATH", "Files")
    native_args <- function(value) list(path = path, recursive = FALSE)
    operation <- fabricQueryR::fabric_onelake_list
  } else if (service == "discovery") {
    service <- "fabric"
    fixed <- list(output = "list")
    native_args <- function(value) list()
    operation <- fabricQueryR::fabric_workspaces
  } else stop("Unknown live transport backend.", call. = FALSE)

  list(service = service,
    bind = function(auth) shinyOAuthDB::oauth_db_fabric(auth, service),
    native_args = native_args,
    query = function(native, args) do.call(operation, c(fixed, list(token = native), args)))
}
