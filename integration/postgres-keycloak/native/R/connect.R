# This package belongs only to the disposable Linux integration fixture.
# It is deliberately absent from shinyOAuthDB's production dependencies.

scalar_string <- function(value, name) {
  if (
    !is.character(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !nzchar(value) ||
      grepl("[\r\n]", value)
  ) {
    stop(
      name,
      " must be one nonempty string without line breaks.",
      call. = FALSE
    )
  }

  value
}

rpostgres_dll <- function() {
  loadNamespace("RPostgres")
  dll <- getLoadedDLLs()[["RPostgres"]]
  if (is.null(dll)) {
    stop("RPostgres's native library is not loaded.", call. = FALSE)
  }

  dll[["path"]]
}

#' Check the PostgreSQL integration runtime
#'
#' Use this before running the fixture to check that pgBearerHook and
#' RPostgres share libpq 18 and the expected authentication hook.
#'
#' @return A list of runtime version and hook-status information.
#'   This function doesn't open a connection.
#' @export
pg_bearer_runtime <- function() {
  .Call(C_pg_bearer_runtime, rpostgres_dll())
}

#' Open a fixture connection with an existing OAuth token
#'
#' Use this in the PostgreSQL/Keycloak integration fixture to connect as a
#' test user. RPostgres returns the DBI connection; PostgreSQL validates the
#' token and checks whether it may authenticate the requested database role.
#'
#' @param token Access token without the Bearer prefix.
#' @param issuer Exact HTTPS issuer from the PostgreSQL authentication settings.
#' @param scope Space-separated OAuth scopes for this database.
#' @param host,port,dbname,user Connection target and database role.
#' @param sslmode Must be `"verify-full"`.
#' @param sslrootcert Database CA certificate path, or `NULL` for libpq defaults.
#' @param connect_timeout Connection timeout in seconds, at least two.
#' @return An RPostgres `PqConnection`, managed through DBI.
#' @details
#' This Linux/libpq 18 helper belongs to the disposable integration fixture.
#' Its token hook is active only while opening the connection. It doesn't
#' acquire or refresh tokens. Discard broken connections; resetting or cloning
#' them is unsupported. See the fixture README for the required libpq build.
#' @export
pg_connect_bearer <- function(
  token,
  issuer,
  scope,
  host,
  port,
  dbname,
  user,
  sslmode = "verify-full",
  sslrootcert = NULL,
  connect_timeout = 5L
) {
  token <- scalar_string(token, "token")
  if (grepl("[[:space:]]", token) || startsWith(token, "Bearer ")) {
    stop(
      "token must be the raw bearer token without whitespace.",
      call. = FALSE
    )
  }

  issuer <- scalar_string(issuer, "issuer")
  if (
    !grepl("^https://[^/?#]+(/[^?#]*)?$", issuer) ||
      endsWith(issuer, "/") ||
      grepl("/\\.well-known/", issuer)
  ) {
    stop(
      "issuer must be an HTTPS issuer identifier without a trailing slash or discovery suffix.",
      call. = FALSE
    )
  }

  scope <- scalar_string(scope, "scope")
  scopes <- strsplit(scope, " ", fixed = TRUE)[[1L]]
  if (
    any(!nzchar(scopes)) || anyDuplicated(scopes) || grepl("[\t\r\n]", scope)
  ) {
    stop(
      "scope must contain distinct scopes separated by single spaces.",
      call. = FALSE
    )
  }

  host <- scalar_string(host, "host")
  dbname <- scalar_string(dbname, "dbname")
  user <- scalar_string(user, "user")
  if (grepl(",", host, fixed = TRUE) || startsWith(host, "/")) {
    stop("host must be one TCP hostname or address.", call. = FALSE)
  }

  port <- suppressWarnings(as.integer(port))
  if (length(port) != 1L || is.na(port) || port < 1L || port > 65535L) {
    stop("port must be one valid TCP port.", call. = FALSE)
  }
  if (!identical(sslmode, "verify-full")) {
    stop("This fixture requires sslmode = 'verify-full'.", call. = FALSE)
  }
  if (!is.null(sslrootcert)) {
    sslrootcert <- scalar_string(sslrootcert, "sslrootcert")
  }
  if (
    !is.numeric(connect_timeout) ||
      length(connect_timeout) != 1L ||
      !is.finite(connect_timeout) ||
      connect_timeout < 2 ||
      connect_timeout != floor(connect_timeout)
  ) {
    stop(
      "connect_timeout must be a whole number of at least two seconds.",
      call. = FALSE
    )
  }
  if (
    any(nzchar(Sys.getenv(c("PGSERVICE", "PGSERVICEFILE", "PGOAUTHDEBUG"))))
  ) {
    stop(
      "Unset PGSERVICE, PGSERVICEFILE and PGOAUTHDEBUG for this explicit-credential fixture.",
      call. = FALSE
    )
  }

  runtime <- pg_bearer_runtime()
  if (!isTRUE(runtime$default_hook)) {
    stop(
      "The fixture requires libpq's default hook; another OAuth hook is installed.",
      call. = FALSE
    )
  }

  params <- list(
    host = host,
    port = as.character(port),
    dbname = dbname,
    user = user,
    sslmode = sslmode,
    sslrootcert = sslrootcert,
    connect_timeout = as.character(connect_timeout),
    require_auth = "oauth",
    gssencmode = "disable",

    # Empty values are ignored by PQconnectdbParams. An explicit sentinel
    # prevents PGPASSWORD/.pgpass from supplying a real password instead.
    password = "pgBearerHook-password-disabled",
    passfile = "/dev/null",
    oauth_issuer = issuer,
    oauth_scope = scope,

    # libpq 18 checks for a nonempty ID before calling its custom bearer hook.
    # No OAuth HTTP requests are made with this integration-only sentinel.
    oauth_client_id = "pgBearerHook-external-bearer-only",
    application_name = "shinyOAuthDB-pg-bearer-fixture"
  )

  open <- function() {
    do.call(DBI::dbConnect, c(list(RPostgres::Postgres()), params))
  }

  expected <- c(
    issuer,
    scope,
    host,
    as.character(port),
    dbname,
    user,
    "pgBearerHook-external-bearer-only"
  )

  .Call(C_pg_with_bearer, token, expected, open)
}
