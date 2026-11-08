#' Access Oracle REST resources as the signed-in user
#'
#' Read Oracle data through Oracle REST Data Services (ORDS) using each
#' visitor's access token. ORDS exposes tables and custom database handlers
#' as web APIs. This client calls those APIs over HTTPS without Oracle
#' client libraries.
#'
#' @inheritParams oauth_db_postgrest_api
#' @param url HTTPS ORDS schema base URL, including any proxy prefix,
#'   for example `"https://data.example.org/ords/reporting"`.
#' @return A client object with these methods:
#'   \itemize{
#'     \item \code{$select(resource, query = list(), raw = FALSE)} reads one
#'       page of records from an AutoREST collection. Pass query parameters such as
#'       \code{list(limit = 20L, offset = 0L)}.
#'     \item \code{$request(path, method = "GET", query = list(), body = NULL,
#'       raw = FALSE, trailing_slash = FALSE)} calls a JSON resource. Supply
#'       relative path segments, for example \code{c("api", "sales")}.
#'       Set \code{trailing_slash = TRUE} when the resource URL ends in `/`.
#'   }
#' @details
#' Configure ORDS to trust your provider's JWT access tokens and map their
#' scopes or roles to resource privileges. Create the client inside `server()`
#' and call its methods from render or reactive expressions.
#'
#' ORDS controls access to its endpoints. The token's user ID is available
#' to handlers as `:current_user`, but it doesn't automatically change the
#' Oracle database schema. Configure handler filtering or a database
#' security context to apply the required per-user data access.
#'
#' Results are JSON lists, including `items`, `hasMore` and pagination links.
#' Large integers stay as strings. Fetch pages explicitly; the client
#' doesn't follow links or redirects. `raw = TRUE` and HEAD return an httr2
#' response; successful empty responses otherwise return invisible `NULL`.
#'
#' Requests use a current token and discard results after sign-out or
#' account changes. GET and HEAD can refresh and retry once after HTTP 401;
#' writes don't retry automatically.
#' @examples
#' \dontrun{
#' ords <- oauth_db_oracle_ords_api(
#'   auth$connection, "https://data.example.org/ords/reporting"
#' )
#' output$rows <- shiny::renderPrint({
#'   ords$select("orders", query = list(limit = 20L))$items
#' })
#' }
#' @seealso [oauth_db_oracle()], `vignette("oracle-ords", package = "shinyOAuthDB")`.
#' @export
oauth_db_oracle_ords_api <- function(
  authorization,
  url,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  timeout = 30,
  ca_bundle = NULL,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("jsonlite")
  url <- .odb_http_url(url)
  .odb_http_options(timeout, ca_bundle)
  provider <- .odb_http_provider(
    authorization,
    target,
    required_scopes,
    min_valid_for,
    session
  )
  .odb_oracle_ords_api$new(provider, url, timeout, ca_bundle)
}

.odb_oracle_ords_api <- R6::R6Class(
  "OAuthOracleORDSAPI",
  cloneable = FALSE,
  public = list(
    initialize = function(provider, url, timeout, ca_bundle) {
      private$provider <- provider
      private$url <- url
      private$timeout <- timeout
      private$ca_bundle <- ca_bundle
    },
    select = function(resource, query = list(), raw = FALSE) {
      page <- self$request(
        resource,
        query = query,
        raw = raw,
        trailing_slash = TRUE
      )
      if (
        !raw &&
          (!is.list(page) ||
            is.null(names(page)) ||
            !is.list(page$items) ||
            !is.null(names(page$items)) ||
            !is.logical(page$hasMore) ||
            length(page$hasMore) != 1L ||
            is.na(page$hasMore))
      ) {
        .odb_abort(
          "ORDS returned an invalid collection page.",
          "invalid_response"
        )
      }
      page
    },
    request = function(
      path,
      method = "GET",
      query = list(),
      body = NULL,
      raw = FALSE,
      trailing_slash = FALSE
    ) {
      path <- .odb_http_path(path)
      .odb_string(method, "method")
      method <- toupper(method)
      if (!method %in% c("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE")) {
        .odb_abort("Unsupported ORDS method.")
      }
      query <- .odb_http_query(query)
      .odb_options(
        query,
        blocked = c("authorization", "access_token", "token", "jwt", "password")
      )
      .odb_flag(raw, "raw")
      .odb_flag(trailing_slash, "trailing_slash")
      if (method %in% c("GET", "HEAD") && !is.null(body)) {
        .odb_abort("GET and HEAD requests cannot have a body.")
      }
      req <- httr2::request(paste0(
        private$url,
        "/",
        path,
        if (trailing_slash) "/" else ""
      ))
      req <- httr2::req_headers(req, Accept = "application/json")
      req <- httr2::req_method(req, method)
      if (length(query)) {
        req <- do.call(httr2::req_url_query, c(list(req), query))
      }
      if (!is.null(body)) {
        req <- httr2::req_body_json(req, body, auto_unbox = TRUE, digits = NA)
      }
      resp <- .odb_http_request(
        private$provider(),
        req,
        "Oracle ORDS",
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
      .odb_http_json(resp, "Oracle ORDS")
    },
    print = function(...) {
      cat("<OAuthOracleORDSAPI>\n")
      invisible(self)
    }
  ),
  private = list(provider = NULL, url = NULL, timeout = NULL, ca_bundle = NULL)
)
