#' Inspect the OAuth requirements of data sources
#'
#' This performs static configuration checks, not remote app registration or
#' consent verification. Resources remain literal, including trailing slashes.
#' @param sources A source or a non-empty named list of sources.
#' @param default_source Name of the source used for initial token redemption.
#' @return A list containing provider groups, scopes, token targets and the
#'   default target when the sources fit one Microsoft registration.
#' @export
oauth_db_auth_plan <- function(sources, default_source = NULL) {
  if (inherits(sources, "oauth_db_source")) sources <- list(source = sources)
  if (!is.list(sources) || !length(sources) ||
      !all(vapply(sources, inherits, logical(1), "oauth_db_source"))) {
    .odb_abort("sources must be a source or a non-empty list of sources.")
  }
  if (is.null(names(sources))) names(sources) <- paste0("source", seq_along(sources))
  if (anyNA(names(sources)) || any(!nzchar(names(sources))) || anyDuplicated(names(sources))) {
    .odb_abort("sources must have distinct non-empty names.")
  }
  default_source <- if (is.null(default_source)) names(sources)[[1L]] else default_source
  if (!is.character(default_source) || length(default_source) != 1L ||
      !default_source %in% names(sources)) .odb_abort("default_source must name one of the sources.")
  families <- vapply(sources, function(x) x$auth$provider_family, character(1))
  groups <- split(names(sources), families)
  if (length(groups) != 1L || !identical(names(groups), "microsoft")) {
    return(list(provider_groups = groups, scopes = unique(unlist(lapply(sources, function(x) x$auth$scopes))),
                token_targets = NULL, default_token_target = NULL,
                sources = names(sources)))
  }
  targets <- list()
  for (source in sources) {
    auth <- source$auth
    .odb_string(auth$target, "Microsoft source target")
    .odb_string(auth$resource, "Microsoft source resource")
    previous <- targets[[auth$target]]
    if (!is.null(previous) && !identical(previous$resource, auth$resource)) {
      .odb_abort("Sources sharing a target name must declare the same literal OAuth resource.", "incompatible_authentication")
    }
    targets[[auth$target]] <- list(resource = auth$resource,
                                   scopes = union(previous$scopes, auth$scopes),
                                   required_scopes = union(previous$required_scopes, auth$required_scopes))
  }
  api_scopes <- unique(unlist(lapply(targets, `[[`, "scopes"), use.names = FALSE))
  is_static <- endsWith(api_scopes, "/.default")
  if (any(is_static) && !all(is_static)) {
    .odb_abort("Microsoft sources cannot mix .default consent with explicit API scopes in one client. Use separate clients or configure compatible explicit profiles.",
               "incompatible_authentication")
  }
  list(provider_groups = groups, scopes = unique(c("openid", "profile", "offline_access", api_scopes)),
       token_targets = targets, default_token_target = sources[[default_source]]$auth$target,
       sources = names(sources))
}

.odb_client_extras <- function(extras) {
  if (length(extras) && (is.null(names(extras)) || any(!nzchar(names(extras))) || anyDuplicated(names(extras)))) {
    .odb_abort("Additional OAuth client settings must have unique names.")
  }
  protected <- c("provider", "client_id", "client_secret", "redirect_uri", "scopes", "token_targets", "default_token_target", "resource")
  if (any(names(extras) %in% protected)) .odb_abort("Additional settings cannot override source-derived OAuth routing.")
  extras
}

.odb_client_secret <- function(value) {
  if (is.null(value) || identical(value, "") || identical(value, character())) return(NULL)
  .odb_string(value, "client_secret")
  value
}

#' Configure a shinyOAuth Microsoft client from data-source requirements
#' @inheritParams oauth_db_auth_plan
#' @param tenant_id Microsoft Entra tenant accepted by shinyOAuth.
#' @param client_id Registered OAuth application's client ID.
#' @param client_secret Confidential application's server-side secret, or NULL
#'   for a registered public client. This is not a service-identity data mode.
#' @param redirect_uri Registered callback URI.
#' @param ... Additional settings passed to `shinyOAuth::oauth_client()`.
#' @return A native shinyOAuth client. Use the existing shinyOAuth UI and server
#'   modules; the bridge does not add a second login or refresh controller.
#' @export
oauth_db_microsoft_client <- function(sources, tenant_id, client_id,
                                      client_secret = NULL, redirect_uri,
                                      default_source = NULL, ...) {
  .odb_string(tenant_id, "tenant_id")
  .odb_string(client_id, "client_id")
  .odb_string(redirect_uri, "redirect_uri")
  client_secret <- .odb_client_secret(client_secret)
  plan <- oauth_db_auth_plan(sources, default_source)
  if (length(plan$provider_groups) != 1L || !identical(names(plan$provider_groups), "microsoft")) {
    .odb_abort("Only explicitly Microsoft-authenticated sources can share this helper. Configure other providers with their native shinyOAuth clients.",
               "incompatible_authentication")
  }
  if (!"token_targets" %in% names(formals(shinyOAuth::oauth_client))) {
    .odb_abort("Install shinyOAuth with module-managed access_token() and token_targets support.", "missing_dependency")
  }
  args <- c(list(provider = shinyOAuth::oauth_provider_microsoft(
    tenant = tenant_id, id_token_validation = TRUE, userinfo_required = FALSE),
    client_id = client_id, client_secret = if (is.null(client_secret)) character() else client_secret,
    redirect_uri = redirect_uri, scopes = plan$scopes,
    token_targets = plan$token_targets, default_token_target = plan$default_token_target),
    .odb_client_extras(list(...)))
  do.call(shinyOAuth::oauth_client, args)
}

#' Configure a native Databricks OAuth client
#' @param source A Databricks source using native `databricks_oauth`.
#' @param client_id Registered Databricks OAuth client ID.
#' @param redirect_uri Registered callback URI.
#' @param client_secret Registered confidential-client secret, or NULL.
#' @param ... Additional shinyOAuth client settings.
#' @return A native shinyOAuth client. Workspace discovery is delegated to the
#'   existing exported `brickster::db_oauth_provider()` and can make a network request.
#' @export
oauth_db_databricks_client <- function(source, client_id, redirect_uri,
                                       client_secret = NULL, ...) {
  if (!inherits(source, "oauth_db_source") || !identical(source$backend, "databricks") ||
      !identical(source$auth$provider_family, "databricks")) {
    .odb_abort("Supply a Databricks source using native Databricks OAuth.")
  }
  .odb_string(client_id, "client_id")
  .odb_string(redirect_uri, "redirect_uri")
  client_secret <- .odb_client_secret(client_secret)
  .odb_require("brickster", "Databricks OAuth discovery")
  if (!"db_oauth_provider" %in% getNamespaceExports("brickster")) .odb_abort("Install brickster with db_oauth_provider() and external-token hooks.", "missing_dependency")
  provider <- brickster::db_oauth_provider(source$config$host,
                                           token_auth_style = if (is.null(client_secret)) "public" else "header")
  do.call(shinyOAuth::oauth_client, c(list(provider = provider, client_id = client_id,
    client_secret = if (is.null(client_secret)) character() else client_secret,
    redirect_uri = redirect_uri,
    scopes = unique(c("openid", "profile", "email", "offline_access", source$auth$scopes))),
    .odb_client_extras(list(...))))
}

#' Configure a native Snowflake OAuth client
#' @param source A Snowflake source using `snowflake_oauth`.
#' @param client_id Registered OAuth client ID.
#' @param client_secret Server-side OAuth client secret.
#' @param redirect_uri Registered callback URI.
#' @param ... Additional shinyOAuth client settings.
#' @return A native shinyOAuth client using Snowflake OAuth endpoints. External
#'   OAuth instead uses its configured external provider, for example the
#'   Microsoft helper when the source explicitly declares that provider family.
#' @export
oauth_db_snowflake_client <- function(source, client_id, client_secret, redirect_uri, ...) {
  if (!inherits(source, "oauth_db_source") || !identical(source$backend, "snowflake") ||
      !identical(source$auth$provider_family, "snowflake")) .odb_abort("Supply a Snowflake source using native Snowflake OAuth.")
  .odb_string(client_id, "client_id")
  .odb_string(client_secret, "client_secret")
  .odb_string(redirect_uri, "redirect_uri")
  base <- paste0("https://", source$config$server)
  provider <- shinyOAuth::oauth_provider(
    name = "snowflake", auth_url = paste0(base, "/oauth/authorize"),
    token_url = paste0(base, "/oauth/token-request"),
    userinfo_required = FALSE, id_token_required = FALSE,
    id_token_validation = FALSE, use_nonce = FALSE,
    use_pkce = TRUE, token_auth_style = "header"
  )
  do.call(shinyOAuth::oauth_client, c(list(provider = provider, client_id = client_id,
    client_secret = client_secret, redirect_uri = redirect_uri,
    scopes = unique(c(source$auth$scopes, "refresh_token"))), .odb_client_extras(list(...))))
}
