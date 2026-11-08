#' Query OpenSearch as the signed-in user
#'
#' Search OpenSearch documents and calculate summaries using each visitor's
#' permissions. An index holds the documents you query. The client supports
#' JSON searches and the SQL plugin, returning results as R lists.
#'
#' @inheritParams oauth_db_connect
#' @param url HTTPS OpenSearch cluster base URL, including a proxy path if needed.
#' @param timeout Maximum seconds for one HTTP operation, including a read retry.
#' @param ca_bundle Optional path to a trusted CA certificate bundle.
#' @return A client object with these methods:
#'   \itemize{
#'     \item \code{$search(index = NULL, body = list(), query = list(), raw = FALSE)}
#'       searches an index using an OpenSearch JSON query. The index can be a
#'       name, pattern or character vector; \code{NULL} searches across the cluster.
#'     \item \code{$sql(sql, parameters = list(), raw = FALSE)} runs a query
#'       through the SQL plugin and returns its native JSON result.
#'     \item \code{$request(path, method = "GET", query = list(), body = NULL,
#'       raw = FALSE)} calls a JSON API. Supply relative path segments,
#'       such as \code{c("orders", "_doc", "42")}.
#'   }
#' @details
#' Configure OpenSearch's Security plugin to accept your provider's tokens
#' and map the user and role claims to OpenSearch permissions. The endpoint
#' must accept bearer tokens; AWS SigV4 needs a different client.
#'
#' Create the client inside `server()` and call its methods from render or
#' reactive expressions. Each operation uses a current token and discards
#' results after sign-out or account changes. GET and HEAD can refresh and
#' retry once after HTTP 401; POST searches, SQL and writes don't retry.
#'
#' Search results keep `hits`, `aggregations` and totals as R lists. SQL
#' results keep their `schema` and `datarows`. Large integers stay as strings.
#' Use `raw = TRUE` for an httr2 response. Searches reporting a timeout or
#' failed shards raise an error unless you request the raw response.
#' @section SQL parameters and pagination:
#' SQL requires the server's SQL plugin. Use `?` placeholders with an
#' unnamed list of typed values, such as
#' `list(list(type = "integer", value = 30))` in `parameters`.
#'
#' Fetch search pages explicitly with `from`/`size` or `search_after`.
#' Use `$request()` for SQL cursors and other JSON APIs; consume or close
#' cursors before changing accounts.
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
#' @export
oauth_db_opensearch_api <- function(
  authorization,
  url,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  timeout = 30,
  ca_bundle = NULL,
  session = shiny::getDefaultReactiveDomain()
) {
  url <- .odb_http_url(url)
  .odb_http_options(timeout, ca_bundle)
  provider <- .odb_http_provider(
    authorization,
    target,
    required_scopes,
    min_valid_for,
    session
  )
  .odb_opensearch_api$new(provider, url, timeout, ca_bundle)
}

.odb_opensearch_api <- R6::R6Class(
  "OAuthOpenSearchAPI",
  cloneable = FALSE,
  public = list(
    initialize = function(provider, url, timeout, ca_bundle) {
      private$provider <- provider
      private$url <- url
      private$timeout <- timeout
      private$ca_bundle <- ca_bundle
    },
    search = function(
      index = NULL,
      body = list(),
      query = list(),
      raw = FALSE
    ) {
      if (!is.null(index)) {
        if (
          !is.character(index) ||
            !length(index) ||
            anyNA(index) ||
            !all(nzchar(index))
        ) {
          .odb_abort("index must be NULL or nonempty index names or patterns.")
        }
        # Validate each name before combining the multi-index expression.
        for (name in index) {
          .odb_http_path(name)
        }
        index <- paste(index, collapse = ",")
      }
      body <- .odb_opensearch_object(body, "body")
      result <- self$request(c(index, "_search"), "POST", query, body, raw)
      if (raw) {
        return(result)
      }
      if (is.list(result) && !is.null(result[["error"]])) {
        .odb_abort("The OpenSearch search failed.", "query_failed")
      }
      if (
        !is.list(result) ||
          is.null(names(result)) ||
          !is.list(result$hits) ||
          !is.list(result$hits$hits) ||
          !is.null(names(result$hits$hits))
      ) {
        .odb_abort(
          "OpenSearch returned an invalid search response.",
          "invalid_response"
        )
      }
      shards <- result[["_shards"]]
      if (
        (!is.null(shards) && !is.list(shards)) ||
          (!is.null(result$timed_out) &&
            (!is.logical(result$timed_out) ||
              length(result$timed_out) != 1L ||
              is.na(result$timed_out)))
      ) {
        .odb_abort(
          "OpenSearch returned invalid search completion metadata.",
          "invalid_response"
        )
      }
      failed <- shards[["failed"]]
      if (
        !is.null(failed) &&
          (!is.numeric(failed) ||
            length(failed) != 1L ||
            !is.finite(failed) ||
            failed < 0 ||
            failed != floor(failed))
      ) {
        .odb_abort(
          "OpenSearch returned invalid shard metadata.",
          "invalid_response"
        )
      }
      if (isTRUE(result$timed_out) || (!is.null(failed) && failed > 0)) {
        .odb_abort(
          "OpenSearch returned incomplete search results. Inspect the response with raw = TRUE.",
          "query_failed"
        )
      }
      result
    },
    sql = function(sql, parameters = list(), raw = FALSE) {
      .odb_string(sql, "sql")
      if (!is.list(parameters) || !is.null(names(parameters))) {
        .odb_abort(
          "parameters must be an unnamed list of native SQL parameter descriptors."
        )
      }
      for (parameter in parameters) {
        .odb_opensearch_object(parameter, "SQL parameter")
        if (!setequal(names(parameter), c("type", "value"))) {
          .odb_abort("Each SQL parameter must contain type and value.")
        }
        .odb_string(parameter$type, "SQL parameter type")
        value <- parameter$value
        if (
          !is.null(value) &&
            (!is.atomic(value) || length(value) != 1L || is.object(value))
        ) {
          .odb_abort("SQL parameter values must be JSON scalars or NULL.")
        }
      }
      body <- list(query = sql)
      if (length(parameters)) {
        body$parameters <- parameters
      }
      result <- self$request(
        c("_plugins", "_sql"),
        "POST",
        list(format = "jdbc"),
        body,
        raw
      )
      if (!raw && is.list(result) && !is.null(result[["error"]])) {
        .odb_abort("The OpenSearch SQL query failed.", "query_failed")
      }
      if (
        !raw &&
          (!is.list(result) ||
            is.null(names(result)) ||
            !is.list(result$schema) ||
            !is.list(result$datarows))
      ) {
        .odb_abort(
          "OpenSearch returned an invalid SQL response.",
          "invalid_response"
        )
      }
      result
    },
    request = function(
      path,
      method = "GET",
      query = list(),
      body = NULL,
      raw = FALSE
    ) {
      path <- .odb_http_path(path)
      .odb_string(method, "method")
      method <- toupper(method)
      if (!method %in% c("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE")) {
        .odb_abort("Unsupported OpenSearch method.")
      }
      query <- .odb_http_query(query)
      .odb_options(
        query,
        blocked = c("authorization", "access_token", "token", "jwt", "password")
      )
      query <- lapply(query, function(value) {
        if (is.logical(value)) tolower(as.character(value)) else value
      })
      .odb_flag(raw, "raw")
      if (method %in% c("GET", "HEAD") && !is.null(body)) {
        .odb_abort(
          "GET and HEAD requests cannot have a body; use POST for searches."
        )
      }
      if (!is.null(body)) {
        body <- .odb_opensearch_object(body, "body")
      }
      req <- httr2::request(paste0(private$url, "/", path))
      req <- httr2::req_headers(req, Accept = "application/json")
      if (length(query)) {
        req <- do.call(httr2::req_url_query, c(list(req), query))
      }
      if (!is.null(body)) {
        req <- httr2::req_body_json(req, body, auto_unbox = TRUE)
      }
      req <- httr2::req_method(req, method)
      resp <- .odb_http_request(
        private$provider(),
        req,
        "OpenSearch",
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
  if (!is.list(value)) {
    .odb_abort(paste0(
      name,
      " must be a named list representing a JSON object."
    ))
  }
  .odb_named_args(value, name)
  if (!length(value)) {
    value <- stats::setNames(list(), character())
  }
  value
}
