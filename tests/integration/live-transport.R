# Explicitly opt-in transport/authorization checks with short-lived delegated
# user fixtures. This never performs login or obtains refresh credentials.

live_fixture_authorization <- function(client, user, current, session) {
  prefix <- paste0("OAUTHDB_LIVE_", user, "_")
  bearer <- live_env(paste0(prefix, "TOKEN"))
  expires_at <- suppressWarnings(as.numeric(live_env(paste0(
    prefix,
    "EXPIRES_AT"
  ))))
  scopes <- strsplit(live_env(paste0(prefix, "SCOPES")), " +")[[1L]]
  if (!is.finite(expires_at) || expires_at <= as.numeric(Sys.time()) + 300) {
    stop(
      "Each live fixture needs at least five minutes of recorded token lifetime.",
      call. = FALSE
    )
  }

  token <- shinyOAuth::OAuthToken(
    access_token = bearer,
    token_type = "Bearer",
    expires_at = expires_at,
    granted_scopes = scopes,
    granted_scopes_verified = TRUE
  )
  id <- paste0("live-fixture-", user)

  getFromNamespace("OAuthConnection", "shinyOAuth")$new(
    id = id,
    client = client,
    resolve = function() {
      domain <- shiny::getDefaultReactiveDomain()
      if (
        isTRUE(session$isClosed()) ||
          is.null(domain) ||
          !identical(domain$rootScope(), session$rootScope()) ||
          !identical(current()$id, id)
      ) {
        stop("Live fixture authorization ended.", call. = FALSE)
      }

      list(client = client, token = token, status = "active")
    },

    acquire = function(...) {
      stop("Fixed live credentials cannot refresh.", call. = FALSE)
    },

    is_current = function() identical(current()$id, id)
  )
}

run_live_transport <- function(fixture) {
  if (!identical(Sys.getenv("OAUTHDB_LIVE_TESTS"), "true")) {
    stop(
      "Live tests are disabled; explicitly set OAUTHDB_LIVE_TESTS=true.",
      call. = FALSE
    )
  }
  if (
    !is.list(fixture) ||
      !is.character(fixture$backend) ||
      length(fixture$backend) != 1L ||
      !is.function(fixture$validate)
  ) {
    stop(
      "The trusted fixture must supply backend and validate(user, value).",
      call. = FALSE
    )
  }

  spec <- live_spec(fixture$backend)
  if (!is.null(fixture$configure)) {
    if (!is.function(fixture$configure)) {
      stop("fixture$configure must be a function.", call. = FALSE)
    }

    spec <- fixture$configure(spec)
  }

  client <- live_client(spec)

  server <- function(input, output, session) {
    current <- shiny::reactiveVal(NULL)

    native <- spec$bind(current)
    rows <- shiny::reactive({
      connection <- native()
      spec$query(connection, spec$native_args(7L))
    })
    user_a <- live_fixture_authorization(client, "A", current, session)
    user_b <- live_fixture_authorization(client, "B", current, session)
  }

  # Both users execute the same operator-defined read operation. The remote
  # platform, not an application WHERE clause, must enforce their grants.
  shiny::testServer(server, {
    current(user_a)
    session$flushReact()
    rows_a <- rows()
    if (!isTRUE(fixture$validate("A", rows_a))) {
      stop("User A fixture expectation failed.", call. = FALSE)
    }
    connection_a <- native()
    is_sql <- inherits(connection_a, "DBIConnection")
    if (is_sql) {
      spec$query(native(), spec$native_args(7L))
      if (!identical(connection_a, native())) {
        stop("Session connection reuse failed.", call. = FALSE)
      }
    }

    current(user_b)
    session$flushReact()
    if (is_sql && isTRUE(DBI::dbIsValid(connection_a))) {
      stop("User A connection was not retired.", call. = FALSE)
    }

    rows_b <- rows()
    if (!isTRUE(fixture$validate("B", rows_b))) {
      stop("User B fixture expectation failed.", call. = FALSE)
    }

    current(NULL)
    session$flushReact()
    blocked <- tryCatch({ native(); FALSE }, error = function(e) TRUE)
    if (!blocked) {
      stop("Logout did not invalidate the native accessor.", call. = FALSE)
    }
  })

  invisible(TRUE)
}
