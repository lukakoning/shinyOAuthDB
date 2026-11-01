#' Query Trino as the signed-in user
#'
#' Query a Trino or Starburst Enterprise cluster using DBI or dbplyr through
#' RTrino. Users sign in with an identity provider accepted by the cluster.
#'
#' @inheritParams oauth_db_connect
#' @param host Cluster hostname or HTTPS origin.
#' @param catalog,schema Default Trino catalog and schema.
#' @param user Trino username, or a function returning it for the selected
#'   account. Use a reactive function when the username can change.
#' @param port HTTPS port. `NULL` uses the port in `host`, or `443`.
#' @param ca_bundle Optional CA certificate bundle path for RTrino.
#' @param ... RTrino connection options, such as `timeout`, `bigint`,
#'   `query_max_run_time`, or `extra.headers`.
#' @return A reactive function returning an RTrino DBI connection.
#' @details
#' Install RTrino 0.1.0 or later. Create `con` inside `server()` and get
#' `connection <- con()` inside a render or reactive expression before
#' querying.
#' @section Sign-in settings:
#' Configure a shinyOAuth client for the cluster's trusted issuer and
#' audience. The `user` value must match the cluster's principal mapping;
#' the server checks impersonation permissions.
#' @section Connection lifetime:
#' RTrino gets a current token for each HTTP request, including result pages.
#' Ordinary token refresh preserves the connection. Account or username
#' changes replace it; sign-out and session end close it.
#'
#' A saved authentication callback stays tied to its original authorization.
#' @examples
#' \dontrun{
#' con <- oauth_db_trino(
#'   auth$connection,
#'   host = "https://trino.example.org",
#'   catalog = "lakehouse",
#'   schema = "reporting",
#'   user = function() shiny::req(auth$token@userinfo$email)
#' )
#' output$rows <- shiny::renderTable({
#'   connection <- con()
#'   DBI::dbGetQuery(connection, "SELECT * FROM Orders LIMIT 20")
#' })
#' }
#' @seealso `vignette("trino", package = "shinyOAuthDB")` has sign-in setup
#'   and a complete app.
#' @family database connections
#' @export
oauth_db_trino <- function(
  authorization, host, catalog, schema, user, ...,
  port = NULL, ca_bundle = NULL, target = NULL, required_scopes = character(),
  min_valid_for = 60, session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("RTrino", version = "0.1.0")
  address <- .odb_trino_address(host, port)
  .odb_string(catalog, "catalog")
  .odb_string(schema, "schema")
  .odb_string(ca_bundle, "ca_bundle", optional = TRUE)
  if (!is.function(user)) .odb_string(user, "user")
  read_user <- if (is.function(user)) user else local({ value <- user; function() value })
  username <- function() {
    value <- read_user()
    .odb_string(value, "Trino user")
    value
  }
  options <- .odb_options(list(...), blocked = c(
    "drv", "host", "port", "catalog", "schema", "user", "auth", "authentication",
    "authorization", "token", "access_token", "token_provider", "password",
    "client_id", "client_secret", "ssl_options", "allow_http_auth", "verify", "insecure"
  ))
  if (!is.null(options$extra.headers)) {
    .odb_options(options$extra.headers, blocked = c(
      "Authorization", "Proxy-Authorization", "Cookie", "Host",
      "X-Trino-User", "X-Presto-User", "X-Trino-Original-User", "X-Presto-Original-User",
      "X-Trino-Session-User", "X-Trino-Principal"
    ))
  }
  .odb_bind(authorization, .odb_backend_trino, host = address$host, port = address$port,
    catalog = catalog, schema = schema, user = username, ca_bundle = ca_bundle,
    options = options, target = target, required_scopes = required_scopes,
    cache_key = function(token) { token(); NULL }, identity_key = username,
    min_valid_for = min_valid_for, session = session)
}

.odb_backend_trino <- function(token, host, port, catalog, schema, user, ca_bundle, options) {
  force(token)
  hostname <- tolower(httr2::url_parse(host)$hostname)
  auth <- function(req) {
    address <- tryCatch(httr2::url_parse(req$url), error = function(e) NULL)
    request_port <- if (is.null(address$port)) 443L else suppressWarnings(as.integer(address$port))
    if (is.null(address) || !identical(tolower(address$scheme), "https") ||
        !identical(tolower(address$hostname), hostname) ||
        !identical(request_port, as.integer(port)) ||
        !is.null(address$username) || !is.null(address$password)) {
      .odb_abort("Trino requests must remain within the configured HTTPS origin.", "invalid_audience")
    }
    req <- httr2::req_options(req, followlocation = FALSE)
    httr2::req_auth_bearer_token(req, token())
  }
  do.call(DBI::dbConnect, c(list(
    drv = RTrino::Trino(), host = host, port = port,
    catalog = catalog, schema = schema, user = shiny::isolate(user()), auth = auth,
    ssl_options = RTrino::trino_ssl(verify = TRUE, ca_bundle = ca_bundle),
    allow_http_auth = FALSE
  ), options))
}

.odb_trino_address <- function(host, port) {
  .odb_string(host, "host")
  if (!grepl("^[A-Za-z][A-Za-z0-9+.-]*://", host)) host <- paste0("https://", host)
  address <- tryCatch(httr2::url_parse(host), error = function(e) NULL)
  if (is.null(address) || !identical(tolower(address$scheme), "https") ||
      is.null(address$hostname) || !nzchar(address$hostname) ||
      !is.null(address$username) || !is.null(address$password) ||
      !is.null(address$query) || !is.null(address$fragment) ||
      !address$path %in% c("", "/") || grepl("[[:space:]]", host)) {
    .odb_abort("host must be an HTTPS cluster origin without credentials, a path, query, or fragment.")
  }
  embedded <- address$port
  if (is.null(port)) port <- if (is.null(embedded)) 443L else embedded
  if (length(port) != 1L || is.na(port) || !grepl("^[0-9]+$", port) ||
      as.numeric(port) < 1 || as.numeric(port) > 65535) {
    .odb_abort("port must be an integer from 1 to 65535.")
  }
  port <- as.integer(port)
  if (!is.null(embedded) && as.integer(embedded) != port) {
    .odb_abort("port conflicts with the port in host.")
  }
  address$scheme <- "https"
  address$port <- NULL
  address$path <- ""
  list(host = httr2::url_build(address), port = port)
}
