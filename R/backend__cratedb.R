#' Query CrateDB as the signed-in user
#'
#' Run SQL through CrateDB's HTTPS interface using the visitor's current JWT
#' access token. CrateDB validates the token, maps it to a database user and
#' enforces that user's privileges.
#'
#' @inheritParams oauth_db_clickhouse_api
#' @param url HTTPS SQL endpoint, including `/_sql` and any proxy prefix.
#' @param schema Default schema, or `NULL` for CrateDB's `doc` default.
#' @return An R6 client with these methods:
#'   \itemize{
#'     \item \code{$query(sql, parameters = list(), raw = FALSE)} returns a
#'       data frame, or the complete result with metadata when `raw = TRUE`.
#'     \item \code{$execute(sql, parameters = list())} runs a statement and
#'       invisibly returns its affected row count (`-1` when unknown).
#'   }
#' @details
#' Configure CrateDB's JWT authentication for HTTP and a database user whose
#' JWT properties match the token's `iss`, `username` and `aud` claims.
#' The provider must issue a compatible access token; an ordinary browser
#' login or an ID token does not establish database access.
#'
#' Create this client inside `server()`. shinyOAuth obtains or renews a token
#' before each request. Account changes, missing permissions, sign-out and
#' session end stop local access; results arriving after an authorization
#' change are discarded. SQL submissions are never retried, including 401
#' responses, because even a query can have side effects. A timed-out query
#' may continue on the server.
#' @section Parameters and results:
#' Use `$1`, `$2`, ... or `?` placeholders with an unnamed list of positional
#' `parameters`. Values are sent separately in CrateDB's JSON `args` array.
#' Scalars, missing values, arrays and named-list objects are supported.
#' Dates and timestamps become ISO strings; cast their placeholders to the
#' desired SQL type. Use strings and SQL casts for exact large integers and
#' decimals. Non-finite numeric parameters are rejected.
#'
#' BIGINT and NUMERIC columns are character vectors, preserving every digit.
#' Smaller integers and floating-point values become R numbers, booleans
#' become logical, and text becomes character. Timestamps and dates retain
#' their epoch-millisecond strings. Arrays, objects and other complex types
#' remain list columns, with JSON numbers preserved as strings. Empty results
#' keep their column types and duplicate column names are preserved.
#'
#' `raw = TRUE` returns metadata and rows, preserving numeric values within
#' rows as strings. HTTP failures expose the HTTP status without including
#' server messages, SQL text or credentials.
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
#' @family platform API clients
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
      result <- private$submit(sql, parameters)
      if (raw) {
        return(result)
      }
      .odb_cratedb_frame(result)
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
    submit = function(sql, parameters) {
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
        auto_unbox = TRUE,
        digits = NA
      )
      resp <- .odb_http_request(
        private$provider(),
        req,
        "CrateDB",
        private$timeout,
        private$ca_bundle
      )
      .odb_cratedb_result(resp)
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
      return(lapply(as.list(value), encode))
    }
    if (is.na(value)) NULL else unname(value)
  }
  lapply(parameters, encode)
}

.odb_cratedb_result <- function(resp) {
  # Quote number tokens outside JSON strings before parsing. jsonlite's
  # bigint_as_char alone does not preserve fractional NUMERIC values.
  result <- tryCatch(
    {
      body <- httr2::resp_body_string(resp)
      pattern <- '"(?:[^"\\\\]|\\\\.)*"(*SKIP)(*F)|-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?'
      positions <- gregexpr(pattern, body, perl = TRUE)
      regmatches(body, positions) <- lapply(
        regmatches(body, positions),
        function(x) paste0('"', x, '"')
      )
      jsonlite::fromJSON(body, simplifyVector = FALSE)
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
  if (
    !is.character(count) ||
      length(count) != 1L ||
      is.na(count) ||
      !grepl("^-?[0-9]+$", count) ||
      !is.finite(as.numeric(count)) ||
      as.numeric(count) < -1 ||
      as.numeric(count) > 2^53
  ) {
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
      any(
        !vapply(
          result$cols,
          function(x) is.character(x) && length(x) == 1L && !is.na(x),
          logical(1)
        )
      ) ||
      any(
        !vapply(
          result$rows,
          function(x) is.list(x) && length(x) == length(result$cols),
          logical(1)
        )
      ) ||
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
  .odb_cratedb_frame(result)
  result
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
    if (any(!vapply(values, is.null, logical(1)))) {
      .odb_abort("CrateDB returned a non-null NULL value.", "invalid_response")
    }
    return(rep(NA, length(values)))
  }
  if (
    any(
      !vapply(
        values,
        function(x) is.null(x) || is.atomic(x) && length(x) == 1L,
        logical(1)
      )
    )
  ) {
    .odb_abort(
      "CrateDB returned a non-scalar value for a scalar column.",
      "invalid_response"
    )
  }
  if (type == 3L) {
    if (
      any(!vapply(values, function(x) is.null(x) || is.logical(x), logical(1)))
    ) {
      .odb_abort("CrateDB returned an invalid boolean.", "invalid_response")
    }
    return(vapply(values, function(x) if (is.null(x)) NA else x, logical(1)))
  }
  if (
    any(!vapply(values, function(x) is.null(x) || is.character(x), logical(1)))
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
      c(10L, 11L, 15L, 22L, 24L) &&
      any(!is.na(text) & !grepl(numeric_pattern, text))
  ) {
    .odb_abort(
      "CrateDB returned an invalid exact numeric value.",
      "invalid_response"
    )
  }
  if (type %in% c(6L, 7L, 8L, 9L)) {
    value <- suppressWarnings(as.numeric(text))
    if (
      any(!is.na(text) & is.na(value) & !is.nan(value)) ||
        type %in%
          c(8L, 9L) &&
          any(
            !is.na(value) &
              (!is.finite(value) |
                value != trunc(value) |
                value < -2^31 |
                value > 2^31 - 1)
          )
    ) {
      .odb_abort("CrateDB returned an invalid number.", "invalid_response")
    }
    return(value)
  }
  text
}
