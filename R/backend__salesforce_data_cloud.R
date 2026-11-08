#' Query Salesforce Data Cloud as the signed-in user
#'
#' Run Salesforce Data Cloud SQL with the visitor's Salesforce account and
#' data permissions. The client uses Query Connect API and returns data
#' frames. It can share a sign-in with [oauth_db_salesforce_api()].
#'
#' @inheritParams oauth_db_salesforce_api
#' @param dataspace Data Cloud data space API name, default `"default"`.
#' @param page_size Maximum number of rows requested per response.
#' @return A client object with a \code{$query(sql, parameters = list(), raw = FALSE)}
#'   method. It waits for completion, fetches all pages, and returns
#'   a data frame. `raw = TRUE` returns combined `data`, `metadata`, `status`
#'   and `returnedRows`.
#' @details
#' Use [oauth_db_salesforce_client()] with `data_cloud = TRUE`. Users need
#' Data Cloud licensing, access to the data space and query permissions.
#' The client uses your Salesforce org endpoint and API version 64.0 or later.
#'
#' Create the client inside `server()` and call `$query()` from a render or
#' reactive expression. Each request gets a current token and discards
#' results after sign-out or account changes.
#' @section Parameters and results:
#' Use an unnamed list of SQL parameter descriptors with `name`, `type` and
#' `value` strings. For example,
#' `list(list(name = "since", type = "date", value = "2026-01-01"))` binds
#' `:since`. Values travel separately from SQL; use the types Salesforce
#' accepts.
#'
#' BIGINT and NUMERIC results stay as strings to preserve precision. Other
#' numbers become R numeric values and booleans become logical. Dates and
#' times stay as strings; nested and unknown types use list columns. Use
#' `raw = TRUE` for rows, metadata and final query status.
#' @section Longer queries:
#' Queries wait for completion and collect all pages in R memory.
#' `timeout` covers submission, polling and fetching. A timeout or sign-out
#' doesn't cancel a submitted query.
#'
#' GET requests can refresh and retry once after HTTP 401. SQL submission
#' doesn't retry automatically, so check Salesforce after a submission
#' failure before running the query again.
#' @examples
#' \dontrun{
#' cloud <- oauth_db_salesforce_data_cloud_api(
#'   auth$connection, "https://example.my.salesforce.com"
#' )
#' output$rows <- shiny::renderTable({
#'   cloud$query("SELECT ssot__Id__c FROM ssot__Individual__dlm LIMIT 20")
#' })
#' }
#' @seealso [oauth_db_salesforce_client()], [oauth_db_salesforce_api()].
#'   `vignette("salesforce", package = "shinyOAuthDB")`.
#' @export
oauth_db_salesforce_data_cloud_api <- function(
  authorization,
  instance_url,
  api_version = "64.0",
  dataspace = "default",
  target = NULL,
  required_scopes = c("api", "cdp_query_api"),
  min_valid_for = 60,
  timeout = 300,
  page_size = 10000L,
  ca_bundle = NULL,
  session = shiny::getDefaultReactiveDomain()
) {
  base <- .odb_salesforce_base(instance_url, api_version)
  if (as.numeric(api_version) < 64) {
    .odb_abort("Data Cloud requires api_version 64.0 or later.")
  }
  .odb_string(dataspace, "dataspace")
  .odb_http_options(timeout, ca_bundle)
  if (
    !is.numeric(page_size) ||
      length(page_size) != 1L ||
      is.na(page_size) ||
      !is.finite(page_size) ||
      page_size < 1 ||
      page_size > .Machine$integer.max ||
      page_size != floor(page_size)
  ) {
    .odb_abort("page_size must be a positive integer.")
  }
  provider <- .odb_http_provider(
    authorization,
    target,
    required_scopes,
    min_valid_for,
    session
  )
  .odb_salesforce_data_cloud_api$new(
    provider,
    base,
    dataspace,
    timeout,
    as.integer(page_size),
    ca_bundle
  )
}

.odb_salesforce_data_cloud_api <- R6::R6Class(
  "OAuthSalesforceDataCloudAPI",
  cloneable = FALSE,
  public = list(
    initialize = function(
      provider,
      base,
      dataspace,
      timeout,
      page_size,
      ca_bundle
    ) {
      private$provider <- provider
      private$base <- base
      private$dataspace <- dataspace
      private$timeout <- timeout
      private$page_size <- page_size
      private$ca_bundle <- ca_bundle
    },
    query = function(sql, parameters = list(), raw = FALSE) {
      .odb_string(sql, "sql")
      .odb_flag(raw, "raw")
      parameters <- .odb_salesforce_parameters(parameters)
      body <- list(
        sql = sql,
        rowLimit = private$page_size,
        adaptiveTimeout = 10L
      )
      if (length(parameters)) {
        body$sqlParameters <- parameters
      }
      deadline <- .odb_http_time() + private$timeout
      token <- private$provider()
      result <- private$request(
        token,
        "",
        deadline,
        body = body,
        method = "POST"
      )
      if (!.odb_salesforce_object(result)) {
        .odb_salesforce_invalid()
      }
      metadata <- .odb_salesforce_metadata(result$metadata)
      rows <- .odb_salesforce_rows(result, metadata)
      pages <- list(rows)
      count <- length(rows)
      status <- .odb_salesforce_status(result$status)
      id <- .odb_salesforce_query_id(status$queryId)
      while (!.odb_salesforce_finished(status)) {
        status <- .odb_salesforce_status(private$request(
          token,
          paste0("/", id),
          deadline,
          query = list(waitTimeMs = 1000L)
        ))
        if (!identical(.odb_salesforce_query_id(status$queryId), id)) {
          .odb_salesforce_invalid()
        }
        if (!.odb_salesforce_finished(status)) {
          Sys.sleep(min(0.1, .odb_salesforce_remaining(deadline)))
        }
      }
      total <- .odb_salesforce_count(status$rowCount)
      if (total < count) {
        .odb_salesforce_invalid()
      }
      while (count < total) {
        page <- private$request(
          token,
          paste0("/", id, "/rows"),
          deadline,
          query = list(
            offset = count,
            rowLimit = min(private$page_size, total - count),
            omitSchema = "true"
          )
        )
        if (!.odb_salesforce_object(page)) {
          .odb_salesforce_invalid()
        }
        if (
          !is.null(page$metadata) &&
            !identical(.odb_salesforce_metadata(page$metadata), metadata)
        ) {
          .odb_salesforce_invalid()
        }
        rows <- .odb_salesforce_rows(page, metadata)
        if (!length(rows) || length(rows) > total - count) {
          .odb_salesforce_invalid()
        }
        pages[[length(pages) + 1L]] <- rows
        count <- count + length(rows)
      }
      result$data <- do.call(c, pages)
      if (is.null(result$data)) {
        result$data <- list()
      }
      result$metadata <- metadata
      result$status <- status
      result$returnedRows <- count
      frame <- .odb_salesforce_cloud_frame(result$data, metadata)
      if (raw) result else frame
    },
    print = function(...) {
      cat("<OAuthSalesforceDataCloudAPI>\n")
      invisible(self)
    }
  ),
  private = list(
    provider = NULL,
    base = NULL,
    dataspace = NULL,
    timeout = NULL,
    page_size = NULL,
    ca_bundle = NULL,
    request = function(
      token,
      suffix,
      deadline,
      query = list(),
      body = NULL,
      method = "GET"
    ) {
      .odb_salesforce_request(
        token,
        private$base,
        paste0("ssot/query-sql", suffix),
        deadline,
        private$ca_bundle,
        query = c(list(dataspace = private$dataspace), query),
        body = body,
        method = method,
        exact = TRUE
      )
    }
  )
)

.odb_salesforce_parameters <- function(parameters) {
  if (!.odb_salesforce_array(parameters)) {
    .odb_abort(
      "parameters must be an unnamed list of SQL parameter descriptors."
    )
  }
  seen <- character()
  for (parameter in parameters) {
    if (
      !.odb_salesforce_object(parameter) ||
        !setequal(names(parameter), c("name", "type", "value")) ||
        !.odb_salesforce_string(parameter$name) ||
        !grepl("^[A-Za-z_][A-Za-z0-9_]*$", parameter$name) ||
        !.odb_salesforce_string(parameter$type) ||
        !is.character(parameter$value) ||
        length(parameter$value) != 1L ||
        is.na(parameter$value) ||
        parameter$name %in% seen
    ) {
      .odb_abort(
        "Each SQL parameter needs a unique name, type and value string."
      )
    }
    seen <- c(seen, parameter$name)
  }
  parameters
}

.odb_salesforce_metadata <- function(metadata) {
  if (
    !.odb_salesforce_array(metadata) ||
      !all(vapply(
        metadata,
        function(field) {
          .odb_salesforce_object(field) &&
            .odb_salesforce_string(field$name) &&
            .odb_salesforce_string(field$type)
        },
        logical(1)
      ))
  ) {
    .odb_salesforce_invalid()
  }
  metadata
}

.odb_salesforce_rows <- function(result, metadata) {
  if (!.odb_salesforce_object(result)) {
    .odb_salesforce_invalid()
  }
  count <- .odb_salesforce_count(result$returnedRows)
  rows <- result$data
  if (is.null(rows) && count == 0) {
    rows <- list()
  }
  if (
    !.odb_salesforce_array(rows) ||
      count != length(rows) ||
      !all(vapply(
        rows,
        function(row) {
          .odb_salesforce_array(row) && length(row) == length(metadata)
        },
        logical(1)
      ))
  ) {
    .odb_salesforce_invalid()
  }
  .odb_salesforce_cloud_frame(rows, metadata)
  rows
}

.odb_salesforce_status <- function(status) {
  if (
    !.odb_salesforce_object(status) ||
      !.odb_salesforce_string(status$queryId) ||
      !.odb_salesforce_string(status$completionStatus)
  ) {
    .odb_salesforce_invalid()
  }
  if (
    !status$completionStatus %in%
      c("Running", "ResultsProduced", "Finished", "Unspecified")
  ) {
    .odb_abort(
      "The Salesforce Data Cloud query did not complete successfully.",
      "query_failed"
    )
  }
  .odb_salesforce_count(status$rowCount)
  if (!is.null(status$progress)) {
    if (
      length(status$progress) != 1L ||
        !is.numeric(status$progress) && !is.character(status$progress)
    ) {
      .odb_salesforce_invalid()
    }
    progress <- suppressWarnings(as.numeric(status$progress))
    if (
      length(progress) != 1L ||
        !is.finite(progress) ||
        progress < 0 ||
        progress > 1
    ) {
      .odb_salesforce_invalid()
    }
  }
  status
}

.odb_salesforce_finished <- function(status) {
  identical(status$completionStatus, "Finished") ||
    (!is.null(status$progress) && as.numeric(status$progress) == 1)
}

.odb_salesforce_query_id <- function(id) {
  decoded <- utils::URLdecode(id)
  if (
    !.odb_salesforce_string(decoded) ||
      decoded %in% c(".", "..") ||
      grepl("[[:cntrl:][:space:]]", decoded)
  ) {
    .odb_salesforce_invalid()
  }
  utils::URLencode(decoded, reserved = TRUE, repeated = TRUE)
}

.odb_salesforce_cloud_frame <- function(rows, metadata) {
  columns <- lapply(seq_along(metadata), function(i) {
    values <- lapply(rows, function(row) row[[i]])
    type <- tolower(metadata[[i]]$type)
    if (
      !type %in%
        c(
          "bool",
          "boolean",
          "smallint",
          "integer",
          "int",
          "float",
          "real",
          "double",
          "double precision",
          "bigint",
          "numeric",
          "decimal",
          "char",
          "varchar",
          "text",
          "date",
          "time",
          "timestamp",
          "timestamptz"
        )
    ) {
      return(values)
    }
    if (type %in% c("bool", "boolean")) {
      if (
        !all(vapply(
          values,
          function(x) is.null(x) || is.logical(x) && length(x) == 1L,
          logical(1)
        ))
      ) {
        .odb_salesforce_invalid()
      }
      return(vapply(values, function(x) if (is.null(x)) NA else x, logical(1)))
    }
    if (
      !all(vapply(
        values,
        function(x) is.null(x) || is.character(x) && length(x) == 1L,
        logical(1)
      ))
    ) {
      .odb_salesforce_invalid()
    }
    text <- vapply(values, function(x) if (is.null(x)) NA_character_ else x, "")
    if (
      type %in%
        c(
          "smallint",
          "integer",
          "int",
          "float",
          "real",
          "double",
          "double precision",
          "bigint",
          "numeric",
          "decimal"
        )
    ) {
      valid <- is.na(text) |
        grepl("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$", text)
      if (!all(valid)) {
        .odb_salesforce_invalid()
      }
      if (
        type %in%
          c("smallint", "integer", "int", "bigint") &&
          any(!is.na(text) & !grepl("^-?(0|[1-9][0-9]*)$", text))
      ) {
        .odb_salesforce_invalid()
      }
      if (type %in% c("bigint", "numeric", "decimal")) {
        return(text)
      }
      numbers <- as.numeric(text)
      if (any(!is.na(text) & !is.finite(numbers))) {
        .odb_salesforce_invalid()
      }
      if (type %in% c("smallint", "integer", "int")) {
        bound <- if (type == "smallint") 32768 else 2147483648
        if (any(numbers < -bound | numbers >= bound, na.rm = TRUE)) {
          .odb_salesforce_invalid()
        }
      }
      return(numbers)
    }
    text
  })
  names(columns) <- vapply(metadata, `[[`, "", "name")
  structure(columns, class = "data.frame", row.names = seq_along(rows))
}
