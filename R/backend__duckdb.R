#' Query a remote DuckDB server as the signed-in user
#'
#' Query a shared remote DuckDB database with each visitor's access token.
#' Quack connects your R client to the server, which checks the token and
#' controls data access. You can query its tables with DBI or dbplyr.
#'
#' @inheritParams oauth_db_connect
#' @param host One TCP hostname or address. Enclose IPv6 addresses in brackets.
#' @param port Quack server or TLS proxy port, default `9494`.
#' @param schema Default schema in the remote database, default `"main"`.
#' @param ca_bundle Optional CA certificate bundle path for a private server CA.
#' @param allow_local_http Allow unencrypted HTTP for `localhost`, `127.0.0.1`
#'   or `[::1]`. Defaults to `FALSE`; use only for local development.
#' @return A reactive function, usually named `con`. Call
#'   `connection <- con()` inside a render or reactive expression, then pass
#'   the connection to DBI. Before sign-in, the function waits quietly.
#' @details
#' Install duckdb 1.5.3 or later and matching `quack` and `httpfs` extensions
#' before starting the app. Configure the remote server's OAuth validator,
#' trusted issuer, audience and data permissions. A local DuckDB file
#' doesn't provide user sign-in.
#'
#' Create the helper inside `server()` and call `con()` before each query.
#' Connections require verified TLS unless you explicitly allow HTTP for
#' local development with `allow_local_http`.
#'
#' The helper selects the remote catalog `oauth_remote` and your chosen
#' schema for table queries. Standalone expressions can still run locally;
#' query a remote table to check server access.
#'
#' Token renewal replaces the connection and ends any transaction on it.
#' Keep transactions within one operation. Sign-out, account changes or
#' session end close the connection. The helper doesn't replay failed SQL.
#' @examples
#' \dontrun{
#' # Inside server(), using a client for the Quack server's issuer and audience:
#' con <- oauth_db_duckdb(
#'   auth$connection, host = "duckdb.example.org", port = 443,
#'   required_scopes = "quack:read"
#' )
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT * FROM orders LIMIT 20")
#' })
#' }
#' @seealso `vignette("duckdb", package = "shinyOAuthDB")` has server
#'   requirements, sign-in setup and a complete app.
#'   [oauth_db_demo()] runs a local Quack and Keycloak example.
#' @export
oauth_db_duckdb <- function(
  authorization,
  host,
  port = 9494L,
  schema = "main",
  ca_bundle = NULL,
  allow_local_http = FALSE,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("duckdb", version = "1.5.3")
  .odb_string(host, "host")
  if (
    !grepl(
      "^([A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?|\\[[0-9A-Fa-f:]+\\])$",
      host
    )
  ) {
    .odb_abort(
      "host must be one TCP hostname or address, without a scheme, port, path or credentials."
    )
  }
  if (
    !is.numeric(port) ||
      length(port) != 1L ||
      !is.finite(port) ||
      port < 1 ||
      port > 65535 ||
      port != floor(port)
  ) {
    .odb_abort("port must be an integer from 1 to 65535.")
  }
  .odb_string(schema, "schema")
  .odb_string(ca_bundle, "ca_bundle", optional = TRUE)
  .odb_flag(allow_local_http, "allow_local_http")
  if (
    allow_local_http && !tolower(host) %in% c("localhost", "127.0.0.1", "[::1]")
  ) {
    .odb_abort(
      "allow_local_http is restricted to localhost, 127.0.0.1 or [::1]."
    )
  }
  .odb_bind(
    authorization,
    .odb_backend_duckdb,
    uri = paste0("quack:", host, ":", as.integer(port)),
    schema = schema,
    ca_bundle = ca_bundle,
    allow_local_http = allow_local_http,
    target = target,
    required_scopes = required_scopes,
    min_valid_for = min_valid_for,
    cache_key = function(token) openssl::sha256(charToRaw(token())),
    disconnect = .odb_duckdb_disconnect,
    session = session
  )
}

.odb_backend_duckdb <- function(
  token,
  uri,
  schema,
  allow_local_http,
  ca_bundle = NULL
) {
  bearer <- token()
  connection <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  opened <- FALSE
  on.exit(if (!opened) .odb_duckdb_disconnect(connection), add = TRUE)
  DBI::dbExecute(connection, "LOAD quack")
  DBI::dbExecute(connection, "LOAD httpfs")
  DBI::dbExecute(connection, "SET enable_server_cert_verification = true")
  # Older httpfs releases have a separate switch for the curl transport.
  settings <- DBI::dbGetQuery(
    connection,
    "SELECT name FROM duckdb_settings() WHERE name = 'enable_curl_server_cert_verification'"
  )
  if (nrow(settings)) {
    DBI::dbExecute(
      connection,
      "SET enable_curl_server_cert_verification = true"
    )
  }
  DBI::dbExecute(connection, "SET http_retries = 0")
  if (!is.null(ca_bundle)) {
    DBI::dbExecute(
      connection,
      paste0("SET ca_cert_file = ", DBI::dbQuoteString(connection, ca_bundle))
    )
  }
  # DuckDB includes SQL text in errors. Do not expose the credential-bearing
  # ATTACH statement or its native condition through a parent error.
  tryCatch(
    {
      DBI::dbExecute(
        connection,
        paste0(
          "ATTACH ",
          DBI::dbQuoteString(connection, uri),
          " AS oauth_remote (TYPE quack, TOKEN ",
          DBI::dbQuoteString(connection, bearer),
          ", DISABLE_SSL ",
          if (allow_local_http) "true" else "false",
          ")"
        )
      )
      DBI::dbExecute(
        connection,
        paste0(
          "USE ",
          DBI::dbQuoteIdentifier(
            connection,
            DBI::Id(catalog = "oauth_remote", schema = schema)
          )
        )
      )
    },
    error = function(error) {
      .odb_abort(
        paste0(
          "Could not open the DuckDB Quack connection. Check the endpoint, ",
          "TLS certificate, server OAuth policy and schema."
        ),
        "connection_failed"
      )
    }
  )
  opened <- TRUE
  connection
}

.odb_duckdb_disconnect <- function(connection) {
  if (isTRUE(DBI::dbIsValid(connection))) {
    DBI::dbDisconnect(connection, shutdown = TRUE)
  }
  invisible(NULL)
}
