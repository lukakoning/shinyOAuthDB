#' Query Neo4j as the signed-in user
#'
#' Run Cypher queries with each Shiny visitor's access token and Neo4j roles.
#' The client uses the HTTPS Query API v2 and returns data frames, keeping
#' nodes, relationships, paths and other nested values in list columns.
#'
#' @inheritParams oauth_db_opensearch_api
#' @param url Neo4j HTTPS base URL, including any reverse-proxy prefix.
#'   Use the Query API host, not a `neo4j+s://` or `bolt://` connection URI.
#' @param database Database name, default `"neo4j"`.
#' @return A client object with these methods:
#'   \itemize{
#'     \item \code{$query(statement, parameters = list(), raw = FALSE)} runs
#'       one Cypher statement. Use named parameters such as \code{list(name = "Alice")}
#'       for \code{$name} placeholders. Returns a data frame, or the parsed
#'       Query API response with fields, values and metadata when \code{raw = TRUE}.
#'     \item \code{$execute(statement, parameters = list())} runs one statement
#'       and invisibly returns the server's update counters.
#'   }
#' @details
#' Configure Neo4j Enterprise SSO to accept the provider's JWT access tokens
#' and map users or groups to database roles. Aura requires a tier and SSO
#' configuration that permit user-token access to the database's Query API.
#' Console API credentials do not establish database access. Query API v2
#' requires Neo4j 5.19 or later; self-managed versions before 5.25 must enable it.
#'
#' Create the client inside `server()`. Each call gets a current access token
#' and discards responses after sign-out, account changes or lost required
#' scopes. Requests require verified HTTPS, do not follow redirects and never
#' replay a statement, including after HTTP 401. Neo4j query errors raise an
#' error even when the server returns HTTP 202 or `raw = TRUE`.
#'
#' Each statement uses an auto-commit transaction. There is no persistent
#' Bolt connection, explicit transaction handle, automatic pagination or
#' retained bookmark. A submitted write may commit after a client timeout;
#' check its outcome before resubmitting it.
#' @section Parameters and results:
#' Parameters are a named list of JSON-compatible values. Nested named lists
#' become maps and unnamed lists become arrays. Missing scalar values become
#' JSON null. Numbers must be finite; pass exact large integers as strings
#' and convert them in Cypher with `toInteger($value)`. Dates and timestamps
#' become ISO strings; use `date($value)` or `datetime($value)` in the query.
#'
#' Results use Neo4j's plain JSON format. Large JSON integers remain strings;
#' temporal, spatial and binary values keep the server's string representation.
#' Scalar columns of one type become atomic vectors; mixed or nested values
#' remain lists. Empty or entirely null columns are logical. Duplicate field
#' names are preserved. Use `raw = TRUE` for bookmarks, notifications and
#' native graph values; discard saved results and metadata when changing users.
#' @examples
#' \dontrun{
#' graph <- oauth_db_neo4j_api(auth$connection,
#'   url = "https://graph.example.org:7473", database = "neo4j")
#' output$rows <- shiny::renderTable({
#'   graph$query("MATCH (p:Person) WHERE p.country = $country RETURN p.name AS name LIMIT 20",
#'     parameters = list(country = "NL"))
#' })
#' }
#' @seealso `vignette("neo4j", package = "shinyOAuthDB")`.
#' @export
oauth_db_neo4j_api <- function(
  authorization,
  url,
  database = "neo4j",
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  timeout = 30,
  ca_bundle = NULL,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("jsonlite")
  url <- .odb_http_url(url)
  .odb_string(database, "database")
  path <- .odb_http_path(c("db", database, "query", "v2"))
  .odb_http_options(timeout, ca_bundle)
  provider <- .odb_http_provider(
    authorization,
    target,
    required_scopes,
    min_valid_for,
    session
  )
  .odb_neo4j_api$new(provider, paste0(url, "/", path), timeout, ca_bundle)
}

.odb_neo4j_api <- R6::R6Class(
  "OAuthNeo4jAPI",
  cloneable = FALSE,
  public = list(
    initialize = function(provider, url, timeout, ca_bundle) {
      private$provider <- provider
      private$url <- url
      private$timeout <- timeout
      private$ca_bundle <- ca_bundle
    },
    query = function(statement, parameters = list(), raw = FALSE) {
      .odb_flag(raw, "raw")
      result <- private$submit(statement, parameters, counters = FALSE)
      if (raw) result else .odb_neo4j_frame(result$data)
    },
    execute = function(statement, parameters = list()) {
      result <- private$submit(statement, parameters, counters = TRUE)
      if (!.odb_neo4j_object(result$counters)) {
        .odb_abort(
          "Neo4j returned invalid update counters.",
          "invalid_response"
        )
      }
      invisible(result$counters)
    },
    print = function(...) {
      cat("<OAuthNeo4jAPI>\n")
      invisible(self)
    }
  ),
  private = list(
    provider = NULL,
    url = NULL,
    timeout = NULL,
    ca_bundle = NULL,
    submit = function(statement, parameters, counters) {
      .odb_string(statement, "statement")
      parameters <- .odb_neo4j_parameters(parameters)
      body <- list(statement = statement)
      if (length(parameters)) {
        body$parameters <- parameters
      }
      if (counters) {
        body$includeCounters <- TRUE
      }
      req <- httr2::request(private$url)
      req <- httr2::req_headers(req, Accept = "application/json")
      req <- httr2::req_body_json(req, body, auto_unbox = TRUE, digits = 17)
      resp <- .odb_http_request(
        private$provider(),
        req,
        "Neo4j",
        private$timeout,
        private$ca_bundle
      )
      .odb_neo4j_result(resp)
    }
  )
)

.odb_neo4j_parameters <- function(parameters) {
  if (!is.list(parameters) || is.object(parameters)) {
    .odb_abort("parameters must be a named list of Cypher parameters.")
  }
  .odb_named_args(parameters, "Cypher parameters")
  encode <- function(value) {
    if (is.null(value)) {
      return(NULL)
    }
    if (inherits(value, c("Date", "POSIXct"))) {
      if (
        length(value) != 1L || !is.finite(as.numeric(value)) && !is.na(value)
      ) {
        .odb_abort(
          "Date and timestamp parameters must be scalar and finite or missing."
        )
      }
      if (is.na(value)) {
        return(NULL)
      }
      if (inherits(value, "Date")) {
        return(format(value, "%Y-%m-%d"))
      }
      return(format(value, "%Y-%m-%dT%H:%M:%OS6Z", tz = "UTC"))
    }
    if (is.object(value) || !is.null(dim(value))) {
      .odb_abort("Unsupported Neo4j parameter class or dimensions.")
    }
    if (is.list(value)) {
      if (!is.null(names(value))) {
        .odb_named_args(value, "Cypher map fields")
      }
      return(lapply(value, encode))
    }
    if (
      (!is.character(value) && !is.logical(value) && !is.numeric(value)) ||
        is.complex(value)
    ) {
      .odb_abort("Neo4j parameters must contain JSON-compatible values.")
    }
    if (
      is.numeric(value) &&
        any(!is.finite(value) & !is.na(value) | is.nan(value))
    ) {
      .odb_abort("Numeric parameters must be finite or missing.")
    }
    if (length(value) != 1L) {
      return(lapply(unname(as.list(value)), encode))
    }
    if (is.na(value)) NULL else unname(value)
  }
  lapply(parameters, encode)
}

.odb_neo4j_object <- function(value) {
  is.list(value) &&
    !is.null(names(value)) &&
    !anyNA(names(value)) &&
    !anyDuplicated(names(value))
}

.odb_neo4j_array <- function(value) is.list(value) && is.null(names(value))

.odb_neo4j_result <- function(resp) {
  result <- .odb_http_json(resp, "Neo4j")
  invalid <- function() {
    .odb_abort("Neo4j returned an invalid query result.", "invalid_response")
  }
  if (!.odb_neo4j_object(result)) {
    invalid()
  }
  if ("errors" %in% names(result)) {
    if (!.odb_neo4j_array(result$errors)) {
      invalid()
    }
    if (length(result$errors)) {
      .odb_abort(
        "The Neo4j statement failed. Check the query and database permissions.",
        "query_failed"
      )
    }
  }
  data <- result$data
  if (
    !.odb_neo4j_object(data) ||
      !.odb_neo4j_array(data$fields) ||
      !.odb_neo4j_array(data$values) ||
      !all(vapply(
        data$fields,
        function(x) is.character(x) && length(x) == 1L && !is.na(x),
        logical(1)
      )) ||
      !all(vapply(
        data$values,
        function(x) .odb_neo4j_array(x) && length(x) == length(data$fields),
        logical(1)
      ))
  ) {
    invalid()
  }
  result
}

.odb_neo4j_frame <- function(data) {
  columns <- lapply(seq_along(data$fields), function(i) {
    values <- lapply(data$values, function(row) row[[i]])
    present <- Filter(Negate(is.null), values)
    if (!length(present)) {
      return(rep(NA, length(values)))
    }
    for (kind in c("logical", "numeric", "character")) {
      matches <- switch(
        kind,
        logical = is.logical,
        numeric = is.numeric,
        character = is.character
      )
      if (
        all(vapply(
          present,
          function(x) matches(x) && length(x) == 1L,
          logical(1)
        ))
      ) {
        missing <- switch(
          kind,
          logical = NA,
          numeric = NA_real_,
          character = NA_character_
        )
        return(vapply(
          values,
          function(x) if (is.null(x)) missing else x,
          missing
        ))
      }
    }
    values
  })
  names(columns) <- unlist(data$fields, use.names = FALSE)
  structure(columns, class = "data.frame", row.names = seq_along(data$values))
}
