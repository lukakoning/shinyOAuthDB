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
#' @param server Database hostname.
#' @param database Database name.
#' @param driver Installed ODBC driver name.
#' @param port Database port.
#' @param scopes Required delegated scopes. Microsoft `/.default` consent is
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
  target = "sql", scopes = "https://database.windows.net//user_impersonation",
  driver = "ODBC Driver 18 for SQL Server", port = 1433L,
  min_valid_for = 60, session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("odbc", version = "1.3.4")
  .odb_odbc_values(list(server, database, driver, port))
  options <- .odb_options(list(...), blocked = c(
    "server", "database", "driver", "port", "drv", "dsn", ".connection_string",
    "connection_string", "attributes", "token", "access_token", "user", "uid",
    "pwd", "password", "authentication", "authenticator", "trusted_connection",
    "integrated_security", "encrypt", "trust_server_certificate"))
  .odb_odbc_values(options)
  .odb_bind(authorization, .odb_backend_sql, server = server, database = database,
    driver = driver, port = port, options = options, target = target,
    scopes = .odb_microsoft_scopes(scopes), min_valid_for = min_valid_for, session = session)
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
  do.call(DBI::dbConnect, c(list(drv = odbc::odbc(), driver = driver,
    server = paste0(server, ",", port), database = database, Encrypt = "yes",
    TrustServerCertificate = "no", attributes = list(azure_token = token())), options))
}

.odb_sql_server_profiles <- function() {
  list(sql = .odb_microsoft_profile("sql", "https://database.windows.net/", "user_impersonation"))
}
