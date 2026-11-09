#' Query BigQuery as the signed-in user
#'
#' Run BigQuery SQL and browse datasets using each visitor's Google account.
#' Queries run as jobs in your chosen Google Cloud project and return data
#' frames for the Shiny app. Users need permission to run jobs in that
#' project and read the data.
#'
#' @inheritParams oauth_db_connect
#' @param project Google Cloud project in which to run and bill queries.
#' @param dataset Default dataset for unqualified table names, or `NULL`.
#' @param location Dataset location, such as `"EU"` or `"us-central1"`.
#'   `NULL` lets BigQuery choose it.
#' @param timeout Maximum seconds to submit, poll, and fetch an operation.
#' @param page_size Maximum number of rows requested per result page.
#' @return A client object with these methods:
#'   \itemize{
#'     \item \code{$query(sql, parameters = NULL, parameter_types = NULL,
#'       maximum_bytes_billed = NULL, use_query_cache = TRUE, raw = FALSE)}
#'       runs GoogleSQL and returns a data frame.
#'     \item \code{$datasets()} lists dataset IDs in the project.
#'     \item \code{$tables(dataset)} lists table IDs. If omitted,
#'       \code{dataset} uses the client's default.
#'   }
#' @details
#' Create the client inside `server()` and call its methods from render or
#' reactive expressions. Use [oauth_db_bigquery_client()] for Google sign-in.
#' No BigQuery database driver is needed.
#'
#' Set `project` to the Google Cloud project that runs and bills queries.
#' The data can be in another project the user can access. Set `location`
#' to match the datasets you query.
#' @section Query parameters:
#' Use named R values in `parameters`, such as `list(country = "NL")` for
#' SQL containing `@country`. Character, logical, integer, numeric, `Date`
#' and `POSIXct` values are supported; vectors become arrays.
#'
#' Use a named character vector of `parameter_types` to choose the type or
#' type a `NULL` value. Use `"ARRAY<INT64>"` for a one-element integer array.
#' @section Query options:
#' Set `maximum_bytes_billed` to limit the bytes a query may bill.
#' Set `use_query_cache = FALSE` to disable cached query results.
#' @section Result types:
#' INT64 and decimal columns stay as strings to preserve precision. Dates
#' become `Date`, timestamps become UTC `POSIXct`, and nested or repeated
#' fields use list columns. BYTES fields keep their API representation.
#'
#' Use `raw = TRUE` for the combined API response, schema and job reference.
#' For statements that change data, inspect `numDmlAffectedRows` in that
#' result; the data frame can have no columns.
#' @section Longer queries:
#' Queries wait for completion and collect all result pages in R memory.
#' Polling is synchronous: other Shiny sessions in the same R process can
#' wait until the call returns.
#' A timeout or sign-out stops fetching results but doesn't cancel a
#' submitted BigQuery job. Each request uses a current token. HTTP 401 can
#' trigger one refresh attempt; other errors stop the operation without
#' resubmitting SQL.
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
#' @export
oauth_db_bigquery_api <- function(
  authorization,
  project,
  dataset = NULL,
  location = NULL,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  timeout = 300,
  page_size = 10000L,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_string(project, "project")
  .odb_string(dataset, "dataset", optional = TRUE)
  .odb_string(location, "location", optional = TRUE)
  .odb_seconds(timeout, "timeout")
  if (timeout == 0) {
    .odb_abort("timeout must be positive.")
  }
  if (
    !is.numeric(page_size) ||
      length(page_size) != 1L ||
      !is.finite(page_size) ||
      page_size < 1 ||
      page_size > .Machine$integer.max ||
      page_size != floor(page_size)
  ) {
    .odb_abort("page_size must be a positive integer.")
  }
  provider <- .odb_bind(
    authorization,
    identity,
    target = target,
    required_scopes = required_scopes,
    cache_key = function(token) {
      token()
      NULL
    },
    min_valid_for = min_valid_for,
    session = session
  )
  .odb_bigquery_api$new(
    provider,
    project,
    dataset,
    location,
    timeout,
    as.integer(page_size)
  )
}

#' Set up Google sign-in for BigQuery
#'
#' Set up Google sign-in for a Shiny app that queries BigQuery. The client
#' holds your app registration and requested permissions. Pass it to
#' shinyOAuth's UI and server modules, then use [oauth_db_bigquery_api()]
#' to query with each visitor's Google account.
#'
#' @inheritParams oauth_db_microsoft_client
#' @param client_secret Client secret from a Google Web OAuth registration.
#' @return A shinyOAuth `OAuthClient`. Create it outside `server()`.
#' @details
#' Register a Web OAuth client in Google Cloud with your app's exact
#' redirect URI. Create this client outside `server()`; the registration is
#' shared by the app, while each visitor's sign-in stays in their own session.
#' Users need access to the query project and datasets.
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
#' @export
oauth_db_bigquery_client <- function(
  client_id,
  redirect_uri,
  client_secret,
  ...,
  provider = shinyOAuth::oauth_provider_google(),
  scopes = c(
    "openid",
    "profile",
    "email",
    "https://www.googleapis.com/auth/bigquery"
  )
) {
  .odb_oauth_client(
    provider,
    client_id,
    redirect_uri,
    client_secret,
    scopes,
    ...
  )
}

.odb_bigquery_api <- R6::R6Class(
  "OAuthBigQueryAPI",
  cloneable = FALSE,
  public = list(
    initialize = function(
      provider,
      project,
      dataset,
      location,
      timeout,
      page_size
    ) {
      private$provider <- provider
      private$project <- project
      private$dataset <- dataset
      private$location <- location
      private$timeout <- timeout
      private$page_size <- page_size
    },
    query = function(
      sql,
      parameters = NULL,
      parameter_types = NULL,
      maximum_bytes_billed = NULL,
      use_query_cache = TRUE,
      raw = FALSE
    ) {
      .odb_string(sql, "sql")
      .odb_flag(raw, "raw")
      .odb_flag(use_query_cache, "use_query_cache")
      params <- .odb_bigquery_parameters(parameters, parameter_types)
      body <- list(
        query = sql,
        useLegacySql = FALSE,
        useQueryCache = use_query_cache,
        maxResults = private$page_size,
        timeoutMs = 10000L,
        jobCreationMode = "JOB_CREATION_REQUIRED",
        requestId = .odb_bigquery_request_id()
      )
      if (!is.null(private$dataset)) {
        body$defaultDataset <- list(
          projectId = private$project,
          datasetId = private$dataset
        )
      }
      if (!is.null(private$location)) {
        body$location <- private$location
      }
      if (length(params)) {
        body$parameterMode <- "NAMED"
        body$queryParameters <- params
      }
      if (!is.null(maximum_bytes_billed)) {
        value <- as.character(maximum_bytes_billed)
        if (length(value) != 1L || is.na(value) || !grepl("^[0-9]+$", value)) {
          .odb_abort(
            "maximum_bytes_billed must be a non-negative decimal integer string."
          )
        }
        body$maximumBytesBilled <- value
      }
      deadline <- .odb_bigquery_time() + private$timeout
      token <- private$provider()
      path <- c("projects", private$project, "queries")
      result <- .odb_bigquery_request(
        token,
        "POST",
        path,
        deadline,
        body = body
      )
      combined <- result
      job <- result$jobReference
      .odb_bigquery_job(job, private$project)
      location <- if (!is.null(job$location)) job$location else private$location
      pages <- list()
      schema <- result$schema
      seen <- character()
      has_errors <- FALSE
      repeat {
        has_errors <- has_errors || length(result$errors) > 0L
        if (
          !is.logical(result$jobComplete) ||
            length(result$jobComplete) != 1L ||
            is.na(result$jobComplete)
        ) {
          .odb_abort("BigQuery omitted jobComplete.", "invalid_response")
        }
        if (isTRUE(result$jobComplete)) {
          if (!is.null(result$schema)) {
            schema <- result$schema
          }
          if (length(result$rows)) {
            pages[[length(pages) + 1L]] <- result$rows
          }
          page <- result$pageToken
          if (is.null(page) || identical(page, "")) {
            break
          }
          .odb_string(page, "BigQuery page token")
          if (page %in% seen) {
            .odb_abort("BigQuery repeated a page token.", "invalid_response")
          }
          seen <- c(seen, page)
        } else {
          page <- NULL
          Sys.sleep(min(0.1, max(0, deadline - .odb_bigquery_time())))
        }
        .odb_bigquery_job(job, private$project)
        query <- list(maxResults = private$page_size, timeoutMs = 10000L)
        if (!is.null(location)) {
          query$location <- location
        }
        if (!is.null(page)) {
          query$pageToken <- page
        }
        result <- .odb_bigquery_request(
          token,
          "GET",
          c(path, job$jobId),
          deadline,
          query = query
        )
        combined[names(result)] <- result
      }
      # The API's errors array also contains warnings; only errorResult is fatal.
      if (has_errors) {
        .odb_bigquery_job(job, private$project)
        query <- if (is.null(location)) list() else list(location = location)
        details <- .odb_bigquery_request(
          token,
          "GET",
          c("projects", private$project, "jobs", job$jobId),
          deadline,
          query = query
        )
        if (!is.null(details$status$errorResult)) {
          .odb_abort(
            "The BigQuery job failed. Inspect the job in Google Cloud.",
            "query_failed",
            job = job
          )
        }
      }
      rows <- if (length(pages)) {
        unlist(pages, recursive = FALSE, use.names = FALSE)
      } else {
        list()
      }
      combined$rows <- rows
      combined$schema <- schema
      combined$jobReference <- job
      combined$pageToken <- NULL
      if (!is.null(combined$pageRowCount)) {
        combined$pageRowCount <- as.character(length(rows))
      }
      if (raw) combined else .odb_bigquery_frame(rows, schema)
    },
    datasets = function() {
      values <- private$list_items(
        c("projects", private$project, "datasets"),
        "datasets"
      )
      vapply(values, function(x) x$datasetReference$datasetId, "")
    },
    tables = function(dataset = private$dataset) {
      .odb_string(dataset, "dataset")
      values <- private$list_items(
        c("projects", private$project, "datasets", dataset, "tables"),
        "tables"
      )
      vapply(values, function(x) x$tableReference$tableId, "")
    },
    print = function(...) {
      cat("<OAuthBigQueryAPI>\n")
      invisible(self)
    }
  ),
  private = list(
    provider = NULL,
    project = NULL,
    dataset = NULL,
    location = NULL,
    timeout = NULL,
    page_size = NULL,
    list_items = function(path, field) {
      deadline <- .odb_bigquery_time() + private$timeout
      token <- private$provider()
      pages <- list()
      seen <- character()
      query <- list(maxResults = private$page_size)
      repeat {
        result <- .odb_bigquery_request(
          token,
          "GET",
          path,
          deadline,
          query = query
        )
        .odb_bigquery_list_page(
          result,
          field,
          private$project,
          dataset = if (field == "tables") path[[4L]] else NULL
        )
        if (length(result[[field]])) {
          pages[[length(pages) + 1L]] <- result[[field]]
        }
        page <- result$nextPageToken
        if (is.null(page) || identical(page, "")) {
          return(
            if (length(pages)) {
              unlist(pages, recursive = FALSE, use.names = FALSE)
            } else {
              list()
            }
          )
        }
        .odb_string(page, "BigQuery page token")
        if (page %in% seen) {
          .odb_abort("BigQuery repeated a page token.", "invalid_response")
        }
        seen <- c(seen, page)
        query$pageToken <- page
      }
    }
  )
)

.odb_bigquery_time <- function() unname(proc.time()[["elapsed"]])

.odb_bigquery_request_id <- function() {
  paste(format(openssl::rand_bytes(16)), collapse = "")
}

.odb_bigquery_list_page <- function(result, field, project, dataset = NULL) {
  fail <- function() {
    .odb_abort(
      "BigQuery returned invalid dataset or table metadata.",
      "invalid_response"
    )
  }
  string <- function(x) {
    is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
  }
  resource <- if (field == "datasets") "dataset" else "table"
  if (
    !is.list(result) ||
      !identical(result$kind, paste0("bigquery#", resource, "List")) ||
      "error" %in% names(result)
  ) {
    fail()
  }
  if (field == "datasets" && length(result$unreachable)) {
    .odb_abort(
      "BigQuery dataset discovery is incomplete because some locations were unreachable. Retry when those locations are available.",
      "query_failed"
    )
  }
  items <- result[[field]]
  if (field %in% names(result) && (!is.list(items) || !is.null(names(items)))) {
    fail()
  }
  page <- result$nextPageToken
  if (
    !is.null(page) && (!is.character(page) || length(page) != 1L || is.na(page))
  ) {
    fail()
  }
  for (item in items) {
    if (!is.list(item)) {
      fail()
    }
    reference <- item[[paste0(resource, "Reference")]]
    if (
      !is.list(reference) ||
        !identical(reference$projectId, project) ||
        !string(reference$datasetId)
    ) {
      fail()
    }
    if (
      field == "tables" &&
        (!identical(reference$datasetId, dataset) ||
          !string(reference$tableId))
    ) {
      fail()
    }
  }
  invisible(NULL)
}

.odb_bigquery_job <- function(job, project) {
  if (
    !is.list(job) ||
      !identical(job$projectId, project) ||
      !is.character(job$jobId) ||
      length(job$jobId) != 1L ||
      is.na(job$jobId) ||
      !nzchar(job$jobId)
  ) {
    .odb_abort(
      "BigQuery returned an invalid job reference.",
      "invalid_response"
    )
  }
}

.odb_bigquery_request <- function(
  token,
  method,
  path,
  deadline,
  body = NULL,
  query = list()
) {
  started <- .odb_bigquery_time()
  remaining <- deadline - started
  if (remaining <= 0) {
    .odb_abort(
      "BigQuery operation timed out; the remote job may still be running.",
      "timeout"
    )
  }
  url <- paste0(
    "https://bigquery.googleapis.com/bigquery/v2/",
    paste(vapply(path, utils::URLencode, "", reserved = TRUE), collapse = "/")
  )
  req <- httr2::request(url)
  req <- httr2::req_method(req, method)
  req <- httr2::req_options(req, followlocation = FALSE)
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  if (length(query)) {
    req <- do.call(httr2::req_url_query, c(list(req), query))
  }
  if (!is.null(body)) {
    req <- httr2::req_body_json(req, body, auto_unbox = TRUE)
  }
  credentials <- character()
  perform <- function(value) {
    force(value)
    credentials <<- union(credentials, value)
    remaining <- deadline - .odb_bigquery_time()
    if (remaining <= 0) {
      .odb_abort(
        "BigQuery operation timed out; the remote job may still be running.",
        "timeout"
      )
    }
    request <- httr2::req_timeout(req, min(remaining, 30))
    .odb_http_perform(httr2::req_auth_bearer_token(request, value), "BigQuery")
  }
  resp <- perform(token())
  if (httr2::resp_status(resp) == 401L) {
    if (deadline <= .odb_bigquery_time()) {
      .odb_abort("BigQuery operation timed out.", "timeout")
    }
    refreshed <- token(force_refresh = TRUE)
    if (method == "POST" && .odb_bigquery_time() - started >= 900) {
      .odb_abort(
        "BigQuery submission retry timed out; inspect the job in Google Cloud.",
        "timeout"
      )
    }
    resp <- perform(refreshed)
  }
  # Discard a response if the selected grant changed while its request ran.
  token(.check_only = TRUE)
  if (deadline <= .odb_bigquery_time()) {
    .odb_abort(
      "BigQuery operation timed out; the remote job may still be running.",
      "timeout"
    )
  }
  status <- httr2::resp_status(resp)
  if (status < 200L || status >= 300L) {
    diagnostics <- .odb_http_diagnostics(resp, "BigQuery", credentials)
    .odb_abort(
      paste0(
        "BigQuery request failed (HTTP ",
        status,
        "). Check the Google permissions, project, location, and job in Google Cloud."
      ),
      "request_failed",
      status = status,
      service_code = diagnostics$service_code,
      request_id = diagnostics$request_id
    )
  }
  result <- .odb_http_json(resp, "BigQuery")
  if (!is.list(result)) {
    .odb_abort(
      "BigQuery returned an invalid JSON response.",
      "invalid_response"
    )
  }
  result
}

.odb_bigquery_parameters <- function(parameters, types) {
  if (is.null(parameters)) {
    parameters <- list()
  }
  if (!is.list(parameters)) {
    .odb_abort("parameters must be a named list of R values.")
  }
  .odb_named_args(parameters, "parameters")
  if (is.null(types)) {
    types <- character()
  }
  if (
    !is.character(types) ||
      anyNA(types) ||
      length(types) &&
        (is.null(names(types)) ||
          !all(nzchar(names(types))) ||
          anyDuplicated(names(types)) ||
          !all(names(types) %in% names(parameters)))
  ) {
    .odb_abort("parameter_types must name entries in parameters.")
  }
  lapply(names(parameters), function(name) {
    value <- parameters[[name]]
    type <- if (name %in% names(types)) {
      toupper(types[[name]])
    } else {
      if (inherits(value, "Date")) {
        "DATE"
      } else if (inherits(value, "POSIXct")) {
        "TIMESTAMP"
      } else if (is.character(value)) {
        "STRING"
      } else if (is.logical(value)) {
        "BOOL"
      } else if (is.integer(value)) {
        "INT64"
      } else if (is.double(value) && !is.object(value)) {
        "FLOAT64"
      } else {
        .odb_abort(paste0("Supply parameter_types for parameter ", name, "."))
      }
    }
    forced_array <- grepl("^ARRAY<[^<>]+>$", type)
    if (forced_array) {
      type <- substr(type, 7L, nchar(type) - 1L)
    }
    if (
      !type %in%
        c(
          "STRING",
          "BOOL",
          "BOOLEAN",
          "INT64",
          "INTEGER",
          "FLOAT64",
          "FLOAT",
          "NUMERIC",
          "BIGNUMERIC",
          "DATE",
          "DATETIME",
          "TIME",
          "TIMESTAMP",
          "BYTES",
          "GEOGRAPHY",
          "JSON"
        )
    ) {
      .odb_abort("Unsupported BigQuery parameter type.")
    }
    if (
      !is.null(value) &&
        (!is.atomic(value) ||
          is.raw(value) ||
          !is.null(dim(value)) ||
          is.factor(value))
    ) {
      .odb_abort(
        "Each parameter must be a scalar or vector of supported R values."
      )
    }
    encode <- function(x) {
      if (length(x) && is.nan(x) && type %in% c("FLOAT64", "FLOAT")) {
        return(list(value = "NaN"))
      }
      if (length(x) == 0L || is.na(x)) {
        return(list(value = NULL))
      }
      text <- if (inherits(x, "POSIXct")) {
        format(x, "%Y-%m-%d %H:%M:%OS6+00:00", tz = "UTC")
      } else if (is.logical(x)) {
        if (x) "true" else "false"
      } else if (is.numeric(x) && !inherits(x, "Date")) {
        format(
          x,
          scientific = FALSE,
          trim = TRUE,
          digits = 17,
          decimal.mark = "."
        )
      } else {
        as.character(x)
      }
      list(value = text)
    }
    array <- forced_array || !is.null(value) && length(value) != 1L
    parameter_type <- if (array) {
      list(type = "ARRAY", arrayType = list(type = type))
    } else {
      list(type = type)
    }
    parameter_value <- if (array) {
      list(
        arrayValues = unname(lapply(seq_along(value), function(i) {
          encode(value[i])
        }))
      )
    } else {
      encode(value)
    }
    list(
      name = name,
      parameterType = parameter_type,
      parameterValue = parameter_value
    )
  })
}

.odb_bigquery_frame <- function(rows, schema) {
  force(rows)
  force(schema)
  tryCatch(.odb_bigquery_decode_frame(rows, schema), error = function(e) {
    if (inherits(e, "shinyOAuthDB_invalid_response")) {
      stop(e)
    }
    .odb_abort("BigQuery returned invalid rows or schema.", "invalid_response")
  })
}

.odb_bigquery_decode_frame <- function(rows, schema) {
  fields <- schema$fields
  if (is.null(fields)) {
    if (length(rows)) {
      .odb_abort("BigQuery returned rows without a schema.", "invalid_response")
    }
    return(data.frame())
  }
  if (
    !all(vapply(
      rows,
      function(row) length(row$f) == length(fields),
      logical(1)
    ))
  ) {
    .odb_abort(
      "BigQuery row width does not match its schema.",
      "invalid_response"
    )
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
    return(lapply(values, function(x) {
      .odb_bigquery_column(lapply(x, function(cell) cell$v), field)
    }))
  }
  if (type %in% c("RECORD", "STRUCT")) {
    return(lapply(values, function(x) {
      if (is.null(x)) {
        return(NULL)
      }
      fields <- field$fields
      result <- lapply(seq_along(fields), function(i) {
        .odb_bigquery_column(list(x$f[[i]]$v), fields[[i]])[[1L]]
      })
      stats::setNames(result, vapply(fields, function(f) f$name, ""))
    }))
  }
  if (type == "RANGE") {
    return(values)
  }
  text <- vapply(
    values,
    function(x) {
      if (is.null(x)) {
        return(NA_character_)
      }
      if (!is.atomic(x) || length(x) != 1L) {
        .odb_abort(
          "BigQuery returned a non-scalar column value.",
          "invalid_response"
        )
      }
      as.character(x)
    },
    ""
  )
  if (type %in% c("BOOLEAN", "BOOL")) {
    if (any(!is.na(text) & !tolower(text) %in% c("true", "false"))) {
      .odb_abort("BigQuery returned an invalid Boolean.", "invalid_response")
    }
    return(as.logical(toupper(text)))
  }
  if (type %in% c("FLOAT", "FLOAT64", "TIMESTAMP")) {
    value <- suppressWarnings(as.numeric(text))
    decimal <- "^[+-]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)([eE][+-]?[0-9]+)?$"
    valid <- is.na(text) | (grepl(decimal, text) & is.finite(value))
    if (type != "TIMESTAMP") {
      valid <- valid |
        tolower(text) %in%
          c("nan", "inf", "+inf", "-inf", "infinity", "+infinity", "-infinity")
    }
    if (!all(valid)) {
      .odb_abort(
        "BigQuery returned an invalid number or timestamp.",
        "invalid_response"
      )
    }
    if (type == "TIMESTAMP") {
      return(as.POSIXct(value, origin = "1970-01-01", tz = "UTC"))
    }
    return(value)
  }
  switch(
    type,
    INTEGER = ,
    INT64 = text,
    NUMERIC = ,
    BIGNUMERIC = ,
    DECIMAL = ,
    BIGDECIMAL = text,
    DATE = .odb_http_date(text, "BigQuery"),
    text
  )
}
