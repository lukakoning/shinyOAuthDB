#' Use the user's authorization with Azure SQL
#'
#' These helpers adapt the user's authorization to a native client. Call the
#' accessor inside an ordinary Shiny reactive or render function to obtain the
#' native connection or credential provider. Connections open on first use.
#' Supply driver options directly in `...`; query arguments stay in your native
#' database call. Authentication and certificate verification cannot be
#' overridden through `...`.
#'
#' @inheritParams oauth_db_connect
#' @details With an existing client without named targets, use `target = NULL`.
#'   Configure consent and required permissions on the shinyOAuth client or
#'   target. The helper adds no scope requirement by default; use
#'   `required_scopes` for an additional check. SQL enforces database permissions.
#'   See the simple-apps vignette for explicit-scope and `/.default` recipes.
#'
#'   For names containing ODBC delimiters, supply an [odbc::quote_value()]
#'   value, for example `database = odbc::quote_value("Sales;Archive")`.
#'   Quoted values pass through unchanged; control characters are rejected.
#' @param server Database hostname.
#' @param database Database name.
#' @param driver Installed ODBC driver name.
#' @param port Database port, an integer from 1 to 65535.
#' @param required_scopes Required delegated scopes. Microsoft `/.default` consent is
#'   configured on the shinyOAuth client, not checked as a literal permission.
#' @param ... Additional named options passed to the native connection function.
#' @returns A session-local reactive accessor for a native DBI connection.
#' @seealso [oauth_db_microsoft_client()], [oauth_db_sql_server()]
#' @examples
#' \dontrun{
#' # Inside server(), after creating auth with shinyOAuth:
#' con <- oauth_db_azure_sql(auth$connection,
#'   server = "example.database.windows.net", database = "Sales")
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT TOP (10) name FROM sys.tables")
#' })
#' }
#' @export
oauth_db_azure_sql <- function(
  authorization, server, database, ...,
  target = "sql", required_scopes = character(),
  driver = "ODBC Driver 18 for SQL Server", port = 1433L,
  min_valid_for = 60, session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("odbc", version = "1.4.2")
  if (length(port) != 1L || is.na(port) || !grepl("^[0-9]+$", port) ||
      as.numeric(port) < 1 || as.numeric(port) > 65535) {
    .odb_abort("port must be an integer from 1 to 65535.")
  }
  .odb_odbc_values(list(server, database, driver, port))
  options <- .odb_options(list(...), blocked = c(
    "server", "database", "driver", "port", "drv", "dsn", ".connection_string",
    "connection_string", "attributes", "token", "access_token", "user", "uid",
    "pwd", "password", "authentication", "authenticator", "trusted_connection",
    "integrated_security", "encrypt", "trust_server_certificate"))
  .odb_odbc_values(options)
  .odb_bind(authorization, .odb_backend_sql, server = server, database = database,
    driver = driver, port = port, options = options, target = target,
    required_scopes = .odb_microsoft_scopes(required_scopes), min_valid_for = min_valid_for, session = session)
}

#' Use the user's authorization with an Entra-enabled SQL Server
#'
#' An alias of [oauth_db_azure_sql()] for SQL Server deployments configured
#' to accept Entra access tokens. The server must already support this login.
#' @inheritParams oauth_db_azure_sql
#' @returns A session-local reactive accessor for a native DBI connection.
#' @export
oauth_db_sql_server <- oauth_db_azure_sql

.odb_backend_sql <- function(token, server, database, driver, port, options) {
  address <- paste0(server, ",", port)
  if (is.character(server) && length(server) == 1L && .odb_odbc_quoted(server)) {
    quote <- substr(server, 1L, 1L)
    address <- I(paste0(quote, substr(server, 2L, nchar(server) - 1L), ",", port, quote))
  }
  do.call(DBI::dbConnect, c(list(drv = odbc::odbc(), driver = driver,
    server = address, database = database, Encrypt = "yes",
    TrustServerCertificate = "no", attributes = list(azure_token = token())), options))
}

.odb_sql_server_profiles <- function() {
  list(sql = .odb_microsoft_profile("sql", "https://database.windows.net/", "user_impersonation"))
}
