#' Query CrateDB as the signed-in user
#'
#' Query CrateDB data using the signed-in visitor's database privileges.
#' CrateDB checks their access token and matches it to a database user.
#' The client sends SQL over HTTPS and returns data frames.
#'
#' @inheritParams oauth_db_clickhouse_api
#' @param url HTTPS SQL endpoint, including `/_sql` and any proxy prefix.
#' @param schema Default schema, or `NULL` for CrateDB's `doc` default.
#' @return A client object with these methods:
#'   \itemize{
#'     \item \code{$query(sql, parameters = list(), raw = FALSE)} returns a
#'       data frame, or the complete result with metadata when `raw = TRUE`.
#'     \item \code{$execute(sql, parameters = list())} runs a statement and
#'       invisibly returns its affected row count (`-1` when unknown).
#'   }
#' @details
#' Configure CrateDB's HTTP JWT authentication and a database user matching
#' the token's `iss`, `username` and `aud` claims. The CrateDB vignette
#' explains the provider requirements.
#'
#' Create the client inside `server()` and call its methods from render or
#' reactive expressions. Each request uses a current token and discards
#' results after sign-out or account changes. SQL doesn't retry automatically.
#' A submitted query can continue after a timeout; check a failed write's
#' outcome before resubmitting it.
#' @section Parameters and results:
#' Use `$1`, `$2`, ... or `?` placeholders with an unnamed list of values in
#' `parameters`. Values travel separately from SQL. Scalars, missing values,
#' arrays and named-list objects are supported. Dates and timestamps become
#' ISO strings; cast the placeholders to the SQL type you need. For exact
#' large integers or decimals, use strings and SQL casts. Numeric parameters
#' must be finite.
#'
#' BIGINT and NUMERIC results stay as strings. Smaller numbers become R
#' numeric values and booleans become logical. Dates and timestamps use
#' epoch-millisecond strings; complex types use list columns with numbers
#' preserved as strings. Empty results keep their column types.
#'
#' `raw = TRUE` returns metadata and rows, with numeric row values kept as
#' strings. HTTP errors report the status without exposing server messages
#' or credentials.
#' @examples
#' \dontrun{
#' crate <- oauth_db_cratedb_api(auth$connection,
#'   url = "https://crate.example.org:4200/_sql", schema = "doc")
#' output$rows <- shiny::renderTable({
#'   crate$query("SELECT id, total FROM orders WHERE country = $1 LIMIT 20",
#'     parameters = list("NL"))
#' })
#' }
#' @seealso `vignette("cratedb", package = "shinyOAuthDB")`.
#'   [oauth_db_demo()] runs a local CrateDB and Keycloak example.
#' @export
oauth_db_cratedb_api <- function(
  authorization,
  url,
  schema = NULL,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  timeout = 300,
  ca_bundle = NULL,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("jsonlite")
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
  .odb_cratedb_api$new(provider, url, schema, timeout, ca_bundle)
}

.odb_cratedb_api <- R6::R6Class(
  "OAuthCrateDBAPI",
  cloneable = FALSE,
  public = list(
    initialize = function(provider, url, schema, timeout, ca_bundle) {
      private$provider <- provider
      private$url <- url
      private$schema <- schema
      private$timeout <- timeout
      private$ca_bundle <- ca_bundle
    },
    query = function(sql, parameters = list(), raw = FALSE) {
      .odb_flag(raw, "raw")
      private$submit(sql, parameters, raw = raw)
    },
    execute = function(sql, parameters = list()) {
      result <- private$submit(sql, parameters)
      invisible(result$rowcount)
    },
    print = function(...) {
      cat("<OAuthCrateDBAPI>\n")
      invisible(self)
    }
  ),
  private = list(
    provider = NULL,
    url = NULL,
    schema = NULL,
    timeout = NULL,
    ca_bundle = NULL,
    submit = function(sql, parameters, raw = TRUE) {
      .odb_string(sql, "sql")
      args <- .odb_cratedb_parameters(parameters)
      req <- httr2::request(private$url)
      req <- httr2::req_url_query(req, types = "true")
      if (!is.null(private$schema)) {
        req <- httr2::req_headers(req, `Default-Schema` = private$schema)
      }
      req <- httr2::req_body_json(
        req,
        list(stmt = sql, args = args),
        auto_unbox = TRUE
      )
      resp <- .odb_http_request(
        private$provider(),
        req,
        "CrateDB",
        private$timeout,
        private$ca_bundle
      )
      .odb_cratedb_result(resp, raw = raw)
    }
  )
)

.odb_cratedb_parameters <- function(parameters) {
  if (!is.list(parameters) || !is.null(names(parameters))) {
    .odb_abort("parameters must be an unnamed list of positional values.")
  }
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
      .odb_abort("Unsupported CrateDB parameter class or dimensions.")
    }
    if (is.list(value)) {
      if (!is.null(names(value))) {
        .odb_named_args(value, "Object parameter fields")
      }
      return(lapply(value, encode))
    }
    if (
      !is.character(value) &&
        !is.logical(value) &&
        !is.numeric(value) ||
        is.complex(value)
    ) {
      .odb_abort("CrateDB parameters must contain JSON-compatible values.")
    }
    if (
      is.numeric(value) &&
        any(!is.finite(value) & !is.na(value) | is.nan(value))
    ) {
      .odb_abort(
        "Numeric parameters must be finite or missing; pass exact values as strings and use SQL casts."
      )
    }
    if (length(value) != 1L) {
      return(lapply(unname(as.list(value)), encode))
    }
    if (is.na(value)) NULL else unname(value)
  }
  lapply(parameters, encode)
}

.odb_cratedb_result <- function(resp, raw = TRUE) {
  # Quote number tokens outside JSON strings before parsing. jsonlite's
  # bigint_as_char alone does not preserve fractional NUMERIC values.
  result <- tryCatch(
    {
      httr2::resp_check_content_type(
        resp,
        valid_types = "application/json",
        valid_suffix = "json"
      )
      body <- httr2::resp_body_string(resp, encoding = "UTF-8")
      if (!isTRUE(jsonlite::validate(body))) {
        stop("Invalid JSON response.")
      }
      pattern <- '"(?:[^"\\\\]|\\\\.)*"(*SKIP)(*F)|-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?'
      positions <- gregexpr(pattern, body, perl = TRUE)
      regmatches(body, positions) <- lapply(
        regmatches(body, positions),
        function(x) paste0('"', x, '"')
      )
      jsonlite::parse_json(body, simplifyVector = FALSE)
    },
    error = function(e) {
      .odb_abort(
        "CrateDB returned an invalid JSON response.",
        "invalid_response"
      )
    }
  )
  if (!is.list(result) || !is.null(result$error)) {
    .odb_abort("The CrateDB statement failed.", "query_failed")
  }
  count <- result$rowcount
  valid_count <- is.character(count) &&
    length(count) == 1L &&
    !is.na(count) &&
    grepl("^-?[0-9]+$", count)
  if (valid_count) {
    magnitude <- sub("^0+", "", sub("^-", "", count))
    valid_count <- (!startsWith(count, "-") || magnitude %in% c("", "1")) &&
      (nchar(magnitude) < 16L ||
        nchar(magnitude) == 16L && magnitude <= "9007199254740992")
  }
  if (!valid_count) {
    .odb_abort("CrateDB returned an invalid row count.", "invalid_response")
  }
  result$rowcount <- as.numeric(count)
  types <- function(type) {
    if (is.list(type)) {
      if (length(type) != 2L || !identical(type[[1L]], "100")) {
        .odb_abort(
          "CrateDB returned invalid array type metadata.",
          "invalid_response"
        )
      }
      return(list(100L, types(type[[2L]])))
    }
    if (
      !is.character(type) ||
        length(type) != 1L ||
        is.na(type) ||
        !grepl("^[0-9]{1,6}$", type)
    ) {
      .odb_abort("CrateDB returned invalid column types.", "invalid_response")
    }
    as.integer(type)
  }
  if (
    !is.list(result$cols) ||
      !is.list(result$col_types) ||
      !is.list(result$rows) ||
      length(result$cols) != length(result$col_types) ||
      !all(vapply(
        result$cols,
        function(x) is.character(x) && length(x) == 1L && !is.na(x),
        logical(1)
      )) ||
      !all(vapply(
        result$rows,
        function(x) is.list(x) && length(x) == length(result$cols),
        logical(1)
      )) ||
      length(result$cols) &&
        result$rowcount >= 0 &&
        result$rowcount != length(result$rows)
  ) {
    .odb_abort(
      "CrateDB returned inconsistent column metadata or rows.",
      "invalid_response"
    )
  }
  result$col_types <- lapply(result$col_types, types)
  if (!is.null(result$duration)) {
    duration <- suppressWarnings(as.numeric(result$duration))
    if (length(duration) != 1L || !is.finite(duration) || duration < 0) {
      .odb_abort("CrateDB returned an invalid duration.", "invalid_response")
    }
    result$duration <- duration
  }
  # Validate every cell even when the caller requests metadata or a row count.
  frame <- .odb_cratedb_frame(result)
  if (raw) result else frame
}

.odb_cratedb_frame <- function(result) {
  columns <- lapply(seq_along(result$cols), function(i) {
    .odb_cratedb_column(
      lapply(result$rows, function(row) row[[i]]),
      result$col_types[[i]]
    )
  })
  names(columns) <- unlist(result$cols, use.names = FALSE)
  structure(columns, class = "data.frame", row.names = seq_along(result$rows))
}

.odb_cratedb_column <- function(values, type) {
  if (is.list(type)) {
    for (value in values) {
      if (is.null(value)) {
        next
      }
      if (!is.list(value) || !is.null(names(value))) {
        .odb_abort("CrateDB returned an invalid array.", "invalid_response")
      }
      .odb_cratedb_column(value, type[[2L]])
    }
    return(values)
  }
  if (type %in% c(12L, 13L, 14L, 16L, 17L, 18L, 21L, 26L, 28L) || type > 30L) {
    return(values)
  }
  if (type == 0L) {
    if (!all(vapply(values, is.null, logical(1)))) {
      .odb_abort("CrateDB returned a non-null NULL value.", "invalid_response")
    }
    return(rep(NA, length(values)))
  }
  if (
    !all(vapply(
      values,
      function(x) is.null(x) || is.atomic(x) && length(x) == 1L,
      logical(1)
    ))
  ) {
    .odb_abort(
      "CrateDB returned a non-scalar value for a scalar column.",
      "invalid_response"
    )
  }
  if (type == 3L) {
    if (
      !all(vapply(values, function(x) is.null(x) || is.logical(x), logical(1)))
    ) {
      .odb_abort("CrateDB returned an invalid boolean.", "invalid_response")
    }
    return(vapply(values, function(x) if (is.null(x)) NA else x, logical(1)))
  }
  if (
    !all(vapply(values, function(x) is.null(x) || is.character(x), logical(1)))
  ) {
    .odb_abort(
      "CrateDB returned an unexpected scalar type.",
      "invalid_response"
    )
  }
  text <- vapply(
    values,
    function(x) if (is.null(x)) NA_character_ else as.character(x),
    ""
  )
  numeric_pattern <- if (type == 22L) {
    "^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$"
  } else {
    "^-?[0-9]+$"
  }
  if (
    type %in%
      c(2L, 10L, 11L, 15L, 22L, 24L) &&
      any(!is.na(text) & !grepl(numeric_pattern, text))
  ) {
    .odb_abort(
      "CrateDB returned an invalid exact numeric value.",
      "invalid_response"
    )
  }
  if (type %in% c(2L, 6L, 7L, 8L, 9L)) {
    value <- suppressWarnings(as.numeric(text))
    bounds <- if (type == 2L) c(-128, 127) else c(-2^31, 2^31 - 1)
    if (
      any(!is.na(text) & is.na(value) & !is.nan(value)) ||
        type %in%
          c(2L, 8L, 9L) &&
          any(
            !is.na(value) &
              (!is.finite(value) |
                value != trunc(value) |
                value < bounds[[1L]] |
                value > bounds[[2L]])
          )
    ) {
      .odb_abort("CrateDB returned an invalid number.", "invalid_response")
    }
    return(value)
  }
  text
}
