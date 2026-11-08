#' Query Supabase as the signed-in user
#'
#' Read tables and views, call database functions, or send native Data API
#' requests with the visitor's access token. Supabase applies the database's
#' grants and row-level security policies.
#'
#' @inheritParams oauth_db_postgrest_api
#' @param url HTTPS Supabase project base URL, without `/rest/v1` or
#'   `/auth/v1`. Custom domains and reverse proxy paths are supported.
#' @param api_key Project publishable key (`sb_publishable_...`) or legacy
#'   `anon` JWT. Secret and `service_role` keys are rejected.
#' @return An R6 client with the same `select()`, `rpc()`, and `request()`
#'   methods as [oauth_db_postgrest_api()]. `select()` returns a data frame;
#'   `rpc()` and `request()` return the parsed JSON value, or an httr2 response
#'   with `raw = TRUE`.
#' @details
#' Create the client inside `server()`. Each request sends the project key
#' in `apikey` and the visitor's current access token in `Authorization`.
#' The project key is never used as a substitute for a missing user token.
#' No database password or PostgreSQL driver is needed.
#'
#' Use [oauth_db_supabase_client()] with Supabase's OAuth server, or supply
#' an authorization from a third-party provider trusted by the project.
#' OAuth scopes do not grant table access; configure database grants and RLS.
#' This helper accesses the REST Data API, not SQL connections, Storage,
#' Realtime, or the Management API.
#'
#' The underlying PostgREST client obtains a current token for each operation,
#' discards responses after account changes or sign-out, and retries GET/HEAD
#' once after HTTP 401. Writes and POST function calls are never replayed.
#' Verified HTTPS is required, including for self-hosted deployments.
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
#' @family platform API clients
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
#' Create a sign-in client for a Supabase project with its OAuth 2.1 server
#' enabled. Pass it to shinyOAuth's UI and server modules, then query with
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
#' Enable Supabase's OAuth server, configure its sign-in and consent UI, and
#' register the app's exact redirect URI. Use asymmetric JWT signing keys
#' for OIDC. The default provider makes an HTTPS OIDC discovery request to
#' the project's `/auth/v1` issuer and enables PKCE and nonce validation.
#'
#' A nonempty secret selects HTTP Basic client authentication; without one,
#' the preset uses a public client. Supabase returns refresh tokens without
#' an `offline_access` scope. shinyOAuth handles renewal.
#'
#' For a third-party provider configured in Supabase, pass its provider here
#' or use an ordinary `shinyOAuth::oauth_client()`.
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
#' @family sign-in configuration
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
