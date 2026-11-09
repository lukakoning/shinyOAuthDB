#' Query Snowflake as the signed-in user
#'
#' Query Snowflake with each visitor's account and role. A role controls
#' which data they can access, while a warehouse runs the queries. The
#' connection works with DBI or dbplyr.
#'
#' @inheritParams oauth_db_azure_sql
#' @param database,schema,warehouse Optional connection settings. `NULL` uses
#'   the driver's or account's defaults.
#' @param role Snowflake role for this connection.
#' @param required_scopes Permissions to check before use. The default is the
#'   Snowflake role scope, `paste0("session:role:", role)`. For External OAuth,
#'   supply the scope names configured by the integration.
#' @param target Named shinyOAuth token target, or `NULL` for the default token.
#' @param ... Named Snowflake ODBC connection options. Authentication and the
#'   HTTPS protocol cannot be overridden.
#' @return A reactive function, usually named `con`. Call
#'   `connection <- con()` inside a render or reactive expression, then pass
#'   the connection to DBI. Before sign-in, the function waits quietly.
#' @details
#' Install odbc and the Snowflake ODBC driver. Use [oauth_db_snowflake_client()]
#' for Snowflake's own OAuth integration, or a shinyOAuth client for your
#' external provider. The user needs access to the requested role, warehouse
#' and data.
#'
#' Create the helper inside `server()` and call `con()` before each query.
#' The connection opens on first use and closes when the authorization or
#' session ends. For names containing ODBC delimiters, use [odbc::quote_value()].
#' @examples
#' \dontrun{
#' con <- oauth_db_snowflake(
#'   auth$connection,
#'   server = "organization-account.snowflakecomputing.com",
#'   role = "REPORTING_READER",
#'   warehouse = "REPORTING_WH",
#'   database = "ANALYTICS"
#' )
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT CURRENT_USER(), CURRENT_ROLE()")
#' })
#' }
#' @seealso [oauth_db_snowflake_client()].
#'   `vignette("snowflake", package = "shinyOAuthDB")` has sign-in setup
#'   and a complete app.
#' @export
oauth_db_snowflake <- function(
  authorization,
  server,
  database = NULL,
  schema = NULL,
  warehouse = NULL,
  role,
  ...,
  required_scopes = paste0("session:role:", role),
  target = NULL,
  driver = "SnowflakeDSIIDriver",
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("odbc", version = "1.4.2")
  .odb_string(server, "server")
  .odb_string(driver, "driver")
  .odb_string(database, "database", optional = TRUE)
  .odb_string(schema, "schema", optional = TRUE)
  .odb_string(warehouse, "warehouse", optional = TRUE)
  .odb_string(role, "role")
  .odb_odbc_values(list(server, database, schema, warehouse, role, driver))
  options <- .odb_options(
    list(...),
    blocked = c(
      "server",
      "database",
      "schema",
      "warehouse",
      "role",
      "driver",
      "drv",
      "dsn",
      "filedsn",
      "savefile",
      ".connection_string",
      "connection_string",
      "attributes",
      "user",
      "uid",
      "pwd",
      "password",
      "token",
      "access_token",
      "authentication",
      "authenticator",
      "token_file_path",
      "client_secret",
      "oauth_client_id",
      "oauth_client_secret",
      "oauth_scope",
      "insecure_mode",
      "protocol",
      "disable_saml_url_check",
      "encrypt",
      "trust_server_certificate"
    ),
    partial = "dsn"
  )
  .odb_odbc_values(options)
  .odb_bind(
    authorization,
    .odb_backend_snowflake,
    server = server,
    database = database,
    schema = schema,
    warehouse = warehouse,
    role = role,
    driver = driver,
    options = options,
    target = target,
    required_scopes = required_scopes,
    min_valid_for = min_valid_for,
    session = session
  )
}

.odb_backend_snowflake <- function(
  token,
  server,
  database,
  schema,
  warehouse,
  role,
  driver,
  options
) {
  context <- list(database = database, schema = schema, warehouse = warehouse)
  context <- context[!vapply(context, is.null, logical(1))]
  .odb_odbc_connect(
    c(
      list(
        drv = odbc::odbc(),
        driver = driver,
        server = server,
        role = role,
        authenticator = "oauth",
        token = token()
      ),
      context,
      options
    )
  )
}

#' Set up Snowflake OAuth sign-in
#'
#' Set up sign-in for a Shiny app using Snowflake's own OAuth integration.
#' Visitors use their Snowflake account and a role they can access. Pass
#' this client to shinyOAuth's UI and server modules, then connect with
#' [oauth_db_snowflake()].
#'
#' @inheritParams oauth_db_microsoft_client
#' @param server Snowflake account hostname. Ignored when `provider` is supplied.
#' @param client_secret Client secret from the Snowflake OAuth integration.
#' @param role Requested Snowflake role. Ignored when `scopes` is supplied.
#' @return A shinyOAuth `OAuthClient`. Create it outside `server()`.
#' @details
#' Register the app's exact redirect URI in a Snowflake custom OAuth
#' integration. The requested role must match the role used by
#' [oauth_db_snowflake()]. If your account uses an external provider such
#' as Entra or Okta, configure a shinyOAuth client for that provider instead.
#' @examples
#' \dontrun{
#' client <- oauth_db_snowflake_client(
#'   server = "organization-account.snowflakecomputing.com",
#'   role = "REPORTING_READER",
#'   client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
#'   client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
#'   redirect_uri = "http://localhost:8100"
#' )
#' }
#' @seealso [oauth_db_snowflake()], [oauth_db_snowflake_provider()].
#'   `vignette("snowflake", package = "shinyOAuthDB")` has sign-in setup
#'   and a complete app.
#' @export
oauth_db_snowflake_client <- function(
  server,
  client_id,
  client_secret,
  redirect_uri,
  role,
  ...,
  provider = oauth_db_snowflake_provider(server),
  scopes = c(paste0("session:role:", role), "refresh_token")
) {
  if (missing(scopes)) {
    .odb_string(role, "role")
  }
  .odb_oauth_client(
    provider,
    client_id,
    redirect_uri,
    client_secret,
    scopes = scopes,
    ...
  )
}

#' Create a Snowflake OAuth provider
#'
#' Describe Snowflake's sign-in service when building a custom client with
#' `shinyOAuth::oauth_client()`. For an app using Snowflake's own OAuth
#' integration, [oauth_db_snowflake_client()] supplies the usual settings.
#'
#' @param server Snowflake account hostname.
#' @param ... Settings for `shinyOAuth::oauth_provider()`, replacing defaults.
#' @return A shinyOAuth `OAuthProvider` for Snowflake's own OAuth integration.
#' @details
#' This provider uses Snowflake's own OAuth endpoints. An account using
#' External OAuth needs the external sign-in provider's configuration.
#' @seealso [oauth_db_snowflake_client()].
#'   `vignette("snowflake", package = "shinyOAuthDB")` has sign-in setup
#'   and a complete app.
#' @export
oauth_db_snowflake_provider <- function(server, ...) {
  .odb_string(server, "server")
  if (!grepl("^[A-Za-z0-9.-]+$", server)) {
    .odb_abort("server must be a Snowflake hostname.")
  }
  base <- paste0("https://", server)
  defaults <- list(
    name = "snowflake",
    auth_url = paste0(base, "/oauth/authorize"),
    token_url = paste0(base, "/oauth/token-request"),
    userinfo_required = FALSE,
    id_token_required = FALSE,
    id_token_validation = FALSE,
    use_nonce = FALSE,
    use_pkce = TRUE,
    token_auth_style = "header"
  )
  overrides <- list(...)
  .odb_named_args(overrides, "Provider settings in ...")
  defaults[names(overrides)] <- overrides
  do.call(shinyOAuth::oauth_provider, defaults)
}
