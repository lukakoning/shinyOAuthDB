#' Query Elasticsearch as the signed-in user
#'
#' Search documents, run SQL or use ES|QL with each visitor's access token.
#' Results keep Elasticsearch's native JSON structure as R lists.
#'
#' @inheritParams oauth_db_opensearch_api
#' @param url HTTPS Elasticsearch deployment URL, including a proxy path if needed.
#' @param client_secret JWT realm's application shared secret. This is separate
#'   from the OAuth registration's client secret. Use `NULL` only when the realm
#'   explicitly disables client authentication.
#' @return A client object with these methods:
#'   \itemize{
#'     \item \code{$search(index = NULL, body = list(), query = list(), raw = FALSE)}
#'       runs a JSON search. The index may be a name, pattern or character vector;
#'       \code{NULL} searches across the deployment.
#'     \item \code{$sql(sql, parameters = list(), raw = FALSE)} returns one SQL
#'       result page, including \code{columns}, \code{rows} and any \code{cursor}.
#'     \item \code{$esql(query, parameters = list(), raw = FALSE)} returns ES|QL
#'       \code{columns}, \code{values} and completion metadata.
#'     \item \code{$request(path, method = "GET", query = list(), body = NULL,
#'       raw = FALSE)} calls a JSON API using relative path segments.
#'   }
#' @details
#' Configure an Elasticsearch JWT realm to accept the provider's JWT access
#' tokens and map their principal and groups to Elasticsearch roles. The
#' `access_token` realm type requires allowed subjects or subject patterns.
#' JWT realms require Elasticsearch 8.7 or later for this token type and an
#' appropriate subscription. This route supports self-managed and Elastic
#' Cloud Hosted deployments; Elastic Cloud Serverless has no JWT realms.
#' Kibana OIDC sign-in alone does not configure API access.
#'
#' Create the client inside `server()`. Each request obtains a current access
#' token and discards results after sign-out, account changes or lost required
#' permissions. GET and HEAD can refresh and retry once after HTTP 401. POST
#' queries and writes are never replayed automatically. Requests use verified
#' HTTPS and do not follow redirects.
#'
#' The realm shared secret identifies the application; the visitor's token
#' determines their data permissions. It is sent in the redacted
#' `ES-Client-Authentication` header. No ID token, API key or impersonation
#' header is substituted for the visitor's access token.
#' @section Parameters and results:
#' SQL and ES|QL accept `?` placeholders with an unnamed list of scalar
#' strings, logicals, finite numbers or `NULL` in `parameters`. Values are
#' sent separately from the query. ES|QL and its parameter syntax require
#' a server version that supports them. Use `$request()` for other native
#' parameter forms or query options.
#'
#' Large JSON integers remain strings; nested documents and multivalued
#' fields remain lists. Search timeouts, shard failures, skipped remote
#' clusters and partial query results raise errors. Use `raw = TRUE` for the
#' httr2 response instead.
#'
#' There is no automatic pagination. Use `search_after` for searches, or
#' `$request("_sql", method = "POST", body = list(cursor = cursor))` for SQL
#' pages. Close unused SQL cursors with `$request(c("_sql", "close"),
#' method = "POST", body = list(cursor = cursor))`. Keep cursors and point-in-time
#' identifiers with the authorization that created them and discard them on
#' sign-out or account changes. NDJSON APIs need a different client.
#' @examples
#' \dontrun{
#' search <- oauth_db_elasticsearch_api(auth$connection,
#'   url = "https://search.example.org",
#'   client_secret = Sys.getenv("OAUTHDB_ELASTICSEARCH_REALM_SECRET"))
#' output$rows <- shiny::renderPrint({
#'   search$sql("SELECT country, total FROM orders WHERE country = ?",
#'     parameters = list("NL"))$rows
#' })
#' }
#' @seealso `vignette("elasticsearch", package = "shinyOAuthDB")`.
#' @export
oauth_db_elasticsearch_api <- function(
  authorization,
  url,
  client_secret = NULL,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  timeout = 30,
  ca_bundle = NULL,
  session = shiny::getDefaultReactiveDomain()
) {
  url <- .odb_http_url(url)
  .odb_string(client_secret, "client_secret", optional = TRUE)
  if (!is.null(client_secret) && grepl("[[:cntrl:]]", client_secret)) {
    .odb_abort("client_secret must not contain control characters.")
  }
  .odb_http_options(timeout, ca_bundle)
  provider <- .odb_http_provider(
    authorization,
    target,
    required_scopes,
    min_valid_for,
    session
  )
  .odb_elasticsearch_api$new(provider, url, client_secret, timeout, ca_bundle)
}

.odb_elasticsearch_api <- R6::R6Class(
  "OAuthElasticsearchAPI",
  cloneable = FALSE,
  public = list(
    initialize = function(provider, url, client_secret, timeout, ca_bundle) {
      private$provider <- provider
      private$url <- url
      private$client_secret <- client_secret
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
        for (name in index) {
          .odb_http_path(name)
        }
        index <- paste(index, collapse = ",")
      }
      body <- .odb_elasticsearch_object(body, "body")
      result <- self$request(c(index, "_search"), "POST", query, body, raw)
      if (raw) {
        return(result)
      }
      .odb_elasticsearch_complete(result)
      if (
        !is.list(result$hits) ||
          !.odb_elasticsearch_array(result$hits$hits)
      ) {
        .odb_abort(
          "Elasticsearch returned invalid search hits.",
          "invalid_response"
        )
      }
      result
    },
    sql = function(sql, parameters = list(), raw = FALSE) {
      .odb_string(sql, "sql")
      body <- list(query = sql)
      .odb_elasticsearch_parameters(parameters)
      if (length(parameters)) {
        body$params <- parameters
      }
      result <- self$request("_sql", "POST", list(format = "json"), body, raw)
      if (!raw) {
        .odb_elasticsearch_table(result, "rows")
      }
      result
    },
    esql = function(query, parameters = list(), raw = FALSE) {
      .odb_string(query, "query")
      body <- list(query = query)
      .odb_elasticsearch_parameters(parameters)
      if (length(parameters)) {
        body$params <- parameters
      }
      result <- self$request("_query", "POST", list(format = "json"), body, raw)
      if (!raw) {
        .odb_elasticsearch_table(result, "values")
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
        .odb_abort("Unsupported Elasticsearch method.")
      }
      query <- .odb_http_query(query)
      .odb_options(
        query,
        blocked = c(
          "authorization",
          "access_token",
          "token",
          "jwt",
          "password",
          "client_secret",
          "es_client_authentication",
          "api_key",
          "apikey"
        )
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
        body <- .odb_elasticsearch_object(body, "body")
      }
      req <- httr2::request(paste0(private$url, "/", path))
      req <- httr2::req_headers(req, Accept = "application/json")
      if (!is.null(private$client_secret)) {
        req <- httr2::req_headers(
          req,
          `ES-Client-Authentication` = paste(
            "SharedSecret",
            private$client_secret
          ),
          .redact = "ES-Client-Authentication"
        )
      }
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
        "Elasticsearch",
        private$timeout,
        private$ca_bundle,
        retry_401 = method %in% c("GET", "HEAD"),
        sensitive = private$client_secret
      )
      if (raw || method == "HEAD") {
        return(resp)
      }
      if (!httr2::resp_has_body(resp)) {
        return(invisible(NULL))
      }
      .odb_http_json(resp, "Elasticsearch")
    },
    print = function(...) {
      cat("<OAuthElasticsearchAPI>\n")
      invisible(self)
    }
  ),
  private = list(
    provider = NULL,
    url = NULL,
    client_secret = NULL,
    timeout = NULL,
    ca_bundle = NULL
  )
)

.odb_elasticsearch_object <- function(value, name) {
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

.odb_elasticsearch_array <- function(value) {
  is.list(value) && is.null(names(value))
}

.odb_elasticsearch_parameters <- function(parameters) {
  scalar <- function(value) {
    is.null(value) ||
      (typeof(value) %in%
        c("character", "logical", "integer", "double") &&
        !is.object(value) &&
        is.null(dim(value)) &&
        length(value) == 1L &&
        !is.na(value) &&
        (!is.numeric(value) || is.finite(value)))
  }
  if (
    !.odb_elasticsearch_array(parameters) ||
      !all(vapply(parameters, scalar, logical(1)))
  ) {
    .odb_abort("parameters must be an unnamed list of JSON scalars or NULL.")
  }
  invisible(NULL)
}

.odb_elasticsearch_complete <- function(result) {
  if (!is.list(result) || is.null(names(result))) {
    .odb_abort(
      "Elasticsearch returned an invalid query response.",
      "invalid_response"
    )
  }
  if (!is.null(result[["error"]])) {
    .odb_abort("The Elasticsearch query failed.", "query_failed")
  }
  incomplete <- FALSE
  for (name in c("timed_out", "is_partial", "is_running")) {
    value <- result[[name]]
    if (!is.null(value)) {
      if (!is.logical(value) || length(value) != 1L || is.na(value)) {
        .odb_abort(
          "Elasticsearch returned invalid completion metadata.",
          "invalid_response"
        )
      }
      incomplete <- incomplete || value
    }
  }
  for (name in c("_shards", "_clusters")) {
    metadata <- result[[name]]
    if (!is.null(metadata)) {
      if (!is.list(metadata) || is.null(names(metadata))) {
        .odb_abort(
          "Elasticsearch returned invalid completion metadata.",
          "invalid_response"
        )
      }
      for (field in c(
        "failed",
        if (name == "_clusters") c("partial", "skipped")
      )) {
        value <- metadata[[field]]
        if (!is.null(value)) {
          if (
            !is.numeric(value) ||
              length(value) != 1L ||
              !is.finite(value) ||
              value < 0 ||
              value != floor(value)
          ) {
            .odb_abort(
              "Elasticsearch returned invalid completion counts.",
              "invalid_response"
            )
          }
          incomplete <- incomplete || value > 0
        }
      }
    }
  }
  if (incomplete) {
    .odb_abort(
      "Elasticsearch returned incomplete query results. Inspect the response with raw = TRUE.",
      "query_failed"
    )
  }
  invisible(NULL)
}

.odb_elasticsearch_table <- function(result, field) {
  .odb_elasticsearch_complete(result)
  if (
    !.odb_elasticsearch_array(result$columns) ||
      !.odb_elasticsearch_array(result[[field]]) ||
      !all(vapply(
        result$columns,
        function(column) {
          is.list(column) &&
            is.character(column$name) &&
            length(column$name) == 1L &&
            !is.na(column$name) &&
            is.character(column$type) &&
            length(column$type) == 1L &&
            !is.na(column$type)
        },
        logical(1)
      )) ||
      !all(vapply(
        result[[field]],
        function(row) {
          .odb_elasticsearch_array(row) && length(row) == length(result$columns)
        },
        logical(1)
      ))
  ) {
    .odb_abort(
      "Elasticsearch returned an invalid tabular response.",
      "invalid_response"
    )
  }
  invisible(NULL)
}
