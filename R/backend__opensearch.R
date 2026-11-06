#' Query OpenSearch as the signed-in user
#'
#' Search documents, run aggregations or use the SQL plugin with the visitor's
#' current OAuth access token. Results retain OpenSearch's native JSON structure.
#'
#' @inheritParams oauth_db_connect
#' @param url HTTPS OpenSearch cluster base URL, including a proxy path if needed.
#' @param timeout Maximum seconds for one HTTP operation, including a read retry.
#' @param ca_bundle Optional path to a trusted CA certificate bundle.
#' @return An R6 client with these methods:
#'   \itemize{
#'     \item \code{$search(index = NULL, body = list(), query = list(), raw = FALSE)}
#'       posts a Query DSL object to \code{/<index>/_search}. An index may be a
#'       name, pattern or character vector. \code{NULL} uses cluster-wide search.
#'     \item \code{$sql(sql, parameters = list(), raw = FALSE)} posts SQL to
#'       \code{/_plugins/_sql}, returning its native JDBC-format JSON response.
#'       Parameters are an unnamed list of \code{list(type = "integer", value = 30)}
#'       descriptors for positional \code{?} placeholders.
#'     \item \code{$request(path, method = "GET", query = list(), body = NULL,
#'       raw = FALSE)} sends a native JSON request. Supply relative path segments,
#'       for example \code{c("orders", "_doc", "42")}.
#'   }
#' @details
#' Configure OpenSearch's Security plugin to accept your provider's JWT access
#' tokens using OpenID Connect or JWT authentication. It must validate the
#' issuer and audience and map the token's subject and backend roles to
#' OpenSearch permissions. A Dashboards browser login alone is insufficient.
#' This client uses bearer tokens, not AWS SigV4 or a shared service account.
#'
#' Create the client in `server()`. Each operation obtains a current token,
#' pins its authorization, and discards responses after account changes,
#' sign-out or lost permissions. GET and HEAD retry once after HTTP 401.
#' POST, PUT, PATCH and DELETE are never replayed automatically, including
#' searches and SQL queries. shinyOAuth renews tokens before requests.
#'
#' JSON objects become named lists, arrays become lists, and large integers
#' remain strings. Search hits, aggregations, totals and SQL schema metadata
#' are preserved rather than flattened into a data frame. `raw = TRUE`
#' returns an httr2 response. Searches that time out or report failed shards
#' raise an error unless `raw = TRUE`; use `$request()` for filtered responses.
#'
#' SQL requires the server's SQL plugin. There is no automatic pagination:
#' search pages use native `from`/`size` or `search_after` in the body.
#' Advanced SQL cursors and other JSON APIs are available through `$request()`;
#' consume or close cursors before changing accounts. Bulk NDJSON requests
#' are outside this client's JSON interface.
#' @examples
#' \dontrun{
#' search <- oauth_db_opensearch_api(auth$connection,
#'   url = "https://search.example.org")
#' output$results <- shiny::renderPrint({
#'   search$search("orders", body = list(
#'     size = 20L, query = list(term = list(country = "NL"))
#'   ))$hits
#' })
#' }
#' @seealso `vignette("opensearch", package = "shinyOAuthDB")`.
#'   [oauth_db_demo()] runs a local OpenSearch and Keycloak example.
#' @family platform API clients
#' @export
oauth_db_opensearch_api <- function(
  authorization, url, target = NULL, required_scopes = character(),
  min_valid_for = 60, timeout = 30, ca_bundle = NULL,
  session = shiny::getDefaultReactiveDomain()
) {
  url <- .odb_http_url(url)
  .odb_http_options(timeout, ca_bundle)
  provider <- .odb_http_provider(authorization, target, required_scopes, min_valid_for, session)
  .odb_opensearch_api$new(provider, url, timeout, ca_bundle)
}

.odb_opensearch_api <- R6::R6Class("OAuthOpenSearchAPI", cloneable = FALSE,
  public = list(
    initialize = function(provider, url, timeout, ca_bundle) {
      private$provider <- provider
      private$url <- url
      private$timeout <- timeout
      private$ca_bundle <- ca_bundle
    },
    search = function(index = NULL, body = list(), query = list(), raw = FALSE) {
      if (!is.null(index)) {
        if (!is.character(index) || !length(index) || anyNA(index) || any(!nzchar(index))) {
          .odb_abort("index must be NULL or nonempty index names or patterns.")
        }
        # Validate each name before combining the multi-index expression.
        for (name in index) .odb_http_path(name)
        index <- paste(index, collapse = ",")
      }
      body <- .odb_opensearch_object(body, "body")
      result <- self$request(c(index, "_search"), "POST", query, body, raw)
      if (raw) return(result)
      if (is.list(result) && !is.null(result[["error"]])) {
        .odb_abort("The OpenSearch search failed.", "query_failed")
      }
      if (!is.list(result) || is.null(names(result)) || !is.list(result$hits) ||
          !is.list(result$hits$hits) || !is.null(names(result$hits$hits))) {
        .odb_abort("OpenSearch returned an invalid search response.", "invalid_response")
      }
      shards <- result[["_shards"]]
      if ((!is.null(shards) && !is.list(shards)) ||
          (!is.null(result$timed_out) && (!is.logical(result$timed_out) ||
            length(result$timed_out) != 1L || is.na(result$timed_out)))) {
        .odb_abort("OpenSearch returned invalid search completion metadata.", "invalid_response")
      }
      failed <- shards[["failed"]]
      if (!is.null(failed) && (!is.numeric(failed) || length(failed) != 1L ||
          !is.finite(failed) || failed < 0 || failed != floor(failed))) {
        .odb_abort("OpenSearch returned invalid shard metadata.", "invalid_response")
      }
      if (isTRUE(result$timed_out) || (!is.null(failed) && failed > 0)) {
        .odb_abort("OpenSearch returned incomplete search results. Inspect the response with raw = TRUE.", "query_failed")
      }
      result
    },
    sql = function(sql, parameters = list(), raw = FALSE) {
      .odb_string(sql, "sql")
      if (!is.list(parameters) || !is.null(names(parameters))) {
        .odb_abort("parameters must be an unnamed list of native SQL parameter descriptors.")
      }
      for (parameter in parameters) {
        .odb_opensearch_object(parameter, "SQL parameter")
        if (!setequal(names(parameter), c("type", "value"))) {
          .odb_abort("Each SQL parameter must contain type and value.")
        }
        .odb_string(parameter$type, "SQL parameter type")
        value <- parameter$value
        if (!is.null(value) && (!is.atomic(value) || length(value) != 1L || is.object(value))) {
          .odb_abort("SQL parameter values must be JSON scalars or NULL.")
        }
      }
      body <- list(query = sql)
      if (length(parameters)) body$parameters <- parameters
      result <- self$request(c("_plugins", "_sql"), "POST", list(format = "jdbc"), body, raw)
      if (!raw && is.list(result) && !is.null(result[["error"]])) {
        .odb_abort("The OpenSearch SQL query failed.", "query_failed")
      }
      if (!raw && (!is.list(result) || is.null(names(result)) ||
          !is.list(result$schema) || !is.list(result$datarows))) {
        .odb_abort("OpenSearch returned an invalid SQL response.", "invalid_response")
      }
      result
    },
    request = function(path, method = "GET", query = list(), body = NULL, raw = FALSE) {
      path <- .odb_http_path(path)
      .odb_string(method, "method")
      method <- toupper(method)
      if (!method %in% c("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE")) {
        .odb_abort("Unsupported OpenSearch method.")
      }
      query <- .odb_http_query(query)
      .odb_options(query, blocked = c("authorization", "access_token", "token", "jwt", "password"))
      query <- lapply(query, function(value) if (is.logical(value)) tolower(as.character(value)) else value)
      .odb_flag(raw, "raw")
      if (method %in% c("GET", "HEAD") && !is.null(body)) {
        .odb_abort("GET and HEAD requests cannot have a body; use POST for searches.")
      }
      if (!is.null(body)) body <- .odb_opensearch_object(body, "body")
      req <- httr2::request(paste0(private$url, "/", path))
      req <- httr2::req_headers(req, Accept = "application/json")
      if (length(query)) req <- do.call(httr2::req_url_query, c(list(req), query))
      if (!is.null(body)) req <- httr2::req_body_json(req, body, auto_unbox = TRUE)
      req <- httr2::req_method(req, method)
      resp <- .odb_http_request(private$provider(), req, "OpenSearch", private$timeout,
        private$ca_bundle, retry_401 = method %in% c("GET", "HEAD"))
      if (raw || method == "HEAD") return(resp)
      if (!httr2::resp_has_body(resp)) return(invisible(NULL))
      result <- .odb_http_json(resp, "OpenSearch")
      result
    },
    print = function(...) {
      cat("<OAuthOpenSearchAPI>\n")
      invisible(self)
    }
  ),
  private = list(provider = NULL, url = NULL, timeout = NULL, ca_bundle = NULL)
)

.odb_opensearch_object <- function(value, name) {
  if (!is.list(value)) .odb_abort(paste0(name, " must be a named list representing a JSON object."))
  .odb_named_args(value, name)
  if (!length(value)) value <- stats::setNames(list(), character())
  value
}
