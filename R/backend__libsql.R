#' Query libSQL as the signed-in user
#'
#' Run SQLite SQL against a remote libSQL or compatible Turso endpoint using
#' the visitor's current access token. Results are returned as data frames.
#'
#' @inheritParams oauth_db_connect
#' @inheritParams oauth_db_clickhouse_api
#' @param url HTTPS database base URL, or a `libsql://` URL (uses HTTPS).
#'   A reverse proxy path is allowed; omit `/v2/pipeline`.
#' @return An R6 client with these methods:
#'   \itemize{
#'     \item \code{$query(sql, parameters = list(), raw = FALSE)} returns a
#'       data frame, or a validated Hrana statement result with `raw = TRUE`.
#'     \item \code{$execute(sql, parameters = list())} runs one statement
#'       and invisibly returns its Hrana result, including `affected_row_count`
#'       and `last_insert_rowid`.
#'   }
#' @details
#' The server must accept the access token issued to your shinyOAuth client.
#' Self-hosted libSQL uses Ed25519 signing keys and libSQL permission claims;
#' arbitrary OIDC access tokens are not interchangeable with database tokens.
#' Turso Cloud has a separate external-provider JWKS configuration.
#' See `vignette("libsql", package = "shinyOAuthDB")` for both configurations.
#'
#' Each operation obtains a current token and uses a new Hrana HTTP stream,
#' closing it in the same request. No stream baton or server-provided URL is
#' reused. Calls cannot share transactions, temporary tables or connection
#' state. The helper does not provide a DBI connection or embedded replica.
#'
#' Create the helper inside `server()` and call its methods in render or
#' reactive expressions. Results arriving after account changes, permission
#' loss or sign-out are discarded. Requests use verified HTTPS and never retry,
#' including after HTTP 401. A submitted statement may continue on the server
#' after a timeout or sign-out.
#' @section Parameters and results:
#' Supply an unnamed list for `?` parameters or a fully named list for named
#' parameters such as `:country`. Values are bound separately from SQL.
#' Character, logical, integer, finite numeric, raw vectors and `NULL`/`NA`
#' are supported. Use `I("9223372036854775807")` for an exact signed 64-bit
#' integer; ordinary character values bind as text. Encode dates as strings.
#'
#' SQLite integers are returned as strings to preserve all 64 bits. Floating
#' point values remain numeric, text remains character and blobs use raw
#' vectors in list columns. Columns with mixed SQLite types remain lists.
#' All-null or empty columns use logical missing values; `raw = TRUE`
#' preserves the server's declared column metadata.
#' @examples
#' \dontrun{
#' libsql <- oauth_db_libsql_api(auth$connection, "https://sqlite.example.org")
#' output$rows <- shiny::renderTable({
#'   libsql$query("SELECT id, total FROM orders WHERE country = :country LIMIT 20",
#'     parameters = list(country = "NL"))
#' })
#' }
#' @seealso `vignette("libsql", package = "shinyOAuthDB")`.
#'   [oauth_db_demo()] runs a local libSQL and Keycloak example.
#' @family platform API clients
#' @export
oauth_db_libsql_api <- function(
  authorization,
  url,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  timeout = 30,
  ca_bundle = NULL,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_string(url, "url")
  url <- .odb_http_url(sub("^libsql://", "https://", url))
  .odb_http_options(timeout, ca_bundle)
  provider <- .odb_http_provider(
    authorization,
    target,
    required_scopes,
    min_valid_for,
    session
  )
  .odb_libsql_api$new(provider, url, timeout, ca_bundle)
}

.odb_libsql_api <- R6::R6Class(
  "OAuthLibSQLAPI",
  cloneable = FALSE,
  public = list(
    initialize = function(provider, url, timeout, ca_bundle) {
      private$provider <- provider
      private$url <- url
      private$timeout <- timeout
      private$ca_bundle <- ca_bundle
    },
    query = function(sql, parameters = list(), raw = FALSE) {
      .odb_flag(raw, "raw")
      result <- private$submit(sql, parameters, TRUE)
      if (raw) {
        return(result)
      }
      .odb_libsql_frame(result)
    },
    execute = function(sql, parameters = list()) {
      invisible(private$submit(sql, parameters, FALSE))
    },
    print = function(...) {
      cat("<OAuthLibSQLAPI>\n")
      invisible(self)
    }
  ),
  private = list(
    provider = NULL,
    url = NULL,
    timeout = NULL,
    ca_bundle = NULL,
    submit = function(sql, parameters, want_rows) {
      .odb_string(sql, "sql")
      stmt <- c(
        list(sql = sql, want_rows = want_rows),
        .odb_libsql_parameters(parameters)
      )
      body <- list(
        baton = NULL,
        requests = list(
          list(type = "execute", stmt = stmt),
          list(type = "close")
        )
      )
      req <- httr2::request(paste0(private$url, "/v2/pipeline"))
      req <- httr2::req_body_json(req, body, auto_unbox = TRUE)
      req <- httr2::req_headers(req, Accept = "application/json")
      # libcurl can replay a POST when a reused connection loses its response.
      req <- httr2::req_options(req, fresh_connect = TRUE, forbid_reuse = TRUE)
      resp <- .odb_http_request(
        private$provider(),
        req,
        "libSQL",
        private$timeout,
        private$ca_bundle
      )
      pipeline <- .odb_http_json(resp, "libSQL")
      if (
        !is.list(pipeline) ||
          !"baton" %in% names(pipeline) ||
          !is.null(pipeline[["baton"]]) ||
          !.odb_libsql_array(pipeline[["results"]]) ||
          length(pipeline[["results"]]) != 2L
      ) {
        .odb_libsql_invalid()
      }
      results <- pipeline[["results"]]
      for (i in seq_along(results)) {
        item <- results[[i]]
        if (!is.list(item)) {
          .odb_libsql_invalid()
        }
        if (identical(item[["type"]], "error")) {
          .odb_abort(
            "The libSQL statement failed. Check the SQL and server permissions.",
            "query_failed"
          )
        }
        if (
          !identical(item[["type"]], "ok") ||
            !is.list(item[["response"]]) ||
            !identical(item[["response"]][["type"]], c("execute", "close")[[i]])
        ) {
          .odb_libsql_invalid()
        }
      }
      result <- results[[1L]][["response"]][["result"]]
      .odb_libsql_validate(result)
      result
    }
  )
)

.odb_libsql_invalid <- function() {
  .odb_abort("libSQL returned an invalid Hrana response.", "invalid_response")
}
.odb_libsql_array <- function(value) is.list(value) && is.null(names(value))
.odb_libsql_string <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value)
}

.odb_libsql_integer <- function(value, unsigned = FALSE) {
  if (
    !.odb_libsql_string(value) ||
      !grepl(
        if (unsigned) "^(0|[1-9][0-9]*)$" else "^-?(0|[1-9][0-9]*)$",
        value
      )
  ) {
    return(FALSE)
  }
  limit <- if (unsigned) {
    "18446744073709551615"
  } else if (startsWith(value, "-")) {
    "9223372036854775808"
  } else {
    "9223372036854775807"
  }
  digits <- sub("^-", "", value)
  nchar(digits) < nchar(limit) ||
    nchar(digits) == nchar(limit) && digits <= limit
}

.odb_libsql_parameters <- function(parameters) {
  if (!is.list(parameters)) {
    .odb_abort("parameters must be a list of SQLite values.")
  }
  nms <- names(parameters)
  if (!is.null(nms)) {
    .odb_named_args(parameters, "parameters")
    if (any(!grepl("^[:@$]?[A-Za-z_][A-Za-z0-9_]*$", nms))) {
      .odb_abort("Invalid SQLite parameter name.")
    }
  }
  values <- lapply(parameters, function(value) {
    if (is.null(value)) {
      return(list(type = "null"))
    }
    if (is.raw(value)) {
      return(list(
        type = "blob",
        base64 = sub("=+$", "", as.character(openssl::base64_encode(value)))
      ))
    }
    if (inherits(value, "AsIs")) {
      if (!.odb_libsql_integer(value)) {
        .odb_abort(
          "I() parameters must contain one signed 64-bit integer string."
        )
      }
      return(list(type = "integer", value = as.character(value)))
    }
    if (
      !is.atomic(value) ||
        length(value) != 1L ||
        !is.null(dim(value)) ||
        is.object(value) ||
        !typeof(value) %in% c("logical", "integer", "double", "character")
    ) {
      .odb_abort(
        "Each parameter must be a scalar SQLite value, a raw vector or NULL."
      )
    }
    if (is.na(value) && !is.nan(value)) {
      return(list(type = "null"))
    }
    if (is.character(value)) {
      return(list(type = "text", value = value))
    }
    if (is.logical(value) || is.integer(value)) {
      return(list(type = "integer", value = as.character(as.integer(value))))
    }
    if (!is.finite(value)) {
      .odb_abort("Numeric SQLite parameters must be finite.")
    }
    list(type = "float", value = unname(value))
  })
  if (is.null(nms)) {
    return(list(args = values))
  }
  list(
    named_args = unname(Map(
      function(name, value) list(name = name, value = value),
      nms,
      values
    ))
  )
}

.odb_libsql_value <- function(value) {
  if (!is.list(value)) {
    .odb_libsql_invalid()
  }
  type <- value[["type"]]
  if (identical(type, "null")) {
    return(NULL)
  }
  if (identical(type, "integer") && .odb_libsql_integer(value[["value"]])) {
    return(value[["value"]])
  }
  if (identical(type, "text") && .odb_libsql_string(value[["value"]])) {
    return(value[["value"]])
  }
  if (
    identical(type, "float") &&
      is.numeric(value[["value"]]) &&
      length(value[["value"]]) == 1L &&
      is.finite(value[["value"]])
  ) {
    return(value[["value"]])
  }
  if (
    identical(type, "blob") &&
      .odb_libsql_string(value[["base64"]]) &&
      grepl(
        "^([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{2}(==)?|[A-Za-z0-9+/]{3}=?)?$",
        value[["base64"]]
      )
  ) {
    text <- sub("=+$", "", value[["base64"]])
    padded <- paste0(text, strrep("=", (4L - nchar(text) %% 4L) %% 4L))
    bytes <- tryCatch(openssl::base64_decode(padded), error = function(e) {
      .odb_libsql_invalid()
    })
    if (
      !identical(
        sub("=+$", "", as.character(openssl::base64_encode(bytes))),
        text
      )
    ) {
      .odb_libsql_invalid()
    }
    return(bytes)
  }
  .odb_libsql_invalid()
}

.odb_libsql_validate <- function(result) {
  if (
    !is.list(result) ||
      !.odb_libsql_array(result[["cols"]]) ||
      !.odb_libsql_array(result[["rows"]])
  ) {
    .odb_libsql_invalid()
  }
  for (column in result[["cols"]]) {
    if (
      !is.list(column) ||
        !"name" %in% names(column) ||
        !is.null(column[["name"]]) && !.odb_libsql_string(column[["name"]]) ||
        !is.null(column[["decltype"]]) &&
          !.odb_libsql_string(column[["decltype"]])
    ) {
      .odb_libsql_invalid()
    }
  }
  for (row in result[["rows"]]) {
    if (!.odb_libsql_array(row) || length(row) != length(result[["cols"]])) {
      .odb_libsql_invalid()
    }
    for (value in row) {
      .odb_libsql_value(value)
    }
  }
  count <- result[["affected_row_count"]]
  valid_count <- if (is.character(count)) {
    .odb_libsql_integer(count, unsigned = TRUE)
  } else {
    is.numeric(count) &&
      length(count) == 1L &&
      is.finite(count) &&
      count >= 0 &&
      count <= 9007199254740991 &&
      count == floor(count)
  }
  if (
    !valid_count ||
      !"last_insert_rowid" %in% names(result) ||
      !is.null(result[["last_insert_rowid"]]) &&
        !.odb_libsql_integer(result[["last_insert_rowid"]])
  ) {
    .odb_libsql_invalid()
  }
  invisible(NULL)
}

.odb_libsql_frame <- function(result) {
  columns <- lapply(seq_along(result[["cols"]]), function(i) {
    values <- lapply(result[["rows"]], function(row) {
      .odb_libsql_value(row[[i]])
    })
    types <- vapply(result[["rows"]], function(row) row[[i]][["type"]], "")
    kinds <- setdiff(unique(types), "null")
    if (!length(kinds)) {
      return(rep(NA, length(values)))
    }
    if (length(kinds) > 1L || identical(kinds, "blob")) {
      return(values)
    }
    if (identical(kinds, "float")) {
      return(vapply(values, function(x) if (is.null(x)) NA_real_ else x, 0))
    }
    vapply(values, function(x) if (is.null(x)) NA_character_ else x, "")
  })
  names(columns) <- vapply(
    result[["cols"]],
    function(col) if (is.null(col[["name"]])) "" else col[["name"]],
    ""
  )
  structure(
    columns,
    class = "data.frame",
    row.names = seq_along(result[["rows"]])
  )
}
