#' Query ClickHouse as the signed-in user
#'
#' Run SQL over ClickHouse's HTTPS interface with the visitor's current
#' bearer token. Query results are returned as data frames.
#'
#' @inheritParams oauth_db_connect
#' @param url HTTPS query endpoint, including its port and proxy path if needed.
#' @param database Default database, or `NULL` for the user's server default.
#' @param timeout Maximum seconds for one HTTP operation.
#' @param ca_bundle Optional trusted CA certificate bundle path.
#' @return An R6 client with these methods:
#'   \itemize{
#'     \item \code{$query(sql, parameters = list(), raw = FALSE)} returns a
#'       data frame, or the parsed JSONCompact response when `raw = TRUE`.
#'     \item \code{$execute(sql, parameters = list())} runs a statement
#'       without collecting a result and invisibly returns its httr2 response.
#'   }
#' @details
#' The endpoint must accept externally issued bearer tokens. Custom identity
#' providers currently require ClickHouse Cloud Enterprise, service version
#' 26.4 or later (26.8 for EC signing keys). This helper does not use Cloud
#' management API keys, database passwords, or a service account.
#'
#' Configure a shinyOAuth client for the provider and audience trusted by
#' your ClickHouse service. Create the API client inside `server()` and call
#' its methods from render or reactive expressions. Tokens are obtained for
#' each request, and a result is discarded if its authorization changes.
#'
#' SQL is sent as the POST body. Requests are never replayed automatically,
#' including HTTP 401, because a submitted statement may have changed data.
#' Token renewal before each request is handled by shinyOAuth. A timeout or
#' sign-out stops local access; a submitted query may continue on the server.
#' @section Parameters:
#' Use native typed placeholders, such as \code{{country:String}} or
#' \code{{id:UInt64}}, with a named list of scalar R values in `parameters`.
#' Values are sent separately through the HTTP `param_` mechanism. Character,
#' logical, integer, numeric, `Date`, `POSIXct`, and missing values are
#' supported. Use character values for exact large integers and decimals.
#' For arrays, tuples, or already encoded values, wrap native ClickHouse
#' escaped-format strings in `I()` to preserve their encoding.
#' @section Result types:
#' Signed and unsigned integers of 64 bits or more, and decimals, remain
#' strings. Smaller integers and floats become R numbers; Bool becomes
#' logical and Date/Date32 become `Date`. Timestamps keep their server string
#' representation. Arrays, maps, tuples, JSON, and other complex values stay
#' in list columns. Empty results preserve column metadata.
#'
#' Omit FORMAT clauses and output-format overrides from SQL. The client
#' requests JSONCompact with exact numeric quoting and validates the entire
#' response before returning any rows. `raw = TRUE` preserves metadata and
#' statistics, with JSON arrays decoded as R lists.
#' @examples
#' \dontrun{
#' clickhouse <- oauth_db_clickhouse_api(auth$connection,
#'   url = "https://example.clickhouse.cloud:8443", database = "reporting")
#' output$rows <- shiny::renderTable({
#'   clickhouse$query("SELECT id, total FROM orders WHERE country = {country:String} LIMIT 20",
#'     parameters = list(country = "NL"))
#' })
#' }
#' @seealso `vignette("clickhouse", package = "shinyOAuthDB")`.
#' @family platform API clients
#' @export
oauth_db_clickhouse_api <- function(
  authorization, url, database = NULL, target = NULL, required_scopes = character(),
  min_valid_for = 60, timeout = 300, ca_bundle = NULL,
  session = shiny::getDefaultReactiveDomain()
) {
  url <- .odb_http_url(url)
  .odb_string(database, "database", optional = TRUE)
  .odb_http_options(timeout, ca_bundle)
  provider <- .odb_http_provider(authorization, target, required_scopes, min_valid_for, session)
  .odb_clickhouse_api$new(provider, url, database, timeout, ca_bundle)
}

.odb_clickhouse_api <- R6::R6Class("OAuthClickHouseAPI", cloneable = FALSE,
  public = list(
    initialize = function(provider, url, database, timeout, ca_bundle) {
      private$provider <- provider
      private$url <- url
      private$database <- database
      private$timeout <- timeout
      private$ca_bundle <- ca_bundle
    },
    query = function(sql, parameters = list(), raw = FALSE) {
      .odb_flag(raw, "raw")
      result <- .odb_http_json(private$submit(sql, parameters), "ClickHouse")
      if (!is.list(result) || !is.null(result$exception)) {
        .odb_abort("The ClickHouse query failed. Inspect it in the server query log.", "query_failed")
      }
      if (raw) {
        .odb_clickhouse_validate(result)
        return(result)
      }
      .odb_clickhouse_frame(result)
    },
    execute = function(sql, parameters = list()) {
      resp <- private$submit(sql, parameters)
      if (httr2::resp_has_body(resp)) {
        result <- .odb_http_json(resp, "ClickHouse")
        if (!is.list(result) || !is.null(result$exception)) .odb_abort("The ClickHouse statement failed.", "query_failed")
        .odb_clickhouse_validate(result)
      }
      invisible(resp)
    },
    print = function(...) {
      cat("<OAuthClickHouseAPI>\n")
      invisible(self)
    }
  ),
  private = list(
    provider = NULL, url = NULL, database = NULL, timeout = NULL, ca_bundle = NULL,
    submit = function(sql, parameters) {
      .odb_string(sql, "sql")
      query <- c(list(default_format = "JSONCompact", wait_end_of_query = "1",
        output_format_json_quote_64bit_integers = "1", output_format_json_quote_decimals = "1",
        output_format_json_quote_denormals = "1"), .odb_clickhouse_parameters(parameters))
      if (!is.null(private$database)) query$database <- private$database
      req <- httr2::request(paste0(private$url, "/"))
      req <- do.call(httr2::req_url_query, c(list(req), query))
      req <- httr2::req_body_raw(req, charToRaw(enc2utf8(sql)), type = "text/plain; charset=utf-8")
      resp <- .odb_http_request(private$provider(), req, "ClickHouse", private$timeout, private$ca_bundle)
      code <- httr2::resp_header(resp, "X-ClickHouse-Exception-Code")
      if (!is.null(code) && !identical(code, "0")) {
        .odb_abort("The ClickHouse statement failed. Inspect it in the server query log.", "query_failed")
      }
      resp
    }
  )
)

.odb_clickhouse_parameters <- function(parameters) {
  if (!is.list(parameters)) .odb_abort("parameters must be a named list of scalar R values.")
  .odb_named_args(parameters, "parameters")
  if (!length(parameters)) return(list())
  if (any(!grepl("^[A-Za-z_][A-Za-z0-9_]*$", names(parameters)))) .odb_abort("Invalid ClickHouse parameter name.")
  values <- lapply(parameters, function(value) {
    if (is.null(value)) return("\\N")
    if (inherits(value, "AsIs")) {
      if (!is.character(value) || length(value) != 1L || is.na(value)) {
        .odb_abort("I() parameters must contain one non-missing, already encoded string.")
      }
      return(as.character(value))
    }
    if (!is.atomic(value) || length(value) != 1L || !is.null(dim(value)) ||
        is.factor(value) || is.object(value) && !inherits(value, c("Date", "POSIXct"))) {
      .odb_abort("Each parameter must be a scalar; wrap encoded array or tuple strings in I().")
    }
    if (is.na(value) && !is.nan(value)) return("\\N")
    text <- if (inherits(value, "POSIXct")) {
      timestamp <- format(value, "%Y-%m-%d %H:%M:%OS6", tz = "UTC")
      # DateTime rejects fractional seconds, even when the fraction is zero.
      sub("\\.$", "", sub("0+$", "", timestamp))
    }
    else if (inherits(value, "Date")) as.character(value)
    else if (is.logical(value)) if (value) "1" else "0"
    else if (is.numeric(value)) format(value, scientific = FALSE, trim = TRUE, digits = 17, decimal.mark = ".")
    else as.character(value)
    text <- gsub("\\", "\\\\", text, fixed = TRUE)
    text <- gsub("\t", "\\t", text, fixed = TRUE)
    text <- gsub("\n", "\\n", text, fixed = TRUE)
    gsub("\r", "\\r", text, fixed = TRUE)
  })
  stats::setNames(values, paste0("param_", names(parameters)))
}

.odb_clickhouse_validate <- function(result, validate_values = TRUE) {
  meta <- result$meta
  rows <- result$data
  if (!is.list(meta) || !is.list(rows) ||
      !all(vapply(meta, function(x) is.list(x) && is.character(x$name) && length(x$name) == 1L &&
        !is.na(x$name) && is.character(x$type) && length(x$type) == 1L && !is.na(x$type), logical(1))) ||
      !all(vapply(rows, function(row) is.list(row) && length(row) == length(meta), logical(1)))) {
    .odb_abort("ClickHouse returned invalid JSONCompact metadata or rows. Omit FORMAT clauses from SQL.", "invalid_response")
  }
  if (!is.null(result$rows) && (!is.numeric(result$rows) || length(result$rows) != 1L ||
      is.na(result$rows) || result$rows != length(rows))) .odb_abort("ClickHouse returned an inconsistent row count.", "invalid_response")
  if (validate_values) for (i in seq_along(meta)) {
    .odb_clickhouse_column(lapply(rows, function(row) row[[i]]), meta[[i]]$type)
  }
  invisible(NULL)
}

.odb_clickhouse_frame <- function(result) {
  .odb_clickhouse_validate(result, validate_values = FALSE)
  meta <- result$meta
  rows <- result$data
  columns <- lapply(seq_along(meta), function(i) {
    .odb_clickhouse_column(lapply(rows, function(row) row[[i]]), meta[[i]]$type)
  })
  names(columns) <- vapply(meta, function(x) x$name, "")
  structure(columns, class = "data.frame", row.names = seq_along(rows))
}

.odb_clickhouse_column <- function(values, type) {
  repeat {
    inner <- sub("^(Nullable|LowCardinality)\\((.*)\\)$", "\\2", type)
    if (identical(inner, type)) break
    type <- inner
  }
  if (grepl("^(Array|Map|Tuple|Nested|Object|JSON|Dynamic|Variant|AggregateFunction|SimpleAggregateFunction)($|\\()", type)) return(values)
  if (any(!vapply(values, function(x) is.null(x) || is.atomic(x) && length(x) == 1L, logical(1)))) {
    .odb_abort("ClickHouse returned a non-scalar value for a scalar column.", "invalid_response")
  }
  text <- vapply(values, function(x) if (is.null(x)) NA_character_ else as.character(x), "")
  if (grepl("^(U?Int(8|16|32)|Float(32|64))$", type)) {
    text[!is.na(text) & tolower(text) %in% c("nan", "+nan", "-nan")] <- "NaN"
    value <- suppressWarnings(as.numeric(text))
    if (any(!is.na(text) & is.na(value) & !is.nan(value))) .odb_abort("ClickHouse returned an invalid number.", "invalid_response")
    return(value)
  }
  if (type == "Bool") {
    if (any(!is.na(text) & !tolower(text) %in% c("true", "false", "1", "0"))) .odb_abort("ClickHouse returned an invalid Bool.", "invalid_response")
    return(ifelse(is.na(text), NA, tolower(text) %in% c("true", "1")))
  }
  if (type %in% c("Date", "Date32")) return(tryCatch(as.Date(text),
    error = function(e) .odb_abort("ClickHouse returned an invalid date.", "invalid_response")))
  text
}
