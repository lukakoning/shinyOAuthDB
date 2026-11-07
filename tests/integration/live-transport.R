# Explicitly opt-in transport/authorization checks with short-lived delegated
# user fixtures. This never performs login or obtains refresh credentials.

live_fixture_authorization <- function(client, user, current, session) {
  prefix <- paste0("OAUTHDB_LIVE_", user, "_")
  encoded <- Sys.getenv(paste0(prefix, "TOKENS_JSON"))
  if (nzchar(encoded)) {
    entries <- jsonlite::fromJSON(encoded, simplifyVector = FALSE)
    expected <- names(client@token_targets)
    if (
      !is.list(entries) ||
        !length(expected) ||
        anyDuplicated(names(entries)) ||
        !setequal(names(entries), expected)
    ) {
      stop(
        "Supply exactly the client's named target credentials.",
        call. = FALSE
      )
    }
    make <- function(entry) {
      if (
        !is.list(entry) ||
          !is.character(entry$access_token) ||
          length(entry$access_token) != 1L ||
          !is.numeric(entry$expires_at) ||
          length(entry$expires_at) != 1L ||
          !is.finite(entry$expires_at) ||
          entry$expires_at <= as.numeric(Sys.time()) + 300 ||
          !is.list(entry$scopes) ||
          !length(entry$scopes) ||
          !all(vapply(
            entry$scopes,
            function(x) is.character(x) && length(x) == 1L && !is.na(x),
            logical(1)
          ))
      ) {
        stop(
          "Each target needs a bearer, scopes array and at least five minutes of lifetime.",
          call. = FALSE
        )
      }
      shinyOAuth::OAuthToken(
        access_token = entry$access_token,
        token_type = "Bearer",
        expires_at = entry$expires_at,
        granted_scopes = unlist(entry$scopes, use.names = FALSE),
        granted_scopes_verified = TRUE
      )
    }
    targets <- lapply(entries, make)
    token <- targets[[client@token_target_default]]
    return(live_connection(client, user, current, session, token, targets))
  }
  if (length(client@token_targets) > 1L) {
    stop(
      "Multi-audience acceptance requires OAUTHDB_LIVE_A_TOKENS_JSON and OAUTHDB_LIVE_B_TOKENS_JSON.",
      call. = FALSE
    )
  }
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
  live_connection(client, user, current, session, token)
}

live_connection <- function(
  client,
  user,
  current,
  session,
  token,
  targets = NULL
) {
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
        getFromNamespace("connection_access_error", "shinyOAuth")(
          "authorization_unavailable"
        )
      }

      list(
        client = client,
        token = token,
        status = "active",
        targets = if (is.null(targets)) NULL else list(tokens = targets)
      )
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
      is.na(fixture$backend) ||
      !nzchar(fixture$backend) ||
      !is.function(fixture$validate) ||
      !is.function(fixture$identify) ||
      !is.function(fixture$denied) ||
      !is.character(fixture$users) ||
      !identical(names(fixture$users), c("A", "B")) ||
      anyNA(fixture$users) ||
      any(!nzchar(fixture$users)) ||
      anyDuplicated(fixture$users)
  ) {
    stop(
      "Supply backend, distinct named users A/B, validate(user, value), identify(user, native, spec) and denied(user, native, spec).",
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
  checks <- new.env(parent = emptyenv())
  checks$scenarios <- character()
  record <- function(name, valid) {
    if (!isTRUE(valid)) {
      stop("Live acceptance failed: ", name, call. = FALSE)
    }
    checks$scenarios <- c(checks$scenarios, name)
  }
  blocked <- function(expr) {
    error <- tryCatch(
      {
        force(expr)
        NULL
      },
      error = identity
    )
    inherits(
      error,
      c(
        "shiny.silent.error",
        "shinyOAuth_access_error",
        "shinyOAuthDB_authorization_unavailable"
      )
    )
  }

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
    record("A_grants", fixture$validate("A", rows_a))
    connection_a <- native()
    record(
      "A_identity",
      identical(
        fixture$identify("A", connection_a, spec),
        unname(fixture$users[["A"]])
      )
    )
    record("A_denied", fixture$denied("A", connection_a, spec))
    if (is.function(spec$checks)) {
      record("A_roundtrip", spec$checks(connection_a))
    }
    is_sql <- inherits(connection_a, "DBIConnection")
    if (is_sql) {
      spec$query(native(), spec$native_args(7L))
      record("connection_reuse", identical(connection_a, native()))
    }

    current(user_b)
    session$flushReact()
    if (is_sql && isTRUE(spec$retires_handle)) {
      record("A_handle_retired", !isTRUE(DBI::dbIsValid(connection_a)))
    }
    if (isTRUE(spec$pinned_resource)) {
      record(
        "A_resource_retired",
        blocked(spec$query(connection_a, spec$native_args(7L)))
      )
    }

    rows_b <- rows()
    record("B_grants", fixture$validate("B", rows_b))
    record("distinct_results", !identical(rows_a, rows_b))
    connection_b <- native()
    record(
      "B_identity",
      identical(
        fixture$identify("B", connection_b, spec),
        unname(fixture$users[["B"]])
      )
    )
    record("B_denied", fixture$denied("B", connection_b, spec))
    if (is.function(spec$checks)) {
      record("B_roundtrip", spec$checks(connection_b))
    }

    current(NULL)
    session$flushReact()
    record(
      "logout_blocks_query",
      blocked(spec$query(native(), spec$native_args(7L)))
    )
    session$close()
    record(
      "closed_session_blocks_query",
      blocked(spec$query(native(), spec$native_args(7L)))
    )
    if (is_sql && isTRUE(spec$retires_handle)) {
      record("B_handle_closed", !isTRUE(DBI::dbIsValid(connection_b)))
    }
  })

  list(
    status = "pass",
    route = spec$route,
    helper = spec$helper,
    auth_mode = spec$auth_mode,
    scenarios = checks$scenarios,
    browser_sign_in = FALSE,
    refresh = FALSE
  )
}
