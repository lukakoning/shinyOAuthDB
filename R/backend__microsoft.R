#' Configure a native shinyOAuth Microsoft client for database services
#'
#' Optional presets returning ordinary `shinyOAuth::oauth_client()` objects.
#' Use them with any shinyOAuth module or connection manager, or configure
#' shinyOAuth directly. These helpers create no login module or database
#' connection. Explicit settings replace defaults rather than being merged.
#' @param services Service names: `sql`, `postgres`, `fabric`, `kql`, `dax`,
#'   `graphql`, `onelake` or `databricks_entra`. The first selects the default
#'   token target. Compatible services sharing a resource combine their scopes.
#' @param tenant_id Microsoft Entra tenant. Unused when `provider` is supplied.
#' @param client_id Registered application ID.
#' @param redirect_uri Registered OAuth callback URL.
#' @param client_secret Confidential client secret, or NULL for a public client.
#' @param provider Native shinyOAuth provider. Defaults to the service's provider.
#' @param scopes Complete client consent scopes, replacing the preset defaults.
#' @param token_targets Named shinyOAuth token targets, replacing the service
#'   defaults. Use `list()` for a client without named targets.
#' @param default_token_target Default target name, or `character()` for none.
#' @param ... Settings passed unchanged to `shinyOAuth::oauth_client()`, such as
#'   `label`, `resource`, `required_scopes`, or `scope_validation`.
#' @details Keep the backend accessor's `target` and `scopes` consistent with
#'   your client configuration. For provider-only configuration, use
#'   `shinyOAuth::oauth_provider_microsoft()`, [oauth_db_databricks_provider()],
#'   or [oauth_db_snowflake_provider()] with `shinyOAuth::oauth_client()`.
#' @return A native shinyOAuth client for its existing UI and server modules.
#' @export
oauth_db_microsoft_client <- function(
  services = "sql", tenant_id, client_id, redirect_uri, client_secret = NULL, ...,
  provider = shinyOAuth::oauth_provider_microsoft(
    tenant = tenant_id, id_token_validation = TRUE, userinfo_required = FALSE),
  token_targets = .odb_microsoft_targets(services),
  default_token_target = if (length(token_targets)) names(token_targets)[[1L]] else character(),
  scopes = c("openid", "profile", "offline_access",
    unique(unlist(lapply(token_targets, `[[`, "scopes"), use.names = FALSE)))
) {
  .odb_oauth_client(provider, client_id, redirect_uri, client_secret,
    scopes = scopes, token_targets = token_targets,
    default_token_target = default_token_target, ...)
}

.odb_microsoft_targets <- function(services) {
  profiles <- c(.odb_sql_server_profiles(), .odb_postgres_profiles(),
                .odb_fabric_profiles(), .odb_databricks_profiles())
  if (!is.character(services) || !length(services) || anyNA(services) ||
      any(!services %in% names(profiles))) {
    .odb_abort("Choose one or more supported Microsoft services.")
  }
  targets <- list()
  for (service in unique(services)) {
    profile <- profiles[[service]]
    previous <- targets[[profile$target]]
    scopes <- union(previous$scopes, profile$scopes)
    targets[[profile$target]] <- list(resource = profile$resource, scopes = scopes,
                                     required_scopes = .odb_microsoft_scopes(scopes))
  }
  targets
}

# Microsoft consent recipes are supplied by each backend; only composition and
# Microsoft's resource-qualified scope convention belong here.
.odb_microsoft_profile <- function(target, resource, permissions) {
  list(target = target, resource = resource, scopes = paste0(resource, "/", permissions))
}

.odb_microsoft_scopes <- function(scopes) {
  scopes <- .odb_scopes(scopes)
  scopes[!endsWith(scopes, "/.default")]
}
