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
#'   `shinyOAuth::oauth_provider_microsoft()`, `brickster::db_oauth_provider()`,
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
  if (!is.character(services) || !length(services) || anyNA(services) ||
      any(!services %in% c("sql", "postgres", "fabric", "kql", "dax", "graphql", "onelake", "databricks_entra"))) {
    .odb_abort("Choose one or more supported Microsoft services.")
  }
  targets <- list()
  for (service in unique(services)) {
    profile <- .odb_backend_profile(service)
    previous <- targets[[profile$target]]
    scopes <- union(previous$scopes, profile$scopes)
    targets[[profile$target]] <- list(resource = profile$resource, scopes = scopes,
                                     required_scopes = scopes[!endsWith(scopes, "/.default")])
  }
  targets
}

#' Configure a native Databricks shinyOAuth client
#' @param host Databricks workspace hostname or HTTPS origin. Unused when
#'   `provider` is supplied.
#' @inheritParams oauth_db_microsoft_client
#' @return A native shinyOAuth client. Discovery uses brickster and may make a
#'   network request. Requires its external-token/OAuth provider hooks.
#' @export
oauth_db_databricks_client <- function(
  host, client_id, redirect_uri, client_secret = NULL, ...,
  provider = .odb_databricks_provider(host, client_secret),
  scopes = c("openid", "profile", "email", "offline_access", "all-apis")
) {
  .odb_oauth_client(provider, client_id, redirect_uri, client_secret,
    scopes = scopes, ...)
}

.odb_databricks_provider <- function(host, client_secret) {
  .odb_backend_require_hook("brickster", "db_oauth_provider")
  brickster::db_oauth_provider(host,
    token_auth_style = if (is.null(client_secret) || !length(client_secret) ||
      identical(client_secret, "")) "public" else "header")
}

#' Configure a native Snowflake shinyOAuth client
#' @param server Snowflake account hostname. Unused when `provider` is supplied.
#' @param role Requested database role. Unused when `scopes` is supplied.
#' @inheritParams oauth_db_microsoft_client
#' @return A native shinyOAuth client. External OAuth instead uses its configured
#'   identity provider through shinyOAuth directly.
#' @export
oauth_db_snowflake_client <- function(
  server, client_id, client_secret, redirect_uri, role, ...,
  provider = oauth_db_snowflake_provider(server),
  scopes = c(paste0("session:role:", role), "refresh_token")
) {
  if (missing(scopes)) .odb_string(role, "role")
  .odb_oauth_client(provider, client_id, redirect_uri, client_secret, scopes = scopes, ...)
}

#' Configure a native Snowflake shinyOAuth provider
#'
#' A provider preset for Snowflake's built-in OAuth integration. Pass it to
#' `shinyOAuth::oauth_client()` with your registered credentials and scopes.
#' External OAuth uses the external identity provider's configuration instead.
#' @param server Snowflake account hostname.
#' @param ... Named `shinyOAuth::oauth_provider()` settings. Explicit values
#'   replace the preset defaults, including endpoints and client authentication.
#' @return An ordinary shinyOAuth provider, independent of the database bridge.
#' @export
oauth_db_snowflake_provider <- function(server, ...) {
  .odb_string(server, "server")
  if (!grepl("^[A-Za-z0-9.-]+$", server)) .odb_abort("server must be a Snowflake hostname.")
  base <- paste0("https://", server)
  defaults <- list(name = "snowflake",
    auth_url = paste0(base, "/oauth/authorize"), token_url = paste0(base, "/oauth/token-request"),
    userinfo_required = FALSE, id_token_required = FALSE, id_token_validation = FALSE,
    use_nonce = FALSE, use_pkce = TRUE, token_auth_style = "header")
  overrides <- list(...)
  if (length(overrides) && (is.null(names(overrides)) || anyNA(names(overrides)) ||
      any(!nzchar(names(overrides))) || anyDuplicated(names(overrides)))) {
    .odb_abort("Provider settings in ... must have unique names.")
  }
  defaults[names(overrides)] <- overrides
  do.call(shinyOAuth::oauth_provider, defaults)
}

.odb_oauth_client <- function(provider, client_id, redirect_uri, client_secret, scopes, ...) {
  .odb_string(client_id, "client_id")
  .odb_string(redirect_uri, "redirect_uri")
  if (is.null(client_secret) || identical(client_secret, "")) client_secret <- character()
  extras <- list(...)
  if (length(extras) && (is.null(names(extras)) || anyNA(names(extras)) ||
      any(!nzchar(names(extras))) || anyDuplicated(names(extras)))) {
    .odb_abort("Client settings in ... must have unique names.")
  }
  args <- list(provider = provider, client_id = client_id, client_secret = client_secret,
               redirect_uri = redirect_uri, scopes = scopes)
  do.call(shinyOAuth::oauth_client, c(args, extras))
}
