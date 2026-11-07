#' Query PostgREST as the signed-in user
#'
#' Read PostgreSQL tables and views or call exposed functions through
#' PostgREST, using the visitor's current bearer token for each request.
#'
#' @inheritParams oauth_db_connect
#' @param url HTTPS PostgREST base URL, including a reverse proxy path if needed.
#' @param schema Exposed PostgreSQL schema, or `NULL` for the server default.
#' @param timeout Maximum seconds for one request, including its refresh retry.
#' @param ca_bundle Optional path to a trusted CA certificate bundle.
#' @return An R6 client with these methods:
#'   \itemize{
#'     \item \code{$select(table, select = "*", filters = list(), order = NULL,
#'       limit = NULL, offset = NULL, count = NULL, raw = FALSE)} reads one
#'       result page as a data frame. Filters use PostgREST expressions,
#'       for example \code{list(country = "eq.NL")}.
#'     \item \code{$rpc(name, args = list(), raw = FALSE)} calls an exposed
#'       database function with POST and returns its parsed JSON value.
#'     \item \code{$request(path, method = "GET", query = list(), body = NULL,
#'       prefer = NULL, raw = FALSE)} sends a native PostgREST request.
#'       Supply path segments such as \code{c("rpc", "my_function")}.
#'   }
#' @details
#' Configure a shinyOAuth client for the identity provider trusted by your
#' PostgREST deployment. Its access token must be a JWT with the expected
#' audience and role claims. PostgREST verifies the token; PostgreSQL grants
#' and row-level security control which data the visitor can access.
#'
#' Create the client inside `server()` and call its methods in render or
#' reactive expressions. No PostgreSQL driver or native OAuth hook is needed.
#' `schema` uses Accept-Profile for reads and Content-Profile for writes.
#'
#' Each call pins its starting authorization, obtains a current access token,
#' and discards responses after sign-out, account changes, or permission loss.
#' GET and HEAD retry once after a 401 with a renewed token. POST, PATCH, PUT,
#' and DELETE are never replayed automatically, including function calls.
#' @section Results and pagination:
#' `select()` returns one page; the server can cap its size. Use `limit`,
#' `offset`, and a deterministic `order` to page explicitly. Set `count` to
#' `"exact"`, `"planned"`, or `"estimated"` to request a total.
#'
#' `raw = TRUE` returns an httr2 response, including Content-Range; inspect
#' it with `httr2::resp_header()`. Otherwise JSON is decoded with large
#' integers preserved as strings. Embedded resources may become nested data
#' frames or list columns. An empty selection returns a zero-column data frame.
#' Dates and decimal strings keep the server's JSON representation.
#' @examples
#' \dontrun{
#' postgrest <- oauth_db_postgrest_api(auth$connection,
#'   url = "https://data.example.org", schema = "reporting")
#' output$rows <- shiny::renderTable({
#'   postgrest$select("orders", filters = list(country = "eq.NL"),
#'     order = "id.asc", limit = 20L)
#' })
#' }
#' @seealso `vignette("postgrest", package = "shinyOAuthDB")`.
#' @family platform API clients
#' @export
oauth_db_postgrest_api <- function(
  authorization,
  url,
  schema = NULL,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  timeout = 30,
  ca_bundle = NULL,
  session = shiny::getDefaultReactiveDomain()
) {
  url <- .odb_http_url(url)
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
  .odb_postgrest_api$new(provider, url, schema, timeout, ca_bundle)
}

.odb_postgrest_api <- R6::R6Class(
  "OAuthPostgRESTAPI",
  cloneable = FALSE,
  public = list(
    initialize = function(provider, url, schema, timeout, ca_bundle) {
      private$provider <- provider
      private$url <- url
      private$schema <- schema
      private$timeout <- timeout
      private$ca_bundle <- ca_bundle
    },
    select = function(
      table,
      select = "*",
      filters = list(),
      order = NULL,
      limit = NULL,
      offset = NULL,
      count = NULL,
      raw = FALSE
    ) {
      .odb_string(table, "table")
      .odb_string(select, "select")
      .odb_string(order, "order", optional = TRUE)
      filters <- .odb_http_query(filters)
      if (any(names(filters) %in% c("select", "order", "limit", "offset"))) {
        .odb_abort(
          "Use the select, order, limit, and offset arguments for those query options."
        )
      }
      query <- c(list(select = select), filters)
      if (!is.null(order)) {
        query$order <- order
      }
      for (name in c("limit", "offset")) {
        value <- get(name)
        if (is.null(value)) {
          next
        }
        if (
          !is.numeric(value) ||
            length(value) != 1L ||
            !is.finite(value) ||
            value < 0 ||
            value != floor(value)
        ) {
          .odb_abort(paste0(name, " must be a non-negative integer."))
        }
        query[[name]] <- value
      }
      prefer <- if (is.null(count)) {
        NULL
      } else {
        .odb_string(count, "count")
        if (!count %in% c("exact", "planned", "estimated")) {
          .odb_abort("Invalid PostgREST count method.")
        }
        paste0("count=", count)
      }
      value <- self$request(table, query = query, prefer = prefer, raw = raw)
      if (raw) {
        return(value)
      }
      if (identical(value, list())) {
        return(data.frame())
      }
      if (!is.data.frame(value)) {
        .odb_abort(
          "PostgREST returned a non-tabular selection.",
          "invalid_response"
        )
      }
      value
    },
    rpc = function(name, args = list(), raw = FALSE) {
      .odb_string(name, "name")
      if (!is.list(args)) {
        .odb_abort("args must be a named list of function arguments.")
      }
      .odb_named_args(args, "args")
      # An argument-free function still expects an object, rather than [].
      if (!length(args)) {
        args <- stats::setNames(list(), character())
      }
      self$request(c("rpc", name), method = "POST", body = args, raw = raw)
    },
    request = function(
      path,
      method = "GET",
      query = list(),
      body = NULL,
      prefer = NULL,
      raw = FALSE
    ) {
      path <- .odb_http_path(path)
      .odb_string(method, "method")
      method <- toupper(method)
      if (!method %in% c("GET", "HEAD", "POST", "PATCH", "PUT", "DELETE")) {
        .odb_abort("Unsupported PostgREST method.")
      }
      query <- .odb_http_query(query)
      .odb_string(prefer, "prefer", optional = TRUE)
      if (!is.null(prefer) && grepl("[[:cntrl:]]", prefer)) {
        .odb_abort("prefer cannot contain control characters.")
      }
      .odb_flag(raw, "raw")
      if (method %in% c("GET", "HEAD") && !is.null(body)) {
        .odb_abort("GET and HEAD requests cannot have a body.")
      }
      req <- httr2::request(paste0(private$url, "/", path))
      req <- httr2::req_method(req, method)
      req <- httr2::req_headers(req, Accept = "application/json")
      if (length(query)) {
        req <- do.call(httr2::req_url_query, c(list(req), query))
      }
      if (!is.null(body)) {
        req <- httr2::req_body_json(req, body, auto_unbox = TRUE)
      }
      if (!is.null(prefer)) {
        req <- httr2::req_headers(req, Prefer = prefer)
      }
      if (!is.null(private$schema)) {
        header <- if (method %in% c("GET", "HEAD")) {
          "Accept-Profile"
        } else {
          "Content-Profile"
        }
        req <- do.call(
          httr2::req_headers,
          c(list(req), stats::setNames(list(private$schema), header))
        )
      }
      resp <- .odb_http_request(
        private$provider(),
        req,
        "PostgREST",
        private$timeout,
        private$ca_bundle,
        retry_401 = method %in% c("GET", "HEAD")
      )
      if (raw || method == "HEAD") {
        return(resp)
      }
      if (!httr2::resp_has_body(resp)) {
        return(invisible(NULL))
      }
      .odb_http_json(resp, "PostgREST", simplify = TRUE)
    },
    print = function(...) {
      cat("<OAuthPostgRESTAPI>\n")
      invisible(self)
    }
  ),
  private = list(
    provider = NULL,
    url = NULL,
    schema = NULL,
    timeout = NULL,
    ca_bundle = NULL
  )
)
