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
  if (identical(spec$auth_mode, "google")) return(do.call(shinyOAuthDB::oauth_db_bigquery_client, args))
  if (identical(spec$auth_mode, "snowflake_oauth")) {
    return(do.call(shinyOAuthDB::oauth_db_snowflake_client, c(list(
      server = live_env("OAUTHDB_SNOWFLAKE_SERVER"), role = live_env("OAUTHDB_SNOWFLAKE_ROLE")), args)))
  }
  if (identical(spec$auth_mode, "oidc")) return(do.call(shinyOAuth::oauth_client, c(list(
    provider = shinyOAuth::oauth_provider_oidc_discover(live_env("OAUTHDB_OIDC_ISSUER")),
    scopes = strsplit(live_env("OAUTHDB_SCOPES", "openid profile database.read"), " +")[[1L]]), args)))
  if (identical(spec$service, "databricks")) {
    return(do.call(shinyOAuthDB::oauth_db_databricks_client,
      c(list(host = live_env("OAUTHDB_DATABRICKS_HOST")), args)))
  }
  if (identical(spec$service, "snowflake")) {
    scopes <- strsplit(live_env("OAUTHDB_SNOWFLAKE_SCOPES"), " +")[[1L]]
    return(do.call(shinyOAuth::oauth_client, c(list(
      provider = shinyOAuth::oauth_provider_microsoft(tenant = live_env("OAUTHDB_TENANT_ID")),
      scopes = c("openid", "profile", scopes),
      token_targets = list(snowflake = list(resource = live_env("OAUTHDB_SNOWFLAKE_RESOURCE"), scopes = scopes)),
      token_target_default = "snowflake"), args)))
  }
  do.call(shinyOAuthDB::oauth_db_microsoft_client,
    c(list(services = spec$service, tenant_id = live_env("OAUTHDB_TENANT_ID")), args))
}

live_spec <- function(backend) {
  spec <- live_backend_spec(backend)
  spec$route <- backend
  if (is.null(spec$auth_mode)) spec$auth_mode <- "entra"
  if (is.null(spec$retires_handle)) spec$retires_handle <- TRUE
  spec
}

live_backend_spec <- function(backend) {
  live_require("shinyOAuthDB")
  if (identical(backend, "bigquery")) return(live_bigquery_spec())
  sql_spec <- function(bind, query, service = "sql", helper = "oauth_db_azure_sql") list(
    helper = helper,
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
      "SELECT CURRENT_USER AS database_user, CAST(? AS int) AS requested_value",
      helper = if (backend == "fabric-sql") "oauth_db_fabric_sql" else
        if (backend == "sql-server") "oauth_db_sql_server" else "oauth_db_azure_sql"))
  }
  if (backend == "azure-postgres") {
    fixed <- list(host = live_env("OAUTHDB_POSTGRES_HOST"), dbname = live_env("OAUTHDB_DATABASE"),
      user = live_env("OAUTHDB_POSTGRES_USER"), sslrootcert = live_env("OAUTHDB_POSTGRES_SSLROOTCERT"))
    return(sql_spec(function(auth) do.call(shinyOAuthDB::oauth_db_azure_postgres,
      c(list(authorization = auth), fixed)),
      "SELECT current_user AS database_user, $1::integer AS requested_value", "postgres", "oauth_db_azure_postgres"))
  }
  if (backend %in% c("snowflake", "snowflake-external", "snowflake-native")) {
    native <- backend == "snowflake-native"
    fixed <- list(server = live_env("OAUTHDB_SNOWFLAKE_SERVER"), database = live_env("OAUTHDB_DATABASE"),
      schema = live_env("OAUTHDB_SNOWFLAKE_SCHEMA"), warehouse = live_env("OAUTHDB_SNOWFLAKE_WAREHOUSE"),
      role = live_env("OAUTHDB_SNOWFLAKE_ROLE"), driver = live_env("OAUTHDB_SNOWFLAKE_DRIVER", "SnowflakeDSIIDriver"),
      required_scopes = if (native) paste0("session:role:", live_env("OAUTHDB_SNOWFLAKE_ROLE")) else
        strsplit(live_env("OAUTHDB_SNOWFLAKE_SCOPES"), " +")[[1L]], target = if (native) NULL else "snowflake")
    spec <- sql_spec(function(auth) do.call(shinyOAuthDB::oauth_db_snowflake,
      c(list(authorization = auth), fixed)),
      "SELECT CURRENT_USER() AS database_user, CURRENT_ROLE() AS database_role, CAST(? AS INTEGER) AS requested_value",
      "snowflake", "oauth_db_snowflake")
    spec$auth_mode <- if (native) "snowflake_oauth" else "external_oauth"
    return(spec)
  }
  if (backend %in% c("databricks", "databricks-dbi", "databricks-api", "databricks-dbi-entra", "databricks-api-entra")) {
    live_require("brickster")
    host <- sub("/$", "", sub("^https://", "", live_env("OAUTHDB_DATABRICKS_HOST")))
    warehouse <- live_env("OAUTHDB_DATABRICKS_WAREHOUSE")
    entra <- endsWith(backend, "-entra")
    api_route <- startsWith(backend, "databricks-api")
    mode <- if (entra) "entra" else "databricks_oauth"
    return(list(service = if (entra) "databricks_entra" else "databricks", auth_mode = mode,
      helper = if (api_route) "oauth_db_databricks_api" else "oauth_db_databricks",
      # brickster stores bearer strings in stateless handles; disconnect is a no-op.
      retires_handle = FALSE,
      bind = if (api_route) function(auth) {
        api <- shinyOAuthDB::oauth_db_databricks_api(auth, host, auth_mode = mode)
        function() api
      } else function(auth) shinyOAuthDB::oauth_db_databricks(auth, host, warehouse,
        auth_mode = mode, disposition = "INLINE", show_progress = FALSE),
      native_args = function(value) list(
        statement = "SELECT current_user() AS database_user, CAST(:value AS INT) AS requested_value",
        parameters = list(list(name = "value", value = as.character(value), type = "INT")),
        disposition = "INLINE", show_progress = FALSE),
      query = if (api_route) function(native, args) do.call(native$call,
        c(list(.fn = brickster::db_sql_query, warehouse_id = warehouse), args)) else
        function(native, args) {
          args$disposition <- args$show_progress <- NULL
          do.call(DBI::dbGetQuery, c(list(conn = native), args))
        }))
  }

  if (backend %in% c("redshift", "redshift-access-token")) {
    fixed <- list(server = live_env("OAUTHDB_SERVER"), database = live_env("OAUTHDB_DATABASE"),
      driver = live_env("OAUTHDB_REDSHIFT_DRIVER", "Amazon Redshift (x64)"),
      token_type = if (backend == "redshift-access-token") "ACCESS_TOKEN" else "EXT_JWT")
    spec <- sql_spec(function(auth) do.call(shinyOAuthDB::oauth_db_redshift,
      c(list(authorization = auth), fixed)), "SELECT current_user AS database_user, CAST(? AS INTEGER) AS requested_value",
      "redshift", "oauth_db_redshift")
    spec$auth_mode <- "oidc"
    return(spec)
  }

  live_require("fabricQueryR")
  service <- sub("^fabric-(api-)?", "", backend)
  if (service == "resource") return(list(service = c("fabric", "onelake"),
    helper = "oauth_db_fabric_api/fabric_item", retires_handle = FALSE, pinned_resource = TRUE,
    bind = function(auth) {
      api <- shinyOAuthDB::oauth_db_fabric_api(auth, targets = list(fabric = "fabric", onelake = "storage"))
      shiny::reactive(api$call(fabricQueryR::fabric_item,
        workspace = live_env("OAUTHDB_FABRIC_WORKSPACE"), item = live_env("OAUTHDB_ONELAKE_ITEM")))
    }, native_args = function(value) list(table = live_env("OAUTHDB_ONELAKE_TABLE"), limit = 20L),
    query = function(native, args) do.call(native$read_table, args)))
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

  target <- c(fabric = "fabric", kql = "kusto", dax = "power_bi", graphql = "power_bi", onelake = "storage")[[service]]
  list(service = service, helper = "oauth_db_fabric_api", retires_handle = FALSE,
    bind = function(auth) {
      api <- shinyOAuthDB::oauth_db_fabric_api(auth, targets = stats::setNames(list(target), service))
      function() api
    },
    native_args = native_args,
    query = function(native, args) do.call(native$call, c(list(.fn = operation), fixed, args)))
}
