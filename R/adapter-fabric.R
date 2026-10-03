#' Describe a Fabric SQL endpoint
#'
#' Reuses fabricQueryR's public connector for endpoint handling, TLS, native
#' token injection and conversions. It returns the existing backend connection.
#' @inheritParams oauth_db_azure_sql
#' @param backend Native `"odbc"` or `"adbc"` transport handled by fabricQueryR.
#' @param target_type Fabric item type, or `"auto"`.
#' @param options Supported fabricQueryR connector options.
#' @returns An `oauth_db_source` descriptor.
#' @export
oauth_db_fabric_sql <- function(
  server,
  database,
  target = "sql",
  driver = "ODBC Driver 18 for SQL Server",
  port = 1433L,
  backend = c("odbc", "adbc"),
  target_type = "auto",
  scopes = "https://database.windows.net//user_impersonation",
  options = list()
) {
  backend <- match.arg(backend)
  target_type <- match.arg(
    target_type,
    c(
      "auto",
      "lakehouse",
      "warehouse",
      "sql_database",
      "sql_analytics_endpoint"
    )
  )

  .odb_source_string(database, "database")
  .odb_source_string(driver, "driver")

  .odb_source_odbc_value(database)
  .odb_source_odbc_value(driver)
  config <- list(
    service = "sql",
    server = .odb_source_host(server),
    database = database,
    odbc_driver = driver,
    port = .odb_source_port(port),
    backend = backend,
    target_type = target_type,
    endpoint_hosts = character(),
    options = .odb_source_odbc_options(
      options,
      c(
        "adbc_driver",
        "timeout",
        "read_only",
        "verbose",
        "max_tries",
        "retry_delay"
      )
    )
  )

  .odb_new_source(
    "fabric_sql",
    config,
    "microsoft",
    target,
    "https://database.windows.net/",
    scopes,
    capabilities = .odb_sql_capabilities("fabricQueryR"),
    protected_args = c(
      .odb_sql_protected,
      "odbc_driver",
      "adbc_driver",
      "backend",
      "target_type",
      "sql_token",
      "encrypt",
      "trust_server_certificate",
      "tenant_id",
      "client_id"
    )
  )
}

.odb_fabric_profile <- function(service) {
  switch(
    service,
    fabric = list(
      resource = "https://api.fabric.microsoft.com",
      target = "fabric",
      scopes = c("Workspace.Read.All", "Item.Read.All")
    ),
    sql = list(
      resource = "https://database.windows.net/",
      target = "sql",
      scopes = "user_impersonation"
    ),
    dax = list(
      resource = "https://analysis.windows.net/powerbi/api",
      target = "power_bi",
      scopes = "Dataset.Read.All"
    ),
    kql = list(
      resource = "https://api.kusto.windows.net",
      target = "kusto",
      scopes = "user_impersonation"
    ),
    onelake = list(
      resource = "https://storage.azure.com",
      target = "storage",
      scopes = "user_impersonation"
    ),
    graphql = list(
      resource = "https://analysis.windows.net/powerbi/api",
      target = "power_bi",
      scopes = "GraphQLApi.Execute.All"
    )
  )
}

#' Describe one Fabric API service
#'
#' Configure known endpoints and item IDs using the native package's argument
#' names. Each source selects one token resource. Discovery is optional when
#' endpoints are known. Endpoint policy is constructed and enforced by the
#' public fabricQueryR credential provider, including secondary request URLs.
#' @param service `"fabric"` (discovery), `"sql"`, `"dax"`, `"kql"`, `"onelake"`
#'   or `"graphql"`. Use [oauth_db_fabric_sql()] for SQL connector options.
#' @param target Declared shinyOAuth target, defaulting to the service profile.
#' @param scopes Fully qualified delegated scopes, defaulting to this service's
#'   read/query requirements. Consent does not replace data-plane permissions.
#' @param cluster,database KQL endpoint and database; SQL server and database.
#' @param server SQL hostname when `service = "sql"`.
#' @param workspace,item Configured discovery or OneLake identifiers/names.
#' @param workspace_id,dataset_id,connstr Native DAX semantic-model target.
#' @param api Native GraphQL API endpoint or item identifier.
#' @param api_base Optional explicitly trusted Fabric/Power BI API base URL.
#' @param dfs_base OneLake endpoint; default is the Microsoft public service.
#' @param endpoint_hosts Additional explicitly trusted exact hostnames, needed
#'   for custom gateways. Never obtain these settings from browser input.
#' @returns An `oauth_db_source` descriptor.
#' @export
oauth_db_fabric <- function(
  service = c("fabric", "sql", "dax", "kql", "onelake", "graphql"),
  target = NULL,
  scopes = NULL,
  cluster = NULL,
  database = NULL,
  server = NULL,
  workspace = NULL,
  item = NULL,
  workspace_id = NULL,
  dataset_id = NULL,
  connstr = NULL,
  api = NULL,
  api_base = NULL,
  dfs_base = "https://onelake.dfs.fabric.microsoft.com",
  endpoint_hosts = character()
) {
  service <- match.arg(service)
  profile <- .odb_fabric_profile(service)
  if (is.null(target)) {
    target <- profile$target
  }
  if (is.null(scopes)) {
    scopes <- paste0(profile$resource, "/", profile$scopes)
  }
  if (
    !is.character(endpoint_hosts) ||
      anyNA(endpoint_hosts) ||
      !all(grepl("^[A-Za-z0-9][A-Za-z0-9.-]*$", endpoint_hosts))
  ) {
    .odb_source_error(
      "endpoint_hosts must contain exact trusted hostnames without schemes, paths or wildcards."
    )
  }
  for (name in c(
    "cluster",
    "database",
    "workspace",
    "item",
    "workspace_id",
    "dataset_id",
    "connstr",
    "api",
    "api_base"
  )) {
    .odb_source_string(get(name), name, TRUE)
  }
  if (service == "sql") {
    source <- oauth_db_fabric_sql(
      server,
      database,
      target = target,
      scopes = scopes
    )
    source$config$endpoint_hosts <- tolower(endpoint_hosts)
    source$id <- paste0(
      source$backend,
      ":",
      digest::digest(
        unclass(source)[setdiff(names(source), "id")],
        algo = "sha256"
      )
    )

    return(source)
  }
  if (service == "kql") {
    cluster <- .odb_source_origin(cluster, "cluster")
    .odb_source_string(database, "database")
  }
  if (
    service == "dax" &&
      is.null(connstr) &&
      (is.null(workspace_id) || is.null(dataset_id))
  ) {
    .odb_source_error("DAX needs connstr or both workspace_id and dataset_id.")
  }
  if (service == "graphql") {
    .odb_source_string(api, "api")
  }
  if (service == "onelake") {
    .odb_source_string(workspace, "workspace")
    .odb_source_string(item, "item")

    dfs_base <- .odb_source_origin(dfs_base, "dfs_base")
  }
  if (is.null(api_base)) {
    api_base <- if (service == "dax") {
      "https://api.powerbi.com/v1.0/myorg"
    } else {
      "https://api.fabric.microsoft.com"
    }
  }

  config <- list(
    service = service,
    cluster = cluster,
    database = database,
    workspace = workspace,
    item = item,
    workspace_id = workspace_id,
    dataset_id = dataset_id,
    connstr = connstr,
    api = api,
    api_base = api_base,
    dfs_base = dfs_base,
    endpoint_hosts = tolower(endpoint_hosts)
  )
  capabilities <- list(
    native_dbi = FALSE,
    sql = FALSE,
    transactions = FALSE,
    async_strategy = "worker_credential",
    connector_package = "fabricQueryR",
    connection_reuse = "credential_provider",
    token_refresh = "per_request",
    query_deadline = FALSE,
    remote_cancellation = FALSE,
    delegated_user = TRUE,
    live_verified = FALSE
  )

  .odb_new_source(
    "fabric",
    config,
    "microsoft",
    target,
    profile$resource,
    scopes,
    capabilities = capabilities,
    protected_args = c(
      .odb_sql_protected,
      "sql_token",
      "storage_token",
      "fabric_token",
      "audience",
      "tenant_id",
      "client_id",
      "cluster",
      "workspace",
      "item",
      "workspace_id",
      "dataset_id",
      "connstr",
      "api",
      "api_base",
      "dfs_base",
      "workspace_name",
      "lakehouse_name",
      "impersonated_user",
      "output",
      "perform_request"
    )
  )
}

.odb_fabric_token_provider <- function(source, credential_fun) {
  .odb_require("fabricQueryR", "Fabric credential providers")
  if (!"fabric_token_provider" %in% getNamespaceExports("fabricQueryR")) {
    .odb_abort(
      "Install fabricQueryR with the public fabric_token_provider() hook to preserve endpoint policy for delegated sessions and workers.",
      "unsupported_dependency"
    )
  }

  service <- source$config$service

  # Preserve fabricQueryR's service and endpoint checks around the token callback.
  fabricQueryR::fabric_token_provider(
    token = function(audience, force_refresh = FALSE) {
      credential_fun(force_refresh = force_refresh, async = FALSE)
    },
    services = service,
    scopes = stats::setNames(list(source$auth$scopes), service),
    endpoint_hosts = stats::setNames(
      list(source$config$endpoint_hosts),
      service
    )
  )
}

.odb_fabric_connect <- function(source, token_provider) {
  .odb_require("fabricQueryR", "Fabric SQL connections")

  config <- source$config
  args <- config[c(
    "server",
    "database",
    "port",
    "backend",
    "target_type",
    "odbc_driver"
  )]
  args$token <- token_provider
  args$encrypt <- "yes"
  args$trust_server_certificate <- "no"

  do.call(fabricQueryR::fabric_sql_connect, c(args, config$options))
}

.odb_fabric_operation_bindings <- function(source, fun) {
  config <- source$config
  select <- switch(
    fun,
    fabric_workspaces = c("api_base"),
    fabric_items = c("workspace", "api_base"),
    fabric_kql_query = c("cluster", "database"),
    fabric_pbi_dax_query = c(
      "connstr",
      "workspace_id",
      "dataset_id",
      "api_base"
    ),
    fabric_graphql_query = c("api", "workspace_id", "api_base"),
    fabric_onelake_list = c("workspace", "item", "dfs_base"),
    fabric_onelake_read_file = c("workspace", "item", "dfs_base"),
    fabric_onelake_read_delta_table = c("dfs_base"),
    fabric_sql_query = c(
      "server",
      "database",
      "port",
      "backend",
      "target_type",
      "odbc_driver"
    ),
    character()
  )
  bindings <- config[select]
  bindings <- bindings[!vapply(bindings, is.null, logical(1))]
  if (fun %in% c("fabric_workspaces", "fabric_items")) {
    bindings$output <- "list"
  }
  if (fun == "fabric_onelake_read_delta_table") {
    bindings$workspace_name <- config$workspace
    bindings$lakehouse_name <- config$item
  }
  if (identical(fun, "fabric_sql_query")) {
    bindings$encrypt <- "yes"
    bindings$trust_server_certificate <- "no"
    bindings <- c(bindings, config$options)
  }

  bindings
}
