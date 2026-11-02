#' Query BigQuery as the signed-in user
#'
#' Run GoogleSQL and browse datasets with the visitor's Google account.
#' Queries return data frames for use in your Shiny app.
#'
#' @inheritParams oauth_db_connect
#' @param project Google Cloud project in which to run and bill queries.
#' @param dataset Default dataset for unqualified table names, or `NULL`.
#' @param location Dataset location, such as `"EU"` or `"us-central1"`.
#'   `NULL` lets BigQuery choose it.
#' @param timeout Maximum seconds to submit, poll, and fetch an operation.
#' @param page_size Maximum number of rows requested per result page.
#' @return An R6 client with these methods:
#'   \itemize{
#'     \item \code{$query(sql, parameters = NULL, parameter_types = NULL,
#'       maximum_bytes_billed = NULL, use_query_cache = TRUE, raw = FALSE)}
#'       runs GoogleSQL and returns a data frame.
#'     \item \code{$datasets()} lists dataset IDs in the project.
#'     \item \code{$tables(dataset)} lists table IDs. If omitted,
#'       \code{dataset} uses the client's default.
#'   }
#' @details
#' Create the client inside `server()` and call its methods inside render or
#' reactive expressions. Use [oauth_db_bigquery_client()] for Google sign-in.
#' Users need permission to create query jobs in `project` and read the data.
#' The client uses BigQuery's REST API; bigrquery and ODBC aren't required.
#' @section Query parameters:
#' Supply named R values in `parameters`, such as `list(country = "NL")`
#' for SQL containing `@country`. Supported values include character,
#' logical, integer, numeric, `Date`, and `POSIXct`.
#'
#' Vectors become ARRAY parameters. Use a named character vector of
#' `parameter_types` to override the scalar element type or type a
#' `NULL` value. Use `"ARRAY<INT64>"` for a one-element array.
#' @section Query options:
#' Set `maximum_bytes_billed` to limit the bytes a query may bill.
#' Set `use_query_cache = FALSE` to disable cached query results.
#' @section Result types:
#' INT64 and decimal columns remain strings to preserve precision.
#' DATE becomes `Date`, TIMESTAMP becomes UTC `POSIXct`, and nested or
#' repeated fields become list columns. BYTES fields keep their REST
#' representation.
#'
#' `raw = TRUE` returns an R list with the combined REST response, schema,
#' and job reference. DML may return a data frame with no columns; use the
#' raw result to inspect `numDmlAffectedRows`.
#' @section Longer queries:
#' Queries run synchronously and collect their results in R memory.
#' A timeout or sign-out stops fetching results but doesn't cancel a
#' submitted BigQuery job.
#'
#' Each request obtains a current token for the authorization that started
#' the operation. A 401 response triggers one refresh attempt. Other errors
#' stop the operation without resubmitting SQL.
#' @examples
#' \dontrun{
#' bigquery <- oauth_db_bigquery_api(
#'   auth$connection, project = "billing-project", location = "EU"
#' )
#' output$rows <- shiny::renderTable({
#'   bigquery$query(
#'     "SELECT * FROM reporting.Orders WHERE country = @country LIMIT 20",
#'     parameters = list(country = "NL")
#'   )
#' })
#' }
#' @seealso [oauth_db_bigquery_client()].
#'   `vignette("bigquery", package = "shinyOAuthDB")` has sign-in setup
#'   and a complete app.
#' @family platform API clients
#' @export
oauth_db_bigquery_api <- function(
  authorization, project, dataset = NULL, location = NULL,
  target = NULL, required_scopes = character(), min_valid_for = 60,
  timeout = 300, page_size = 10000L,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_string(project, "project")
  .odb_string(dataset, "dataset", optional = TRUE)
  .odb_string(location, "location", optional = TRUE)
  .odb_seconds(timeout, "timeout")
  if (timeout == 0) .odb_abort("timeout must be positive.")
  if (!is.numeric(page_size) || length(page_size) != 1L || !is.finite(page_size) ||
      page_size < 1 || page_size > .Machine$integer.max || page_size != floor(page_size)) {
    .odb_abort("page_size must be a positive integer.")
  }
  provider <- .odb_bind(authorization, identity, target = target,
    required_scopes = required_scopes, cache_key = function(token) { token(); NULL },
    min_valid_for = min_valid_for, session = session)
  .odb_bigquery_api$new(provider, project, dataset, location, timeout, as.integer(page_size))
}

#' Set up Google sign-in for BigQuery
#'
#' Create a sign-in client for a Shiny app that queries BigQuery.
#' Pass it to shinyOAuth's UI and server modules, then query with
#' [oauth_db_bigquery_api()].
#'
#' @inheritParams oauth_db_microsoft_client
#' @param client_secret Client secret from a Google Web OAuth registration.
#' @return A shinyOAuth `OAuthClient`. Create it outside `server()`.
#' @details
#' Register a Web OAuth client in Google Cloud. Users need access to the
#' query project and datasets.
#' @examples
#' \dontrun{
#' client <- oauth_db_bigquery_client(
#'   client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
#'   client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
#'   redirect_uri = "http://localhost:8100"
#' )
#' }
#' @seealso [oauth_db_bigquery_api()].
#'   `vignette("bigquery", package = "shinyOAuthDB")` has sign-in setup
#'   and a complete app.
#' @family sign-in configuration
#' @export
oauth_db_bigquery_client <- function(
  client_id, redirect_uri, client_secret, ...,
  provider = shinyOAuth::oauth_provider_google(),
  scopes = c("openid", "profile", "email", "https://www.googleapis.com/auth/bigquery")
) {
  .odb_oauth_client(provider, client_id, redirect_uri, client_secret, scopes, ...)
}

.odb_bigquery_api <- R6::R6Class("OAuthBigQueryAPI", cloneable = FALSE,
  public = list(
    initialize = function(provider, project, dataset, location, timeout, page_size) {
      private$provider <- provider
      private$project <- project
      private$dataset <- dataset
      private$location <- location
      private$timeout <- timeout
      private$page_size <- page_size
    },
    query = function(sql, parameters = NULL, parameter_types = NULL,
                     maximum_bytes_billed = NULL, use_query_cache = TRUE, raw = FALSE) {
      .odb_string(sql, "sql")
      .odb_flag(raw, "raw")
      .odb_flag(use_query_cache, "use_query_cache")
      params <- .odb_bigquery_parameters(parameters, parameter_types)
      body <- list(query = sql, useLegacySql = FALSE, useQueryCache = use_query_cache,
        maxResults = private$page_size, timeoutMs = 10000L,
        jobCreationMode = "JOB_CREATION_REQUIRED",
        requestId = .odb_bigquery_request_id())
      if (!is.null(private$dataset)) {
        body$defaultDataset <- list(projectId = private$project, datasetId = private$dataset)
      }
      if (!is.null(private$location)) body$location <- private$location
      if (length(params)) {
        body$parameterMode <- "NAMED"
        body$queryParameters <- params
      }
      if (!is.null(maximum_bytes_billed)) {
        value <- as.character(maximum_bytes_billed)
        if (length(value) != 1L || is.na(value) || !grepl("^[0-9]+$", value)) {
          .odb_abort("maximum_bytes_billed must be a non-negative decimal integer string.")
        }
        body$maximumBytesBilled <- value
      }
      token <- private$provider()
      deadline <- .odb_bigquery_time() + private$timeout
      path <- c("projects", private$project, "queries")
      result <- .odb_bigquery_request(token, "POST", path, deadline, body = body)
      job <- result$jobReference
      .odb_bigquery_job(job, private$project)
      location <- if (!is.null(job$location)) job$location else private$location
      pages <- list()
      schema <- result$schema
      seen <- character()
      has_errors <- FALSE
      repeat {
        has_errors <- has_errors || length(result$errors) > 0L
        if (!is.logical(result$jobComplete) || length(result$jobComplete) != 1L ||
            is.na(result$jobComplete)) .odb_abort("BigQuery omitted jobComplete.", "invalid_response")
        if (isTRUE(result$jobComplete)) {
          if (!is.null(result$schema)) schema <- result$schema
          if (length(result$rows)) pages[[length(pages) + 1L]] <- result$rows
          page <- result$pageToken
          if (is.null(page) || identical(page, "")) break
          .odb_string(page, "BigQuery page token")
          if (page %in% seen) .odb_abort("BigQuery repeated a page token.", "invalid_response")
          seen <- c(seen, page)
        } else {
          page <- NULL
          Sys.sleep(min(0.1, max(0, deadline - .odb_bigquery_time())))
        }
        .odb_bigquery_job(job, private$project)
        query <- list(maxResults = private$page_size, timeoutMs = 10000L)
        if (!is.null(location)) query$location <- location
        if (!is.null(page)) query$pageToken <- page
        result <- .odb_bigquery_request(token, "GET", c(path, job$jobId), deadline, query = query)
      }
      # The API's errors array also contains warnings; only errorResult is fatal.
      if (has_errors) {
        .odb_bigquery_job(job, private$project)
        query <- if (is.null(location)) list() else list(location = location)
        details <- .odb_bigquery_request(token, "GET",
          c("projects", private$project, "jobs", job$jobId), deadline, query = query)
        if (!is.null(details$status$errorResult)) {
          .odb_abort("The BigQuery job failed. Inspect the job in Google Cloud.",
            "query_failed", job = job)
        }
      }
      rows <- if (length(pages)) unlist(pages, recursive = FALSE, use.names = FALSE) else list()
      result$rows <- rows
      result$schema <- schema
      result$jobReference <- job
      result$pageToken <- NULL
      if (raw) result else .odb_bigquery_frame(rows, schema)
    },
    datasets = function() {
      values <- private$list_items(c("projects", private$project, "datasets"), "datasets")
      vapply(values, function(x) x$datasetReference$datasetId, "")
    },
    tables = function(dataset = private$dataset) {
      .odb_string(dataset, "dataset")
      values <- private$list_items(c("projects", private$project, "datasets", dataset, "tables"), "tables")
      vapply(values, function(x) x$tableReference$tableId, "")
    },
    print = function(...) {
      cat("<OAuthBigQueryAPI>\n")
      invisible(self)
    }
  ),
  private = list(
    provider = NULL, project = NULL, dataset = NULL, location = NULL,
    timeout = NULL, page_size = NULL,
    list_items = function(path, field) {
      token <- private$provider()
      deadline <- .odb_bigquery_time() + private$timeout
      pages <- list()
      seen <- character()
      query <- list(maxResults = private$page_size)
      repeat {
        result <- .odb_bigquery_request(token, "GET", path, deadline, query = query)
        if (length(result[[field]])) pages[[length(pages) + 1L]] <- result[[field]]
        page <- result$nextPageToken
        if (is.null(page) || identical(page, "")) {
          return(if (length(pages)) unlist(pages, recursive = FALSE, use.names = FALSE) else list())
        }
        .odb_string(page, "BigQuery page token")
        if (page %in% seen) .odb_abort("BigQuery repeated a page token.", "invalid_response")
        seen <- c(seen, page)
        query$pageToken <- page
      }
    }
  )
)

.odb_bigquery_time <- function() unname(proc.time()[["elapsed"]])

.odb_bigquery_request_id <- function() paste(format(openssl::rand_bytes(16)), collapse = "")

.odb_bigquery_job <- function(job, project) {
  if (!is.list(job) || !identical(job$projectId, project) ||
      !is.character(job$jobId) || length(job$jobId) != 1L ||
      is.na(job$jobId) || !nzchar(job$jobId)) {
    .odb_abort("BigQuery returned an invalid job reference.", "invalid_response")
  }
}

.odb_bigquery_request <- function(token, method, path, deadline, body = NULL, query = list()) {
  started <- .odb_bigquery_time()
  remaining <- deadline - started
  if (remaining <= 0) .odb_abort("BigQuery operation timed out; the remote job may still be running.", "timeout")
  url <- paste0("https://bigquery.googleapis.com/bigquery/v2/",
    paste(vapply(path, utils::URLencode, "", reserved = TRUE), collapse = "/"))
  req <- httr2::request(url)
  req <- httr2::req_method(req, method)
  req <- httr2::req_options(req, followlocation = FALSE)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  if (length(query)) req <- do.call(httr2::req_url_query, c(list(req), query))
  if (!is.null(body)) req <- httr2::req_body_json(req, body, auto_unbox = TRUE)
  perform <- function(value) {
    force(value)
    remaining <- deadline - .odb_bigquery_time()
    if (remaining <= 0) .odb_abort("BigQuery operation timed out; the remote job may still be running.", "timeout")
    request <- httr2::req_timeout(req, min(remaining, 30))
    httr2::req_perform(httr2::req_auth_bearer_token(request, value))
  }
  resp <- perform(token())
  if (httr2::resp_status(resp) == 401L) {
    if (deadline <= .odb_bigquery_time()) .odb_abort("BigQuery operation timed out.", "timeout")
    refreshed <- token(force_refresh = TRUE)
    if (method == "POST" && .odb_bigquery_time() - started >= 900) {
      .odb_abort("BigQuery submission retry timed out; inspect the job in Google Cloud.", "timeout")
    }
    resp <- perform(refreshed)
  }
  # Discard a response if the selected grant changed while its request ran.
  token(.check_only = TRUE)
  if (deadline <= .odb_bigquery_time()) .odb_abort("BigQuery operation timed out; the remote job may still be running.", "timeout")
  status <- httr2::resp_status(resp)
  if (status < 200L || status >= 300L) {
    .odb_abort(paste0("BigQuery request failed (HTTP ", status,
      "). Check the Google permissions, project, location, and job in Google Cloud."),
      "request_failed", status = status)
  }
  result <- httr2::resp_body_json(resp, simplifyVector = FALSE)
  if (!is.list(result)) .odb_abort("BigQuery returned an invalid JSON response.", "invalid_response")
  result
}

.odb_bigquery_parameters <- function(parameters, types) {
  if (is.null(parameters)) parameters <- list()
  if (!is.list(parameters)) .odb_abort("parameters must be a named list of R values.")
  .odb_named_args(parameters, "parameters")
  if (is.null(types)) types <- character()
  if (!is.character(types) || anyNA(types) || length(types) && (
      is.null(names(types)) || any(!nzchar(names(types))) || anyDuplicated(names(types)) ||
      !all(names(types) %in% names(parameters)))) {
    .odb_abort("parameter_types must name entries in parameters.")
  }
  lapply(names(parameters), function(name) {
    value <- parameters[[name]]
    type <- if (name %in% names(types)) toupper(types[[name]]) else {
      if (inherits(value, "Date")) "DATE"
      else if (inherits(value, "POSIXct")) "TIMESTAMP"
      else if (is.character(value)) "STRING"
      else if (is.logical(value)) "BOOL"
      else if (is.integer(value)) "INT64"
      else if (is.double(value) && !is.object(value)) "FLOAT64"
      else .odb_abort(paste0("Supply parameter_types for parameter ", name, "."))
    }
    forced_array <- grepl("^ARRAY<[^<>]+>$", type)
    if (forced_array) type <- substr(type, 7L, nchar(type) - 1L)
    if (!type %in% c("STRING", "BOOL", "BOOLEAN", "INT64", "INTEGER", "FLOAT64", "FLOAT",
                    "NUMERIC", "BIGNUMERIC", "DATE", "DATETIME", "TIME", "TIMESTAMP", "BYTES", "GEOGRAPHY", "JSON")) {
      .odb_abort("Unsupported BigQuery parameter type.")
    }
    if (!is.null(value) && (!is.atomic(value) || !is.null(dim(value)) || is.factor(value))) {
      .odb_abort("Each parameter must be a scalar or vector of supported R values.")
    }
    encode <- function(x) {
      if (length(x) && is.nan(x) && type %in% c("FLOAT64", "FLOAT")) {
        return(list(value = "NaN"))
      }
      if (length(x) == 0L || is.na(x)) return(list(value = NULL))
      text <- if (inherits(x, "POSIXct")) format(x, "%Y-%m-%d %H:%M:%OS6+00:00", tz = "UTC")
      else if (is.logical(x)) if (x) "true" else "false"
      else if (is.numeric(x) && !inherits(x, "Date")) format(x, scientific = FALSE, trim = TRUE, digits = 17, decimal.mark = ".")
      else as.character(x)
      list(value = text)
    }
    array <- forced_array || !is.null(value) && length(value) != 1L
    parameter_type <- if (array) list(type = "ARRAY", arrayType = list(type = type)) else list(type = type)
    parameter_value <- if (array) {
      list(arrayValues = unname(lapply(seq_along(value), function(i) encode(value[i]))))
    } else encode(value)
    list(name = name, parameterType = parameter_type, parameterValue = parameter_value)
  })
}

.odb_bigquery_frame <- function(rows, schema) {
  fields <- schema$fields
  if (is.null(fields)) {
    if (length(rows)) .odb_abort("BigQuery returned rows without a schema.", "invalid_response")
    return(data.frame())
  }
  if (!all(vapply(rows, function(row) length(row$f) == length(fields), logical(1)))) {
    .odb_abort("BigQuery row width does not match its schema.", "invalid_response")
  }
  columns <- lapply(seq_along(fields), function(i) {
    .odb_bigquery_column(lapply(rows, function(row) row$f[[i]]$v), fields[[i]])
  })
  names(columns) <- vapply(fields, function(field) field$name, "")
  structure(columns, class = "data.frame", row.names = seq_along(rows))
}

.odb_bigquery_column <- function(values, field) {
  type <- toupper(field$type)
  if (identical(field$mode, "REPEATED")) {
    field$mode <- "NULLABLE"
    return(lapply(values, function(x) .odb_bigquery_column(lapply(x, function(cell) cell$v), field)))
  }
  if (type %in% c("RECORD", "STRUCT")) {
    return(lapply(values, function(x) {
      if (is.null(x)) return(NULL)
      fields <- field$fields
      result <- lapply(seq_along(fields), function(i) .odb_bigquery_column(list(x$f[[i]]$v), fields[[i]])[[1L]])
      stats::setNames(result, vapply(fields, function(f) f$name, ""))
    }))
  }
  if (type == "RANGE") return(values)
  text <- vapply(values, function(x) if (is.null(x)) NA_character_ else as.character(x), "")
  switch(type,
    INTEGER = , INT64 = text,
    NUMERIC = , BIGNUMERIC = , DECIMAL = , BIGDECIMAL = text,
    FLOAT = , FLOAT64 = as.numeric(text),
    BOOLEAN = , BOOL = as.logical(toupper(text)),
    DATE = as.Date(text),
    TIMESTAMP = as.POSIXct(as.numeric(text), origin = "1970-01-01", tz = "UTC"),
    text
  )
}
