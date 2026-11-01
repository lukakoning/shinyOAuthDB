#' Set up Microsoft sign-in for database access
#'
#' Create sign-in settings for Azure or Fabric services. Pass the result to
#' shinyOAuth's UI and server modules so visitors can use their own accounts.
#' Choose the services your app needs with `services`.
#'
#' @param services One or more of `"sql"`, `"postgres"`, `"fabric"`, `"kql"`,
#'   `"dax"`, `"graphql"`, `"onelake"`, or `"databricks_entra"`.
#'   The first service selects the default token target.
#' @param tenant_id Microsoft Entra tenant ID. Not used when `provider` is supplied.
#' @param client_id Application ID from the OAuth registration.
#' @param redirect_uri Registered URL where the browser returns after sign-in.
#' @param client_secret Registered client secret, or `NULL` for a public client.
#' @param provider Optional shinyOAuth provider, replacing the default provider.
#' @param scopes Requested OAuth scopes, replacing the preset's defaults.
#' @param token_targets Named token targets, replacing the service defaults.
#'   Use `list()` for a client without named targets.
#' @param token_target_default Default target name, or `character()` for none.
#' @param ... Other settings for `shinyOAuth::oauth_client()`.
#' @return A shinyOAuth `OAuthClient`. Create it outside `server()`.
#' @details
#' Your app registration needs delegated permissions for the chosen services,
#' and users still need access to the database or Fabric items.
#'
#' You can keep an existing shinyOAuth client instead of using this helper.
#' Custom scopes, providers, and targets replace the corresponding defaults;
#' see `vignette("authorization", package = "shinyOAuthDB")`.
#' @examples
#' \dontrun{
#' client <- oauth_db_microsoft_client(
#'   services = c("fabric", "sql"),
#'   tenant_id = Sys.getenv("OAUTHDB_TENANT_ID"),
#'   client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
#'   client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
#'   redirect_uri = "http://localhost:8100"
#' )
#' }
#' @family sign-in configuration
#' @export
oauth_db_microsoft_client <- function(
  services = "sql", tenant_id, client_id, redirect_uri, client_secret = NULL, ...,
  provider = shinyOAuth::oauth_provider_microsoft(
    tenant = tenant_id, id_token_validation = TRUE, userinfo_required = FALSE),
  token_targets = .odb_microsoft_targets(services),
  token_target_default = if (length(token_targets)) names(token_targets)[[1L]] else character(),
  scopes = c("openid", "profile", "offline_access",
    unique(unlist(lapply(token_targets, `[[`, "scopes"), use.names = FALSE)))
) {
  .odb_oauth_client(provider, client_id, redirect_uri, client_secret,
    scopes = scopes, token_targets = token_targets,
    token_target_default = token_target_default, ...)
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
                                     required_scopes = .odb_microsoft_scopes(scopes, "scopes"))
  }
  targets
}

# Microsoft consent recipes are supplied by each backend; only composition and
# Microsoft's resource-qualified scope convention belong here.
.odb_microsoft_profile <- function(target, resource, permissions) {
  list(target = target, resource = resource, scopes = paste0(resource, "/", permissions))
}

.odb_microsoft_scopes <- function(scopes, name = "required_scopes") {
  scopes <- .odb_scopes(scopes, name)
  scopes[!endsWith(scopes, "/.default")]
}
