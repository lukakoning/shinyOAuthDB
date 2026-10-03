#' Describe a Databricks workspace or SQL warehouse
#'
#' The native brickster token provider enforces exact workspace binding. Native
#' Databricks OAuth and Entra are separate profiles; neither falls back to the
#' app host's CLI, environment, PAT or service-principal credentials.
#' @param host Workspace hostname or HTTPS origin.
#' @param warehouse_id SQL warehouse ID, or `NULL` for non-SQL REST operations.
#' @param catalog,schema Optional default SQL namespace.
#' @param auth_mode `"databricks_oauth"` or Azure Databricks `"entra"`.
#' @param target Declared shinyOAuth token-target name.
#' @param scopes Delegated scope profile; default `all-apis` for native OAuth.
#' @param options Native brickster connection options.
#' @returns An `oauth_db_source` descriptor.
#' @export
oauth_db_databricks <- function(
  host,
  warehouse_id = NULL,
  catalog = NULL,
  schema = NULL,
  auth_mode = c("databricks_oauth", "entra"),
  target = if (auth_mode[[1L]] == "entra") "databricks" else NULL,
  scopes = NULL,
  options = list()
) {
  auth_mode <- match.arg(auth_mode)
  host <- .odb_source_origin(host)
  for (name in c("warehouse_id", "catalog", "schema")) {
    .odb_source_string(get(name), name, TRUE)
  }

  resource <- if (auth_mode == "entra") {
    "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d"
  } else {
    NULL
  }
  if (is.null(scopes)) {
    scopes <- if (auth_mode == "entra") {
      paste0(resource, "/user_impersonation")
    } else {
      "all-apis"
    }
  }

  config <- list(
    host = host,
    warehouse_id = warehouse_id,
    catalog = catalog,
    schema = schema,
    auth_mode = auth_mode,
    options = .odb_source_options(
      options,
      c(
        "disposition",
        "max_active_connections",
        "fetch_timeout",
        "show_progress",
        "staging_volume"
      )
    )
  )
  capabilities <- .odb_sql_capabilities("brickster", transactions = FALSE)
  capabilities$native_dbi <- capabilities$sql <- !is.null(warehouse_id)
  capabilities$token_refresh <- "per_request"

  .odb_new_source(
    "databricks",
    config,
    if (auth_mode == "entra") "microsoft" else "databricks",
    target,
    resource,
    scopes,
    capabilities = capabilities,
    protected_args = c(
      .odb_sql_protected,
      "warehouse_id",
      "http_path",
      "staging_volume",
      "perform_request"
    )
  )
}
