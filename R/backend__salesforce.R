#' Set up Salesforce sign-in
#'
#' Set up Salesforce sign-in for a Shiny app that queries CRM records,
#' Data Cloud or both. Pass the client to shinyOAuth's UI and server modules.
#' Visitors sign in with their own Salesforce account and keep their
#' existing data permissions.
#'
#' @inheritParams oauth_db_microsoft_client
#' @param login_url Salesforce login origin: your My Domain URL,
#'   `"https://login.salesforce.com"`, or `"https://test.salesforce.com"`.
#' @param data_cloud Include the `cdp_query_api` consent scope.
#' @param provider Custom shinyOAuth provider, replacing OIDC discovery.
#' @param scopes OAuth scopes, replacing the defaults.
#' @param client_secret Client secret from the Salesforce registration. Pass
#'   `NULL` only with a custom public-client provider matching that registration.
#' @return A shinyOAuth `OAuthClient`. Create it outside `server()`.
#' @details
#' Register an External Client App with the authorization-code flow and
#' PKCE, which protects the sign-in code. Enable JWT-based access tokens
#' for named users; this format works with shinyOAuth's token validation.
#' The default client discovers sign-in settings from `login_url` over HTTPS.
#'
#' shinyOAuth manages token renewal. If Salesforce omits the token's expiry,
#' shinyOAuth warns and uses its configured fallback lifetime. Your app's
#' registration and users still need the relevant API and data permissions.
#' @seealso [oauth_db_salesforce_api()], [oauth_db_salesforce_data_cloud_api()].
#'   `vignette("salesforce", package = "shinyOAuthDB")` has registration steps
#'   and a complete app.
#' @export
oauth_db_salesforce_client <- function(
  client_id,
  redirect_uri,
  client_secret,
  ...,
  login_url = "https://login.salesforce.com",
  data_cloud = FALSE,
  provider = shinyOAuth::oauth_provider_oidc_discover(
    .odb_salesforce_origin(login_url)
  ),
  scopes = c(
    "openid",
    "profile",
    "api",
    "refresh_token",
    if (data_cloud) "cdp_query_api"
  )
) {
  if (missing(scopes)) {
    .odb_flag(data_cloud, "data_cloud")
  }
  .odb_oauth_client(
    provider,
    client_id,
    redirect_uri,
    client_secret,
    scopes,
    ...
  )
}

#' Query Salesforce CRM as the signed-in user
#'
#' Read Salesforce CRM records using the visitor's object, field and record
#' permissions. CRM objects, such as accounts, are queried with Salesforce's
#' query language, SOQL. Queries return data frames for your Shiny app.
#'
#' @inheritParams oauth_db_connect
#' @inheritParams oauth_db_postgrest_api
#' @param instance_url Trusted HTTPS origin of your Salesforce org, such as
#'   `"https://example.my.salesforce.com"`. Use the org URL, not a Lightning URL.
#' @param api_version Salesforce REST API version without `v`, default `"64.0"`.
#' @param timeout Total seconds allowed for an operation, including polling,
#'   result pages and any permitted refresh retry.
#' @return A client object with these methods:
#'   \itemize{
#'     \item \code{$query(soql, include_deleted = FALSE, raw = FALSE)} fetches
#'       all result pages and returns a data frame. `include_deleted = TRUE`
#'       includes deleted or archived records through QueryAll.
#'       `raw = TRUE` returns combined native records and
#'       `totalSize`, including the count for `SELECT COUNT()`.
#'     \item \code{$objects()} returns the API's object catalog.
#'     \item \code{$describe(object)} returns field definitions and other
#'       object metadata.
#'   }
#' @details
#' Use [oauth_db_salesforce_client()] for sign-in. Create this API client
#' inside `server()` and call its methods from render or reactive expressions.
#' The client gets a current token for each request and discards results
#' after sign-out or account changes. GET requests can refresh and retry
#' once after HTTP 401.
#'
#' Queries fetch all result pages into R memory. `timeout` applies to the
#' whole operation. Relationships and child-query results stay in list
#' columns; ordinary numbers become R numeric values and large integers
#' stay as strings. Empty results have no field metadata; use `$describe()`
#' for field types.
#'
#' Supply SOQL as written. This client doesn't bind SQL parameters or
#' provide a DBI connection. Use `raw = TRUE` for the records and metadata
#' without conversion to a data frame.
#' @examples
#' \dontrun{
#' crm <- oauth_db_salesforce_api(
#'   auth$connection, "https://example.my.salesforce.com"
#' )
#' output$rows <- shiny::renderTable({
#'   crm$query("SELECT Id, Name FROM Account LIMIT 20")
#' })
#' }
#' @seealso [oauth_db_salesforce_client()], [oauth_db_salesforce_data_cloud_api()].
#'   `vignette("salesforce", package = "shinyOAuthDB")`.
#' @export
oauth_db_salesforce_api <- function(
  authorization,
  instance_url,
  api_version = "64.0",
  target = NULL,
  required_scopes = "api",
  min_valid_for = 60,
  timeout = 300,
  ca_bundle = NULL,
  session = shiny::getDefaultReactiveDomain()
) {
  base <- .odb_salesforce_base(instance_url, api_version)
  .odb_http_options(timeout, ca_bundle)
  provider <- .odb_http_provider(
    authorization,
    target,
    required_scopes,
    min_valid_for,
    session
  )
  .odb_salesforce_api$new(provider, base, timeout, ca_bundle)
}

.odb_salesforce_api <- R6::R6Class(
  "OAuthSalesforceAPI",
  cloneable = FALSE,
  public = list(
    initialize = function(provider, base, timeout, ca_bundle) {
      private$provider <- provider
      private$base <- base
      private$timeout <- timeout
      private$ca_bundle <- ca_bundle
    },
    query = function(soql, include_deleted = FALSE, raw = FALSE) {
      .odb_string(soql, "soql")
      .odb_flag(include_deleted, "include_deleted")
      .odb_flag(raw, "raw")
      deadline <- .odb_http_time() + private$timeout
      token <- private$provider()
      result <- private$get(
        token,
        if (include_deleted) "queryAll" else "query",
        deadline,
        list(q = soql)
      )
      first <- result
      pages <- list()
      seen <- character()
      repeat {
        if (
          !is.list(result) ||
            !is.logical(result$done) ||
            length(result$done) != 1L ||
            is.na(result$done) ||
            !.odb_salesforce_array(result$records) ||
            !all(vapply(result$records, .odb_salesforce_object, logical(1))) ||
            .odb_salesforce_count(result$totalSize) !=
              .odb_salesforce_count(first$totalSize)
        ) {
          .odb_salesforce_invalid()
        }
        pages[[length(pages) + 1L]] <- result$records
        if (result$done) {
          break
        }
        next_url <- result$nextRecordsUrl
        prefix <- paste0(httr2::url_parse(private$base)$path, "/query/")
        if (
          !.odb_salesforce_string(next_url) ||
            !startsWith(next_url, prefix) ||
            !grepl(
              "^[A-Za-z0-9_-]+$",
              substring(next_url, nchar(prefix) + 1L)
            ) ||
            next_url %in% seen ||
            !length(result$records)
        ) {
          .odb_salesforce_invalid()
        }
        seen <- c(seen, next_url)
        result <- private$get(
          token,
          substring(next_url, nchar(httr2::url_parse(private$base)$path) + 2L),
          deadline
        )
      }
      records <- do.call(c, pages)
      if (is.null(records)) {
        records <- list()
      }
      if (length(records) && length(records) != first$totalSize) {
        .odb_salesforce_invalid()
      }
      first$records <- records
      first$done <- TRUE
      first$nextRecordsUrl <- NULL
      if (raw) first else .odb_salesforce_records(records)
    },
    objects = function() private$read("sobjects"),
    describe = function(object) {
      .odb_string(object, "object")
      if (!grepl("^[A-Za-z][A-Za-z0-9_]*$", object)) {
        .odb_abort("object must be a Salesforce object API name.")
      }
      private$read(paste0("sobjects/", object, "/describe"))
    },
    print = function(...) {
      cat("<OAuthSalesforceAPI>\n")
      invisible(self)
    }
  ),
  private = list(
    provider = NULL,
    base = NULL,
    timeout = NULL,
    ca_bundle = NULL,
    get = function(token, path, deadline, query = list()) {
      .odb_salesforce_request(
        token,
        private$base,
        path,
        deadline,
        private$ca_bundle,
        query = query
      )
    },
    read = function(path) {
      deadline <- .odb_http_time() + private$timeout
      token <- private$provider()
      result <- private$get(token, path, deadline)
      if (!.odb_salesforce_object(result)) {
        .odb_salesforce_invalid()
      }
      result
    }
  )
)

.odb_salesforce_origin <- function(url) {
  url <- .odb_http_url(url)
  if (!httr2::url_parse(url)$path %in% c("", "/")) {
    .odb_abort("Salesforce URLs must be HTTPS origins without a path.")
  }
  url
}

.odb_salesforce_base <- function(instance_url, api_version) {
  origin <- .odb_salesforce_origin(instance_url)
  .odb_string(api_version, "api_version")
  if (!grepl("^[1-9][0-9]+\\.0$", api_version)) {
    .odb_abort(
      "api_version must be a Salesforce version such as 64.0, without v."
    )
  }
  paste0(origin, "/services/data/v", api_version)
}

.odb_salesforce_string <- function(value) {
  is.character(value) && length(value) == 1L && !is.na(value) && nzchar(value)
}

.odb_salesforce_array <- function(value) is.list(value) && is.null(names(value))
.odb_salesforce_object <- function(value) {
  is.list(value) &&
    length(value) > 0L &&
    !is.null(names(value)) &&
    all(nzchar(names(value))) &&
    !anyDuplicated(names(value))
}

.odb_salesforce_count <- function(value) {
  if (
    length(value) != 1L ||
      !is.numeric(value) && !is.character(value) ||
      is.na(value)
  ) {
    .odb_salesforce_invalid()
  }
  if (is.character(value) && !grepl("^[0-9]+$", value)) {
    .odb_salesforce_invalid()
  }
  count <- suppressWarnings(as.numeric(value))
  if (
    !is.finite(count) ||
      count < 0 ||
      count != floor(count) ||
      count > .Machine$integer.max
  ) {
    .odb_salesforce_invalid()
  }
  count
}

.odb_salesforce_invalid <- function() {
  .odb_abort(
    "Salesforce returned an invalid or inconsistent query response.",
    "invalid_response"
  )
}

.odb_salesforce_remaining <- function(deadline) {
  remaining <- deadline - .odb_http_time()
  if (remaining <= 0) {
    .odb_abort(
      "Salesforce operation timed out; a submitted query may continue on the server.",
      "timeout"
    )
  }
  remaining
}

.odb_salesforce_request <- function(
  token,
  base,
  path,
  deadline,
  ca_bundle,
  query = list(),
  body = NULL,
  method = "GET",
  exact = FALSE
) {
  req <- httr2::request(base)
  req <- httr2::req_method(req, method)
  req <- httr2::req_headers(req, Accept = "application/json")
  if (length(query)) {
    req <- do.call(httr2::req_url_query, c(list(req), query))
  }
  # Build query parameters before adding escaped query-ID path segments.
  # Otherwise URL query builders can decode their encoded slashes.
  query_suffix <- sub("^[^?]*", "", req$url)
  req <- httr2::req_url(req, paste0(base, "/", path, query_suffix))
  if (!is.null(body)) {
    req <- httr2::req_body_json(req, body, auto_unbox = TRUE)
  }
  resp <- .odb_http_request(
    token,
    req,
    "Salesforce",
    .odb_salesforce_remaining(deadline),
    ca_bundle,
    retry_401 = method == "GET"
  )
  if (exact) {
    # Preserve decimal and integer lexemes before JSON decoding can round them.
    result <- tryCatch(
      {
        httr2::resp_check_content_type(
          resp,
          valid_types = "application/json",
          valid_suffix = "json"
        )
        text <- httr2::resp_body_string(resp, encoding = "UTF-8")
        if (!isTRUE(jsonlite::validate(text))) {
          .odb_salesforce_invalid()
        }
        pattern <- '"(?:[^"\\\\]|\\\\.)*"(*SKIP)(*F)|-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?'
        positions <- gregexpr(pattern, text, perl = TRUE)
        regmatches(text, positions) <- lapply(
          regmatches(text, positions),
          function(x) paste0('"', x, '"')
        )
        jsonlite::parse_json(text, simplifyVector = FALSE)
      },
      error = function(e) .odb_salesforce_invalid()
    )
  } else {
    result <- .odb_http_json(resp, "Salesforce")
  }
  .odb_salesforce_remaining(deadline)
  result
}

.odb_salesforce_records <- function(records) {
  fields <- setdiff(
    unique(unlist(lapply(records, names), use.names = FALSE)),
    "attributes"
  )
  columns <- lapply(fields, function(field) {
    values <- lapply(records, function(record) record[[field]])
    present <- Filter(Negate(is.null), values)
    if (!length(present)) {
      return(rep(NA, length(values)))
    }
    scalar <- vapply(
      present,
      function(x) is.atomic(x) && length(x) == 1L,
      logical(1)
    )
    types <- unique(vapply(present, typeof, ""))
    if (!all(scalar)) {
      return(values)
    }
    if (all(types %in% c("integer", "double"))) {
      return(vapply(
        values,
        function(x) if (is.null(x)) NA_real_ else as.numeric(x),
        numeric(1)
      ))
    }
    if (length(types) != 1L) {
      return(values)
    }
    missing <- switch(
      types,
      character = NA_character_,
      logical = NA,
      double = NA_real_,
      integer = NA_integer_
    )
    if (is.null(missing)) {
      return(values)
    }
    vapply(values, function(x) if (is.null(x)) missing else x, missing)
  })
  names(columns) <- fields
  structure(columns, class = "data.frame", row.names = seq_along(records))
}
