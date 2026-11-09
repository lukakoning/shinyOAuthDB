#' Query MongoDB as the signed-in user
#'
#' Read MongoDB collections, run aggregation pipelines and issue database
#' commands using the visitor's OAuth access token. Uses the official PyMongo
#' driver through reticulate, with a separate client for each Shiny session.
#'
#' @inheritParams oauth_db_connect
#' @param url Credential-free `mongodb://` or `mongodb+srv://` connection URL.
#'   Authentication, TLS, retry and timeout options are set by the helper.
#' @param db Database name.
#' @param issuer Exact HTTPS issuer configured for MongoDB workforce OIDC.
#' @param user Optional MongoDB OIDC username, or a function returning it.
#'   Useful when the deployment uses the username to select an identity provider.
#' @param client_id Optional expected client ID in MongoDB's OIDC challenge.
#' @param allowed_hosts Hostnames to which PyMongo may send visitor tokens.
#'   An entry can start with `*.` to allow subdomains. Defaults to the seed
#'   hosts for ordinary URLs, or the cluster's parent domain for Atlas SRV URLs.
#'   Supply this explicitly for other SRV deployments or additional replica hosts.
#' @param timeout Positive operation timeout in seconds, including server
#'   selection, authentication and fetching result pages.
#' @param ca_bundle Optional trusted CA certificate file. TLS always verifies
#'   certificates and hostnames.
#' @return A client with these methods:
#'   \itemize{
#'     \item \code{$find(collection, filter = "{}", projection = "{\"_id\":0}",
#'       sort = "{}", skip = 0, limit = 100, simplify = TRUE)} reads documents.
#'     \item \code{$aggregate(collection, pipeline, simplify = TRUE)} consumes
#'       an aggregation cursor, including all result pages.
#'     \item \code{$count(collection, filter = "{}")} counts matching documents.
#'     \item \code{$run(command, simplify = FALSE)} issues one database command.
#'       Authentication, transaction and cursor commands are excluded.
#'   }
#'   Inputs use MongoDB JSON or Extended JSON strings. Reads return data frames
#'   by default; `simplify = FALSE` preserves lists. BSON-specific values retain
#'   their Extended JSON representation, and large integers remain strings.
#' @details
#' MongoDB must support workforce OIDC: Atlas with workforce federation, or
#' a supported Linux MongoDB Enterprise deployment. Community Server doesn't
#' provide this authentication. Configure the issuer, audience and database
#' user or group permissions before connecting.
#'
#' Install reticulate and PyMongo 4.10 or later in its selected Python
#' environment. Python is initialized only on the first signed-in operation;
#' the helper never installs dependencies or chooses a different interpreter.
#' mongolite currently has no public OIDC callback for supplying visitor tokens.
#'
#' Create the client inside `server()`. shinyOAuth obtains and renews tokens.
#' PyMongo's human OIDC callback supplies only the current client's access
#' token after checking the server's issuer and optional client ID. It never
#' starts browser sign-in or uses workload credentials from the app host.
#'
#' Clients are replaced on their next use after token or username changes.
#' Sign-out, permission loss and session end close them. Results arriving after
#' an authorization change are discarded. Cursors are consumed and closed in
#' the operation that created them; transactions and retained cursors aren't
#' exposed. `limit = 0` fetches all matching documents.
#'
#' Driver retryable reads and writes are disabled, and the helper doesn't
#' replay failed operations. PyMongo handles protocol reauthentication with
#' the same supplied token. A failed or timed-out operation can still have
#' effects on the server, including aggregation pipelines that write data.
#' @examples
#' \dontrun{
#' mongo <- oauth_db_mongodb(auth$connection,
#'   url = "mongodb://mongo.example.org:27017", db = "reporting",
#'   issuer = "https://login.example.org/realms/reporting")
#' output$rows <- shiny::renderTable({
#'   mongo$find("orders", filter = '{"country":"NL"}', limit = 20)
#' })
#' }
#' @seealso `vignette("mongodb", package = "shinyOAuthDB")`.
#' @export
oauth_db_mongodb <- function(
  authorization,
  url,
  db,
  issuer,
  user = NULL,
  client_id = NULL,
  allowed_hosts = NULL,
  timeout = 30,
  ca_bundle = NULL,
  target = NULL,
  required_scopes = character(),
  min_valid_for = 60,
  session = shiny::getDefaultReactiveDomain()
) {
  .odb_require("jsonlite")
  hosts <- .odb_mongodb_url(url, allowed_hosts)
  .odb_string(db, "db")
  if (grepl("[/\\\\.\"$[:space:][:cntrl:]]", db)) {
    .odb_abort("db must be a MongoDB database name.")
  }
  .odb_string(issuer, "issuer")
  address <- httr2::url_parse(issuer)
  if (
    !identical(address$scheme, "https") ||
      is.null(address$hostname) ||
      !is.null(address$username) ||
      !is.null(address$password) ||
      length(address$query) ||
      !is.null(address$fragment)
  ) {
    .odb_abort("issuer must be an HTTPS issuer without credentials or query.")
  }
  .odb_string(client_id, "client_id", optional = TRUE)
  .odb_seconds(timeout, "timeout")
  if (timeout <= 0) {
    .odb_abort("timeout must be positive.")
  }
  .odb_string(ca_bundle, "ca_bundle", optional = TRUE)
  username <- function() {
    value <- if (is.function(user)) user() else user
    .odb_string(value, "user", optional = TRUE)
    value
  }
  if (!is.function(user)) {
    username()
  }
  connection <- .odb_bind(
    authorization,
    .odb_backend_mongodb,
    url = url,
    db = db,
    issuer = issuer,
    user = username,
    client_id = client_id,
    hosts = hosts,
    timeout = timeout,
    ca_bundle = ca_bundle,
    disconnect = .odb_mongodb_disconnect,
    cache_key = function(token) openssl::sha256(charToRaw(token())),
    identity_key = username,
    target = target,
    required_scopes = required_scopes,
    min_valid_for = min_valid_for,
    session = session
  )
  .odb_mongodb_client$new(connection)
}

.odb_backend_mongodb <- function(
  token,
  url,
  db,
  issuer,
  user,
  client_id,
  hosts,
  timeout,
  ca_bundle
) {
  username <- if (is.function(user)) user() else user
  driver <- .odb_mongodb_open(
    token(),
    url,
    db,
    issuer,
    username,
    client_id,
    hosts,
    timeout,
    ca_bundle
  )
  list(driver = driver, check = function() token(.check_only = TRUE))
}

.odb_mongodb_disconnect <- function(value) value$driver$close()

.odb_mongodb_client <- R6::R6Class(
  "OAuthMongoDBClient",
  cloneable = FALSE,
  public = list(
    initialize = function(connection) {
      private$connection <- connection
    },
    find = function(
      collection,
      filter = "{}",
      projection = '{"_id":0}',
      sort = "{}",
      skip = 0,
      limit = 100,
      simplify = TRUE
    ) {
      private$collection(collection)
      .odb_mongodb_json(filter, "filter")
      .odb_mongodb_json(projection, "projection")
      .odb_mongodb_json(sort, "sort")
      for (value in list(skip, limit)) {
        if (
          !is.numeric(value) ||
            length(value) != 1L ||
            !is.finite(value) ||
            value < 0 ||
            value > .Machine$integer.max ||
            value != floor(value)
        ) {
          .odb_abort("skip and limit must be non-negative 32-bit integers.")
        }
      }
      private$execute(
        "find",
        list(
          collection = collection,
          filter = filter,
          projection = projection,
          sort = sort,
          skip = as.integer(skip),
          limit = as.integer(limit)
        ),
        simplify,
        rows = TRUE
      )
    },
    aggregate = function(collection, pipeline, simplify = TRUE) {
      private$collection(collection)
      .odb_mongodb_json(pipeline, "pipeline", array = TRUE)
      private$execute(
        "aggregate",
        list(
          collection = collection,
          pipeline = pipeline
        ),
        simplify,
        rows = TRUE
      )
    },
    count = function(collection, filter = "{}") {
      private$collection(collection)
      .odb_mongodb_json(filter, "filter")
      private$execute(
        "count",
        list(collection = collection, filter = filter),
        FALSE
      )
    },
    run = function(command, simplify = FALSE) {
      .odb_mongodb_json(command, "command")
      private$execute("run", list(command = command), simplify)
    },
    print = function(...) {
      cat("<OAuthMongoDBClient>\n")
      invisible(self)
    }
  ),
  private = list(
    connection = NULL,
    collection = function(value) {
      .odb_string(value, "collection")
      if (grepl("[[:cntrl:]]|\\$|^\\.|\\.$|\\.\\.", value)) {
        .odb_abort("collection must be a MongoDB collection name.")
      }
    },
    execute = function(operation, arguments, simplify, rows = FALSE) {
      .odb_flag(simplify, "simplify")
      native <- private$connection()
      response <- native$driver$execute(operation, arguments)
      native$check()
      if (!isTRUE(response$ok)) {
        code <- response$code
        detail <- if (
          is.numeric(code) && length(code) == 1L && is.finite(code)
        ) {
          paste0(" (server code ", code, ")")
        } else {
          ""
        }
        .odb_abort(
          paste0(
            "The MongoDB operation failed",
            detail,
            ". Check the query, workforce OIDC configuration and database permissions."
          ),
          "query_failed"
        )
      }
      result <- jsonlite::fromJSON(
        response$json,
        simplifyVector = simplify,
        bigint_as_char = TRUE
      )
      if (rows && simplify && identical(result, list())) {
        data.frame()
      } else {
        result
      }
    }
  )
)

.odb_mongodb_json <- function(value, name, array = FALSE) {
  .odb_string(value, name)
  if (
    !jsonlite::validate(value) ||
      !grepl(if (array) "^\\s*\\[" else "^\\s*\\{", value)
  ) {
    .odb_abort(paste0(
      name,
      " must be a JSON ",
      if (array) "array." else "object."
    ))
  }
  invisible(NULL)
}

.odb_mongodb_url <- function(url, allowed_hosts) {
  .odb_string(url, "url")
  if (
    !grepl("^mongodb(\\+srv)?://", url) || grepl("[[:space:][:cntrl:]#]", url)
  ) {
    .odb_abort("url must be a credential-free MongoDB connection URL.")
  }
  rest <- sub("^mongodb(\\+srv)?://", "", url)
  authority <- sub("[/\\?].*$", "", rest)
  if (!nzchar(authority) || grepl("[^A-Za-z0-9.,:\\[\\]-]", authority)) {
    .odb_abort(
      "MongoDB URL hosts cannot contain credentials or escaped characters."
    )
  }
  path <- sub("^[^/\\?]*", "", rest)
  if (!grepl("^/?(\\?.*)?$", path)) {
    .odb_abort("Set the database with db, not in the MongoDB URL.")
  }
  if (grepl("?", path, fixed = TRUE)) {
    options <- strsplit(sub("^.*?\\?", "", path), "&", fixed = TRUE)[[1L]]
    keys <- tolower(utils::URLdecode(sub("=.*$", "", options)))
    allowed <- c(
      "replicaset",
      "directconnection",
      "loadbalanced",
      "readpreference",
      "readconcernlevel",
      "w",
      "appname",
      "srvservicename",
      "srvmaxhosts"
    )
    if (anyDuplicated(keys) || !all(keys %in% allowed)) {
      .odb_abort(
        "MongoDB URL options cannot override authentication, TLS, retries or timeouts."
      )
    }
  }
  if (is.null(allowed_hosts)) {
    if (startsWith(url, "mongodb+srv://")) {
      if (
        !grepl("^[A-Za-z0-9-]+\\.[A-Za-z0-9-]+\\.mongodb\\.net$", authority)
      ) {
        .odb_abort("Supply allowed_hosts for this MongoDB SRV deployment.")
      }
      allowed_hosts <- paste0("*.", sub("^[^.]+\\.", "", authority))
    } else {
      allowed_hosts <- sub(
        "^\\[([^]]+)\\](:[0-9]+)?$|:[0-9]+$",
        "\\1",
        strsplit(authority, ",", fixed = TRUE)[[1L]]
      )
    }
  }
  if (
    !is.character(allowed_hosts) ||
      !length(allowed_hosts) ||
      anyNA(allowed_hosts) ||
      !all(grepl("^(\\*\\.)?[A-Za-z0-9][A-Za-z0-9.:-]*$", allowed_hosts)) ||
      any(grepl("^\\*\\.[^.]+$", allowed_hosts))
  ) {
    .odb_abort(
      "allowed_hosts must contain explicit hostnames or *.domain names."
    )
  }
  unique(tolower(allowed_hosts))
}

.odb_mongodb_open <- function(
  token,
  url,
  db,
  issuer,
  user,
  client_id,
  hosts,
  timeout,
  ca_bundle
) {
  .odb_require("reticulate", "MongoDB", version = "1.35.0")
  if (!grepl("^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$", token)) {
    .odb_abort(
      "MongoDB requires a signed JWT access token.",
      "invalid_credential"
    )
  }
  tryCatch(
    {
      module <- reticulate::import_from_path(
        "shiny_oauthdb_mongodb",
        path = system.file("python", package = "shinyOAuthDB")
      )
      module$Client(
        token,
        url,
        db,
        issuer,
        user,
        client_id,
        as.list(hosts),
        timeout,
        ca_bundle
      )
    },
    error = function(error) {
      .odb_abort(
        "Cannot initialize MongoDB. Install PyMongo >= 4.10 in reticulate's Python environment and check the connection settings.",
        "connection_failed"
      )
    }
  )
}
