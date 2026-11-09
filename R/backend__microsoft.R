#' Set up Microsoft sign-in for database access
#'
#' Set up Microsoft sign-in for a Shiny app that queries Azure SQL,
#' Azure PostgreSQL, Azure MySQL or other supported Microsoft services.
#' Choose the services your app uses, then pass this client to shinyOAuth's
#' UI and server modules.
#' The client holds your app's sign-in settings; each visitor signs in with
#' their own account.
#'
#' @param services One or more of `"sql"`, `"postgres"`, `"mysql"`, `"fabric"`,
#'   `"kql"`, `"dax"`, `"graphql"`, `"onelake"`, or `"databricks_entra"`.
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
#' Register the Shiny app in Microsoft Entra with the exact `redirect_uri`
#' and delegated permissions for the services it uses. Delegated access lets
#' the app act on behalf of the person who signs in. Users also need
#' permission to access the database or Fabric items.
#'
#' The preset creates named token targets for the selected services. Custom
#' `scopes`, `provider` and `token_targets` replace their defaults. An existing
#' shinyOAuth client can also supply suitable tokens.
#'
#' When PostgreSQL or MySQL is combined with other services, its preset
#' requests `user_impersonation` instead of `.default`. For a custom resource
#' such as Oracle Database, supply `token_targets`; the Oracle vignette has
#' an example.
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
#' @seealso `vignette("getting-started", package = "shinyOAuthDB")` explains
#'   sign-in settings and links to each source's setup guide.
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
    .odb_mysql_profiles(
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
