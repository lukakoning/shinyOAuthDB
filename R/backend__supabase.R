#' Query Supabase as the signed-in user
#'
#' Read Supabase tables or call database functions using each visitor's
#' account. The Data API exposes PostgreSQL data over HTTPS, so no database
#' driver is needed. Database grants and row-level security policies control
#' which records the user can read or change.
#'
#' @inheritParams oauth_db_postgrest_api
#' @param url HTTPS Supabase project base URL, without `/rest/v1` or
#'   `/auth/v1`. Custom domains and reverse proxy paths are supported.
#' @param api_key Project publishable key (`sb_publishable_...`) or legacy
#'   `anon` JWT. Secret and `service_role` keys are rejected.
#' @return A client object with the same `select()`, `rpc()`, and `request()`
#'   methods as [oauth_db_postgrest_api()]. `select()` returns a data frame;
#'   `rpc()` and `request()` return the parsed JSON value, or an httr2 response
#'   with `raw = TRUE`.
#' @details
#' Create the client inside `server()` and call its methods from render or
#' reactive expressions. Use [oauth_db_supabase_client()] for project sign-in,
#' or an authorization from a third-party provider the project trusts.
#'
#' The project key identifies the application; the visitor's token supplies
#' their identity. OAuth scopes don't grant table access, so configure
#' database grants and row-level security policies too. This client uses
#' the Data API; use a separate helper for a direct SQL connection.
#'
#' Requests use a current token and discard results after sign-out or
#' account changes. GET and HEAD can refresh and retry once after HTTP 401;
#' writes and POST function calls don't retry automatically. HTTPS is
#' required, including for self-hosted projects.
#' @examples
#' \dontrun{
#' supabase <- oauth_db_supabase_api(auth$connection,
#'   url = Sys.getenv("OAUTHDB_SUPABASE_URL"),
#'   api_key = Sys.getenv("OAUTHDB_SUPABASE_KEY"))
#' output$rows <- shiny::renderTable({
#'   supabase$select("orders", order = "id.asc", limit = 20L)
#' })
#' }
#' @seealso [oauth_db_supabase_client()], [oauth_db_postgrest_api()].
#'   `vignette("supabase", package = "shinyOAuthDB")` has setup instructions
#'   and a complete Shiny app.
#' @export
oauth_db_supabase_api <- function(
  authorization,
  url,
  api_key,
  schema = NULL,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  timeout = 30,
  ca_bundle = NULL,
  session = shiny::getDefaultReactiveDomain()
) {
  url <- .odb_supabase_url(url)
  api_key <- .odb_supabase_key(api_key)
  .odb_string(schema, "schema", optional = TRUE)
  if (!is.null(schema) && grepl("[[:cntrl:]]", schema)) {
    .odb_abort("schema cannot contain control characters.")
  }
  .odb_http_options(timeout, ca_bundle)
  provider <- .odb_http_provider(
    authorization,
    target,
    required_scopes,
    min_valid_for,
    session
  )
  .odb_supabase_api$new(
    provider,
    paste0(url, "/rest/v1"),
    schema,
    timeout,
    ca_bundle,
    api_key
  )
}

.odb_supabase_api <- R6::R6Class(
  "OAuthSupabaseAPI",
  inherit = .odb_postgrest_api,
  cloneable = FALSE,
  public = list(
    print = function(...) {
      cat("<OAuthSupabaseAPI>\n")
      invisible(self)
    }
  )
)

#' Set up Supabase OAuth sign-in
#'
#' Set up sign-in for people with accounts in a Supabase project. The
#' project must have its OAuth server enabled. Pass this client to
#' shinyOAuth's UI and server modules, then read data with
#' [oauth_db_supabase_api()].
#'
#' @inheritParams oauth_db_microsoft_client
#' @inheritParams oauth_db_supabase_api
#' @param url Supabase project base URL. Ignored when `provider` is supplied.
#' @param provider A custom shinyOAuth provider, replacing Supabase discovery.
#' @param scopes Identity scopes to request. The defaults request `openid`,
#'   `profile`, and `email`; these do not grant database permissions.
#' @return A shinyOAuth `OAuthClient`. Create it outside `server()`.
#' @details
#' Enable the project's OAuth server, configure its sign-in and consent
#' pages, and register the app's exact redirect URI. Use asymmetric signing
#' keys so shinyOAuth can validate the sign-in identity.
#'
#' Supply `client_secret` for a confidential registration; omit it for a
#' public registration without a secret. Supabase supplies refresh tokens
#' without an `offline_access` scope, and shinyOAuth handles renewal.
#'
#' For a third-party provider trusted directly by the project, supply that
#' `provider` or use `shinyOAuth::oauth_client()`.
#' @examples
#' \dontrun{
#' client <- oauth_db_supabase_client(
#'   url = Sys.getenv("OAUTHDB_SUPABASE_URL"),
#'   client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
#'   client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
#'   redirect_uri = "http://localhost:8100"
#' )
#' }
#' @seealso [oauth_db_supabase_api()].
#'   `vignette("supabase", package = "shinyOAuthDB")`.
#' @export
oauth_db_supabase_client <- function(
  url,
  client_id,
  redirect_uri,
  client_secret = NULL,
  ...,
  provider = .odb_supabase_provider(url, client_secret),
  scopes = c("openid", "profile", "email")
) {
  .odb_oauth_client(
    provider,
    client_id,
    redirect_uri,
    client_secret,
    scopes,
    ...
  )
}

.odb_supabase_provider <- function(url, client_secret) {
  shinyOAuth::oauth_provider_oidc_discover(
    issuer = paste0(.odb_supabase_url(url), "/auth/v1"),
    name = "supabase",
    token_auth_style = if (
      is.null(client_secret) ||
        !length(client_secret) ||
        identical(client_secret, "")
    ) {
      "public"
    } else {
      "header"
    },
    use_pkce = TRUE,
    use_nonce = TRUE,
    id_token_validation = TRUE,
    userinfo_required = FALSE
  )
}

.odb_supabase_url <- function(url) {
  url <- .odb_http_url(url)
  if (grepl("/(rest|auth)/v1$", url)) {
    .odb_abort(
      "url must be the Supabase project base URL, without /rest/v1 or /auth/v1."
    )
  }
  url
}

.odb_supabase_key <- function(api_key) {
  .odb_string(api_key, "api_key")
  if (grepl("^sb_publishable_[!-~]+$", api_key)) {
    return(api_key)
  }
  claims <- NULL
  if (grepl("^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$", api_key)) {
    .odb_require("jsonlite")
    claims <- tryCatch(
      {
        payload <- strsplit(api_key, ".", fixed = TRUE)[[1L]][[2L]]
        payload <- chartr("-_", "+/", payload)
        payload <- paste0(
          payload,
          strrep("=", (4L - nchar(payload) %% 4L) %% 4L)
        )
        jsonlite::parse_json(rawToChar(openssl::base64_decode(payload)))
      },
      error = function(e) NULL
    )
  }
  if (is.list(claims) && identical(claims[["role"]], "anon")) {
    return(api_key)
  }
  .odb_abort(
    "api_key must be a Supabase publishable key or legacy anon JWT; secret and service_role keys cannot be used for visitor access."
  )
}
