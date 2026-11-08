#' Access Oracle REST resources as the signed-in user
#'
#' Read protected Oracle REST Data Services (ORDS) resources and call JSON
#' handlers using the visitor's OAuth access token. Configure ORDS to trust
#' the provider's JWTs and map their scopes or roles to ORDS privileges.
#'
#' @inheritParams oauth_db_postgrest_api
#' @param url HTTPS ORDS schema base URL, including any proxy prefix,
#'   for example `"https://data.example.org/ords/reporting"`.
#' @return An R6 client with these methods:
#'   \itemize{
#'     \item \code{$select(resource, query = list(), raw = FALSE)} reads one
#'       AutoREST collection page. Pass native query parameters such as
#'       \code{list(limit = 20L, offset = 0L)}.
#'     \item \code{$request(path, method = "GET", query = list(), body = NULL,
#'       raw = FALSE, trailing_slash = FALSE)} calls a JSON resource. Supply
#'       relative path segments, for example \code{c("api", "sales")}.
#'       Set \code{trailing_slash = TRUE} when the resource URL ends in `/`.
#'   }
#' @details
#' ORDS JWT profiles support external providers including OCI IAM, Keycloak,
#' Auth0 and Okta when their tokens meet the configured issuer, audience,
#' signing-key and privilege requirements. Register a browser authorization
#' code flow in shinyOAuth. An unrelated database or console access token
#' does not authorize an ORDS resource.
#'
#' ORDS enforces its resource privileges. A JWT subject is available to
#' handlers as `:current_user`; it does not automatically switch the handler
#' to a distinct Oracle database schema. Configure user filtering or a
#' supported database security context where per-user data access is needed.
#'
#' Results retain native JSON lists, including `items`, `hasMore`, offsets
#' and links. Large JSON integers are strings. The client does not follow
#' links or redirects; page explicitly with native query parameters.
#' `raw = TRUE` returns an httr2 response. HEAD also returns the response;
#' successful empty responses return invisible `NULL` otherwise.
#'
#' Create the client inside `server()`. Each request obtains a current token
#' pinned to the selected authorization; late responses after account changes
#' or sign-out are discarded. GET and HEAD retry once after HTTP 401. Writes
#' are never replayed automatically. No Oracle client libraries are needed.
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
#' @family platform API clients
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
