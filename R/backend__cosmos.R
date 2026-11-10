#' Set up Microsoft sign-in for Azure Cosmos DB
#'
#' Create a Microsoft Entra client for a Shiny app that reads Azure Cosmos DB
#' for NoSQL with each visitor's account. Pass it to shinyOAuth's UI and
#' server modules, then use [oauth_db_cosmos_api()] inside `server()`.
#'
#' @inheritParams oauth_db_microsoft_client
#' @param resource Cosmos DB token audience, default
#'   `"https://cosmos.azure.com"`. Change this with `provider` for another
#'   Azure cloud or an account-specific audience accepted by your deployment.
#' @param scopes OAuth consent scopes, replacing the defaults.
#' @param token_targets Named token targets, replacing the Cosmos DB default.
#' @param token_target_default Default token target name.
#' @return A shinyOAuth `OAuthClient`. Create it outside `server()`.
#' @details
#' Use your own Microsoft Entra Web application registration with the exact
#' redirect URI. The preset requests the resource's `.default` scope and
#' keeps its token in the `"cosmos"` target. `.default` is a consent marker,
#' not an operation permission checked by the database helper.
#'
#' Cosmos DB doesn't publish a delegated permission in the app-registration
#' permission picker. Validate that your tenant and registration permit a
#' user token for this resource before deploying. Sign-in configuration and
#' Cosmos DB data-plane role assignments are separate requirements.
#' The preset doesn't use Azure CLI, managed identity or account keys.
#' @seealso [oauth_db_cosmos_api()]. `vignette("cosmos", package =
#'   "shinyOAuthDB")` has setup steps and a complete app.
#' @export
oauth_db_cosmos_client <- function(
  tenant_id,
  client_id,
  redirect_uri,
  client_secret = NULL,
  ...,
  resource = "https://cosmos.azure.com",
  provider = shinyOAuth::oauth_provider_microsoft(
    tenant = tenant_id,
    id_token_validation = TRUE,
    userinfo_required = FALSE
  ),
  scopes = c(
    "openid",
    "profile",
    "offline_access",
    paste0(resource, "/.default")
  ),
  token_targets = list(
    cosmos = list(
      resource = resource,
      scopes = paste0(resource, "/.default"),
      required_scopes = character()
    )
  ),
  token_target_default = "cosmos"
) {
  resource <- .odb_cosmos_origin(resource)
  .odb_oauth_client(
    provider,
    client_id,
    redirect_uri,
    client_secret,
    scopes = scopes,
    token_targets = token_targets,
    token_target_default = token_target_default,
    ...
  )
}

#' Query Azure Cosmos DB for NoSQL as the signed-in user
#'
#' Read documents with each visitor's Microsoft Entra access token and
#' Cosmos DB data-plane permissions. Queries use the NoSQL HTTPS API;
#' no database driver or Azure SDK is needed.
#'
#' @inheritParams oauth_db_connect
#' @inheritParams oauth_db_cratedb_api
#' @param url Cosmos DB account HTTPS origin, such as
#'   `"https://example.documents.azure.com"`.
#' @param database Database ID.
#' @param container Container ID.
#' @param page_size Maximum items requested per page, or `-1` for the
#'   service default. A page can contain fewer items, including none.
#' @param api_version Cosmos DB REST service version.
#' @param timeout Total seconds allowed for an operation and all its pages.
#' @return A session-bound client with these methods:
#'   \itemize{
#'     \item \code{$query(sql, parameters = list(), partition_key = NULL,
#'       raw = FALSE)} collects all pages and returns a data frame.
#'     \item \code{$query_page(sql, parameters = list(), partition_key = NULL,
#'       continuation = NULL, session_token = NULL)} returns one page as a
#'       list with \code{documents}, \code{continuation},
#'       \code{request_charge} and \code{session_token}.
#'     \item \code{$read(id, partition_key)} reads one document as a named list.
#'   }
#' @details
#' Use [oauth_db_cosmos_client()] for sign-in. Users need Cosmos DB
#' data-plane roles, such as Cosmos DB Built-in Data Reader, scoped to the
#' database or container. Azure subscription roles alone don't grant data
#' access. Other Cosmos DB APIs and account administration aren't supported.
#'
#' Create the client inside `server()`. Each operation stays bound to the
#' authorization that started it and gets a current token for every page.
#' Results arriving after account replacement or sign-out are discarded.
#' Read requests may refresh and retry once after HTTP 401. Throttling and
#' other errors stop the operation; no account key or host credentials are used.
#' @section Queries and partitions:
#' Use named parameters without `@`, such as `list(country = "NL")` for
#' SQL containing `@country`. Values can be JSON scalars, arrays or objects;
#' `NULL` becomes JSON null. Dates and timestamps use ISO strings.
#'
#' With `partition_key = NULL`, queries enable cross-partition execution.
#' Supply a scalar key to select one partition, or an unnamed list of up to
#' three components for a hierarchical key. `list(NULL)` selects a null key.
#' This selects data; it doesn't restrict the visitor's database permissions.
#' Some cross-partition query plans need the vendor SDK's result merging;
#' this client sends the query to the REST gateway without rewriting it.
#' @section Results and pagination:
#' Object projections become columns. Missing and null fields become `NA`
#' in scalar columns; nested or mixed values stay in list columns. Scalar
#' or mixed `SELECT VALUE` results use a `value` list column. Large JSON
#' integers stay as strings. Empty results have no field schema.
#'
#' `raw = TRUE` returns the collected native `documents`, total
#' `request_charge` and last `session_token`, with `continuation = NULL`.
#' A missing request-charge header produces `NA_real_`. `$query_page()`
#' preserves nested documents and nulls. Reuse its continuation and session
#' token only with the same query, parameters, partition and account.
#'
#' Queries are synchronous and collect results in memory. Use `$query_page()`
#' for larger results. Session tokens are carried between pages of one
#' operation, never cached across accounts or independent operations.
#' @examples
#' \dontrun{
#' cosmos <- oauth_db_cosmos_api(
#'   auth$connection, url = "https://example.documents.azure.com",
#'   database = "reporting", container = "orders"
#' )
#' output$rows <- shiny::renderTable({
#'   cosmos$query(
#'     "SELECT c.id, c.total FROM c WHERE c.country = @country",
#'     parameters = list(country = "NL"), partition_key = "NL"
#'   )
#' })
#' }
#' @seealso [oauth_db_cosmos_client()]. `vignette("cosmos", package =
#'   "shinyOAuthDB")` has registration and role setup.
#' @export
oauth_db_cosmos_api <- function(
  authorization,
  url,
  database,
  container,
  target = "cosmos",
  required_scopes = character(),
  min_valid_for = 60,
  timeout = 300,
  page_size = 1000L,
  api_version = "2020-07-15",
  ca_bundle = NULL,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("jsonlite")
  url <- .odb_cosmos_origin(url)
  path <- .odb_http_path(c(
    "dbs",
    .odb_cosmos_id(database, "database"),
    "colls",
    .odb_cosmos_id(container, "container"),
    "docs"
  ))
  .odb_http_options(timeout, ca_bundle)
  if (
    !is.numeric(page_size) ||
      length(page_size) != 1L ||
      !is.finite(page_size) ||
      page_size != floor(page_size) ||
      !page_size %in% -1L && (page_size < 1 || page_size > .Machine$integer.max)
  ) {
    .odb_abort("page_size must be -1 or a positive integer.")
  }
  .odb_string(api_version, "api_version")
  if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", api_version)) {
    .odb_abort("api_version must be a REST service date in YYYY-MM-DD form.")
  }
  provider <- .odb_http_provider(
    authorization,
    target,
    .odb_microsoft_scopes(required_scopes),
    min_valid_for,
    session
  )
  .odb_cosmos_api$new(
    provider,
    paste0(url, "/", path),
    timeout,
    as.integer(page_size),
    api_version,
    ca_bundle
  )
}

.odb_cosmos_api <- R6::R6Class(
  "OAuthCosmosAPI",
  cloneable = FALSE,
  public = list(
    initialize = function(
      provider,
      url,
      timeout,
      page_size,
      version,
      ca_bundle
    ) {
      private$provider <- provider
      private$url <- url
      private$timeout <- timeout
      private$page_size <- page_size
      private$version <- version
      private$ca_bundle <- ca_bundle
    },
    query = function(
      sql,
      parameters = list(),
      partition_key = NULL,
      raw = FALSE
    ) {
      .odb_flag(raw, "raw")
      body <- .odb_cosmos_query(sql, parameters)
      key <- .odb_cosmos_partition(partition_key)
      deadline <- .odb_http_time() + private$timeout
      token <- private$provider()
      pages <- list()
      seen <- character()
      continuation <- session_token <- NULL
      charge <- 0
      repeat {
        page <- private$page(
          token,
          body,
          key,
          continuation,
          session_token,
          deadline
        )
        pages[[length(pages) + 1L]] <- page$documents
        charge <- charge + page$request_charge
        continuation <- page$continuation
        session_token <- page$session_token
        if (is.null(continuation)) {
          break
        }
        if (continuation %in% seen) {
          .odb_cosmos_invalid("Azure Cosmos DB repeated a continuation token.")
        }
        seen <- c(seen, continuation)
      }
      page$documents <- do.call(c, pages)
      if (is.null(page$documents)) {
        page$documents <- list()
      }
      page$request_charge <- charge
      result <- if (raw) page else .odb_cosmos_frame(page$documents)
      token(.check_only = TRUE)
      result
    },
    query_page = function(
      sql,
      parameters = list(),
      partition_key = NULL,
      continuation = NULL,
      session_token = NULL
    ) {
      body <- .odb_cosmos_query(sql, parameters)
      key <- .odb_cosmos_partition(partition_key)
      .odb_cosmos_header(continuation, "continuation")
      .odb_cosmos_header(session_token, "session_token")
      deadline <- .odb_http_time() + private$timeout
      token <- private$provider()
      private$page(
        token,
        body,
        key,
        continuation,
        session_token,
        deadline
      )
    },
    read = function(id, partition_key) {
      id <- .odb_cosmos_id(id, "id")
      key <- .odb_cosmos_partition(partition_key)
      if (is.null(key)) {
        .odb_abort(
          "Supply a partition_key for point reads; use list(NULL) for a null key."
        )
      }
      deadline <- .odb_http_time() + private$timeout
      token <- private$provider()
      req <- httr2::request(paste0(private$url, "/", .odb_http_path(id)))
      req <- httr2::req_headers(req, `x-ms-documentdb-partitionkey` = key)
      resp <- private$request(token, req, deadline)
      result <- .odb_http_json(resp, "Azure Cosmos DB")
      if (!is.list(result) || is.null(names(result))) {
        .odb_cosmos_invalid()
      }
      token(.check_only = TRUE)
      result
    },
    print = function(...) {
      cat("<OAuthCosmosAPI>\n")
      invisible(self)
    }
  ),
  private = list(
    provider = NULL,
    url = NULL,
    timeout = NULL,
    page_size = NULL,
    version = NULL,
    ca_bundle = NULL,
    page = function(token, body, key, continuation, session_token, deadline) {
      req <- httr2::request(private$url)
      req <- httr2::req_body_json(req, body, auto_unbox = TRUE)
      req <- httr2::req_headers(
        req,
        `Content-Type` = "application/query+json",
        `x-ms-documentdb-isquery` = "True",
        `x-ms-max-item-count` = as.character(private$page_size),
        `x-ms-documentdb-query-enablecrosspartition` = if (is.null(key)) {
          "True"
        } else {
          "False"
        },
        `x-ms-documentdb-partitionkey` = key,
        `x-ms-continuation` = continuation,
        `x-ms-session-token` = session_token
      )
      resp <- private$request(token, req, deadline)
      result <- .odb_http_json(resp, "Azure Cosmos DB")
      if (
        !is.list(result) ||
          is.null(names(result)) ||
          !is.list(result$Documents) ||
          !is.null(names(result$Documents)) ||
          !is.numeric(result$`_count`) ||
          length(result$`_count`) != 1L ||
          is.na(result$`_count`) ||
          result$`_count` != length(result$Documents)
      ) {
        .odb_cosmos_invalid()
      }
      continuation <- httr2::resp_header(resp, "x-ms-continuation")
      if (identical(continuation, "")) {
        continuation <- NULL
      }
      session_token <- httr2::resp_header(resp, "x-ms-session-token")
      .odb_cosmos_header(continuation, "continuation", response = TRUE)
      .odb_cosmos_header(session_token, "session token", response = TRUE)
      charge <- httr2::resp_header(resp, "x-ms-request-charge")
      if (!is.null(charge)) {
        if (!grepl("^[0-9]+(\\.[0-9]+)?$", charge)) {
          .odb_cosmos_invalid()
        }
        charge <- suppressWarnings(as.numeric(charge))
        if (!is.finite(charge)) .odb_cosmos_invalid()
      } else {
        charge <- NA_real_
      }
      token(.check_only = TRUE)
      list(
        documents = result$Documents,
        continuation = continuation,
        request_charge = charge,
        session_token = session_token
      )
    },
    request = function(token, req, deadline) {
      remaining <- deadline - .odb_http_time()
      if (remaining <= 0) {
        .odb_abort("Azure Cosmos DB operation timed out.", "timeout")
      }
      req <- httr2::req_headers(
        req,
        `x-ms-version` = private$version,
        Accept = "application/json"
      )
      .odb_http_request(
        token,
        req,
        "Azure Cosmos DB",
        remaining,
        private$ca_bundle,
        retry_401 = TRUE,
        authenticate = function(request, value) {
          request <- httr2::req_headers(
            request,
            `x-ms-date` = .odb_cosmos_date(),
            Authorization = utils::URLencode(
              paste0("type=aad&ver=1.0&sig=", value),
              reserved = TRUE,
              repeated = TRUE
            )
          )
          request
        }
      )
    }
  )
)

.odb_cosmos_invalid <- function(
  message = "Azure Cosmos DB returned an invalid response."
) {
  .odb_abort(message, "invalid_response")
}

.odb_cosmos_origin <- function(url) {
  url <- .odb_http_url(url)
  address <- httr2::url_parse(url)
  if (!is.null(address$path) && !address$path %in% c("", "/")) {
    .odb_abort(
      "Supply the Cosmos DB HTTPS origin without a database or API path."
    )
  }
  url
}

.odb_cosmos_id <- function(value, name) {
  .odb_string(value, name)
  .odb_http_path(value)
  if (grepl("[?#]| $", value)) {
    .odb_abort(paste0(name, " contains an invalid resource ID."))
  }
  value
}

.odb_cosmos_header <- function(value, name, response = FALSE) {
  if (is.null(value)) {
    return(invisible(NULL))
  }
  if (
    !is.character(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !nzchar(value) ||
      grepl("[[:cntrl:]]", value)
  ) {
    if (response) {
      .odb_cosmos_invalid()
    }
    .odb_abort(paste0(
      name,
      " must be a nonempty header string without control characters."
    ))
  }
  invisible(NULL)
}

.odb_cosmos_date <- function() {
  now <- as.POSIXlt(Sys.time(), tz = "UTC")
  paste0(
    c("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")[[now$wday + 1L]],
    ", ",
    sprintf("%02d", now$mday),
    " ",
    c(
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec"
    )[[now$mon + 1L]],
    sprintf(
      " %04d %02d:%02d:%02d GMT",
      now$year + 1900L,
      now$hour,
      now$min,
      as.integer(now$sec)
    )
  )
}

.odb_cosmos_value <- function(value) {
  if (is.null(value)) {
    return(NULL)
  }
  if (inherits(value, c("Date", "POSIXct"))) {
    if (length(value) != 1L || !is.finite(as.numeric(value))) {
      .odb_abort("Date and timestamp parameters must be scalar and finite.")
    }
    return(
      if (inherits(value, "Date")) {
        format(value, "%Y-%m-%d")
      } else {
        format(value, "%Y-%m-%dT%H:%M:%OS6Z", tz = "UTC")
      }
    )
  }
  if (is.object(value) || !is.null(dim(value))) {
    .odb_abort("Unsupported Cosmos DB parameter class or dimensions.")
  }
  if (is.list(value)) {
    if (!is.null(names(value))) {
      .odb_named_args(value, "Object parameter fields")
    }
    return(lapply(value, .odb_cosmos_value))
  }
  if (
    !is.character(value) &&
      !is.logical(value) &&
      !is.numeric(value) ||
      is.complex(value) ||
      anyNA(value) ||
      is.numeric(value) && !all(is.finite(value))
  ) {
    .odb_abort(
      "Cosmos DB parameters must be finite JSON values; use NULL for JSON null."
    )
  }
  if (length(value) != 1L) {
    return(lapply(unname(as.list(value)), .odb_cosmos_value))
  }
  unname(value)
}

.odb_cosmos_query <- function(sql, parameters) {
  .odb_string(sql, "sql")
  if (!is.list(parameters)) {
    .odb_abort("parameters must be a named list.")
  }
  .odb_named_args(parameters, "parameters")
  if (
    length(parameters) &&
      !all(grepl("^[A-Za-z_][A-Za-z0-9_]*$", names(parameters)))
  ) {
    .odb_abort("Parameter names must be identifiers without the @ prefix.")
  }
  list(
    query = sql,
    parameters = unname(lapply(names(parameters), function(name) {
      list(
        name = paste0("@", name),
        value = .odb_cosmos_value(parameters[[name]])
      )
    }))
  )
}

.odb_cosmos_partition <- function(key) {
  if (is.null(key)) {
    return(NULL)
  }
  if (!is.list(key)) {
    key <- list(key)
  }
  if (!is.null(names(key)) || !length(key) || length(key) > 3L) {
    .odb_abort(
      "partition_key must contain one to three unnamed scalar components."
    )
  }
  values <- lapply(key, function(value) {
    if (
      !is.null(value) &&
        (!is.atomic(value) ||
          is.object(value) ||
          !is.null(dim(value)) ||
          length(value) != 1L)
    ) {
      .odb_abort("Partition key components must be JSON scalars or NULL.")
    }
    .odb_cosmos_value(value)
  })
  as.character(jsonlite::toJSON(
    values,
    auto_unbox = TRUE,
    null = "null",
    digits = NA
  ))
}

.odb_cosmos_frame <- function(documents) {
  objects <- vapply(
    documents,
    function(x) is.list(x) && !is.null(names(x)),
    logical(1)
  )
  if (length(documents) && !all(objects)) {
    columns <- list(value = documents)
  } else {
    fields <- unique(unlist(lapply(documents, names), use.names = FALSE))
    columns <- lapply(fields, function(field) {
      values <- lapply(documents, function(document) document[[field]])
      present <- Filter(Negate(is.null), values)
      if (!length(present)) {
        return(rep(NA, length(values)))
      }
      scalar <- function(x) is.atomic(x) && length(x) == 1L && !is.object(x)
      if (!all(vapply(present, scalar, logical(1)))) {
        return(values)
      }
      types <- unique(vapply(present, typeof, ""))
      if (all(types %in% c("integer", "double"))) {
        return(vapply(
          values,
          function(x) if (is.null(x)) NA_real_ else as.numeric(x),
          0
        ))
      }
      if (length(types) != 1L || !types %in% c("character", "logical")) {
        return(values)
      }
      missing <- if (types == "character") NA_character_ else NA
      vapply(values, function(x) if (is.null(x)) missing else x, missing)
    })
    names(columns) <- if (is.null(fields)) character() else fields
  }
  structure(columns, class = "data.frame", row.names = seq_along(documents))
}
