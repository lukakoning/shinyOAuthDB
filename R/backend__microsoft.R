#' Set up Microsoft sign-in for database access
#'
#' Create a Microsoft Entra sign-in client for database and platform access.
#' Choose the services or token targets the app uses, then pass the client
#' to shinyOAuth's UI and server modules.
#'
#' @param services One or more of `"sql"`, `"postgres"`, `"fabric"`, `"kql"`,
#'   `"dax"`, `"graphql"`, `"onelake"`, or `"databricks_entra"`.
#'   The first service selects the default token target.
#' @param tenant_id Microsoft Entra tenant ID. Ignored when `provider` is supplied.
#' @param client_id Application ID from the OAuth registration.
#' @param redirect_uri Registered URL where the browser returns after sign-in.
#' @param client_secret Client secret, or `NULL` for a public client.
#' @param provider Custom shinyOAuth provider, replacing the default.
#' @param scopes OAuth scopes to request, replacing the defaults.
#' @param token_targets Named token targets, replacing the service defaults.
#'   Use `list()` for a client without named targets. In that case, default
#'   scopes come from `services`, which must select one resource. Supply
#'   `scopes` explicitly to replace those consent defaults.
#' @param token_target_default Default target name, or `character()` for none.
#' @param ... Other arguments for `shinyOAuth::oauth_client()`.
#' @return A shinyOAuth `OAuthClient`. Create it outside `server()`.
#' @details
#' The Entra registration needs delegated permissions for the selected services.
#' Users also need access to the database or Fabric items.
#' When PostgreSQL is combined with other services, its preset requests the
#' delegated `user_impersonation` scope instead of `.default`.
#'
#' Custom `scopes`, `provider`, and `token_targets` replace their defaults.
#' An existing shinyOAuth client can be used in place of this preset.
#' For a deployment-specific resource such as Oracle Database, supply custom
#' `token_targets`; see `vignette("oracle", package = "shinyOAuthDB")`.
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
#' @seealso `vignette("getting-started", package = "shinyOAuthDB")` links to
#'   each source's setup. For custom permissions and targets, see
#'   `vignette("authorization", package = "shinyOAuthDB")`.
#' @family sign-in configuration
#' @export
oauth_db_microsoft_client <- function(
  services = "sql",
  tenant_id,
  client_id,
  redirect_uri,
  client_secret = NULL,
  ...,
  provider = shinyOAuth::oauth_provider_microsoft(
    tenant = tenant_id,
    id_token_validation = TRUE,
    userinfo_required = FALSE
  ),
  token_targets = .odb_microsoft_targets(services),
  token_target_default = if (length(token_targets)) {
    names(token_targets)[[1L]]
  } else {
    character()
  },
  scopes = .odb_microsoft_client_scopes(services, token_targets)
) {
  .odb_oauth_client(
    provider,
    client_id,
    redirect_uri,
    client_secret,
    scopes = scopes,
    token_targets = token_targets,
    token_target_default = token_target_default,
    ...
  )
}

.odb_microsoft_client_scopes <- function(services, token_targets) {
  if (!length(token_targets)) {
    token_targets <- .odb_microsoft_targets(services)
    if (length(token_targets) != 1L) {
      .odb_abort(
        "Clients without named token targets must select one resource through services, or supply scopes explicitly."
      )
    }
  }
  c(
    "openid",
    "profile",
    "offline_access",
    unique(unlist(lapply(token_targets, `[[`, "scopes"), use.names = FALSE))
  )
}

.odb_microsoft_targets <- function(services) {
  profiles <- c(
    .odb_sql_server_profiles(),
    .odb_postgres_profiles(
      explicit_scopes = is.character(services) && length(unique(services)) > 1L
    ),
    .odb_fabric_profiles(),
    .odb_databricks_profiles()
  )
  if (
    !is.character(services) ||
      !length(services) ||
      anyNA(services) ||
      !all(services %in% names(profiles))
  ) {
    .odb_abort("Choose one or more supported Microsoft services.")
  }
  targets <- list()
  for (service in unique(services)) {
    profile <- profiles[[service]]
    previous <- targets[[profile$target]]
    scopes <- union(previous$scopes, profile$scopes)
    targets[[profile$target]] <- list(
      resource = profile$resource,
      scopes = scopes,
      required_scopes = .odb_microsoft_scopes(scopes, "scopes")
    )
  }
  targets
}

# Microsoft consent recipes are supplied by each backend; only composition and
# Microsoft's resource-qualified scope convention belong here.
.odb_microsoft_profile <- function(target, resource, permissions) {
  list(
    target = target,
    resource = resource,
    scopes = paste0(resource, "/", permissions)
  )
}

.odb_microsoft_scopes <- function(scopes, name = "required_scopes") {
  scopes <- .odb_scopes(scopes, name)
  scopes[!endsWith(scopes, "/.default")]
}
