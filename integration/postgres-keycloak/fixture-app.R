# Genuine browser sign-in and PostgreSQL OAuth through the public package helper.

postgres_fixture_error_detail <- function(condition) {
  detail <- conditionMessage(condition)
  detail <- gsub("https?://[^[:space:]]+", "[configured endpoint]", detail)
  detail <- gsub(
    "eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+",
    "[redacted credential]",
    detail
  )
  detail <- gsub(
    "(?i)bearer[[:space:]]+[A-Za-z0-9_.~+/-]+=*",
    "[redacted bearer]",
    detail,
    perl = TRUE
  )

  substr(detail, 1L, 1000L)
}

postgres_browser_app <- function(config) {
  # This process belongs to the loopback-only fixture; use shinyOAuth's normal
  # host checks with the explicit local issuer/callback host allowlist.
  options(shinyOAuth.allowed_hosts = c("localhost", "127.0.0.1", "::1"))
  provider <- shinyOAuth::oauth_provider_oidc_discover(
    # Keycloak's discovery omits 'none'; its public registrations accept the
    # advertised body style with client_id and an empty registered secret.
    config$issuer,
    token_auth_style = "body",
    id_token_validation = TRUE
  )

  # Keep the browser-visible authorization request inspectable for PKCE and
  # explicitly show the login form when changing the external user.
  provider@par_url <- NA_character_
  provider@extra_auth_params <- list(prompt = "login")
  scopes <- c(
    "openid",
    "profile",
    if (config$client_id != "shiny-missing-scope") "database.read"
  )
  client <- shinyOAuth::oauth_client(
    provider,
    client_id = config$client_id,
    client_secret = "",
    redirect_uri = paste0(config$origin, "/callback"),
    scopes = scopes,
    required_scopes = "openid"
  )
  base <- postgres_playground_ui(config)
  ui <- shinyOAuth::oauth_ui(base, id = "auth", client = client)

  server <- function(input, output, session) {
    auth <- shinyOAuth::oauth_module_server(
      "auth",
      client,
      auto_redirect = FALSE,
      async = TRUE,
      refresh_proactively = FALSE,
      indefinite_session = isTRUE(config$retain_expired)
    )

    authorization <- shiny::reactive(auth$connection())
    feedback <- shiny::reactiveVal(list(
      text = "Connecting to the browser. Sign-in will be available shortly.",
      kind = "info",
      sequence = 0L
    ))
    refreshing <- shiny::reactiveVal(FALSE)
    refresh_job <- NULL
    notice <- function(text, kind = "info") {
      feedback(list(
        text = text,
        kind = kind,
        sequence = shiny::isolate(feedback())$sequence + 1L
      ))
    }

    connect_attempts <- shiny::reactiveVal(0L)

    successful_connections <- shiny::reactiveVal(0L)

    connections <- shiny::reactiveVal(list())
    disconnects <- function() {
      sum(vapply(
        connections(),
        function(native) !DBI::dbIsValid(native),
        logical(1)
      ))
    }

    native_error_detail <- shiny::reactiveVal(NULL)

    role_cache <- NULL
    database_role <- function() {
      reference <- authorization()
      shiny::req(reference)
      if (!is.null(role_cache) && identical(role_cache$id, reference$id)) {
        return(role_cache$role)
      }
      # Keep the verified mapping for this authorization while credentials rotate.
      subject <- shiny::isolate(
        reference$identity(claims = "sub")$id_token_claims$sub
      )
      role <- switch(
        subject,
        "11111111-1111-4111-8111-111111111111" = "alice",
        "22222222-2222-4222-8222-222222222222" = "bob",
        NULL
      )
      if (is.null(role)) {
        stop(
          "The validated fixture identity has no database role.",
          call. = FALSE
        )
      }
      role_cache <<- list(id = reference$id, role = role)
      role
    }
    database <- shinyOAuthDB::oauth_db_postgres(
      authorization,
      user = database_role,
      issuer = config$issuer,
      scope = "database.read",
      host = config$pg_host,
      port = config$pg_port,
      dbname = config$pg_dbname,
      sslrootcert = config$ca_file,
      required_scopes = "database.read",
      min_valid_for = 1
    )
    negative_results <- shiny::reactiveVal(NULL)
    expired_denied <- shiny::reactiveVal(NULL)
    original_token <- NULL
    original_expiry <- NULL
    original_role <- NULL
    negative_connection <- function(
      token,
      host = config$pg_host,
      ca = config$ca_file,
      user = database_role()
    ) {
      getFromNamespace(".odb_postgres_connect_bearer", "shinyOAuthDB")(
        token = token,
        issuer = config$issuer,
        scope = "database.read",
        host = host,
        port = config$pg_port,
        dbname = config$pg_dbname,
        user = user,
        sslrootcert = ca,
        connect_timeout = 3L
      )
    }
    rejects <- function(token, ..., pattern = "OAuth") {
      tryCatch(
        {
          value <- negative_connection(token, ...)
          DBI::dbDisconnect(value)
          FALSE
        },
        error = function(e) {
          grepl(pattern, conditionMessage(e), ignore.case = TRUE)
        }
      )
    }
    shiny::observeEvent(input$native_credentials, {
      tryCatch(
        {
          token <- authorization()$access_token(min_valid_for_seconds = 1)
          original_token <<- token
          original_role <<- database_role()
          segment <- chartr(
            "-_",
            "+/",
            strsplit(token, ".", fixed = TRUE)[[1L]][2L]
          )
          segment <- paste0(
            segment,
            strrep("=", (4L - nchar(segment) %% 4L) %% 4L)
          )
          claims <- jsonlite::fromJSON(rawToChar(openssl::base64_decode(
            segment
          )))
          original_expiry <<- claims$exp
          pieces <- strsplit(token, ".", fixed = TRUE)[[1L]]
          signature <- pieces[[3L]]
          substr(signature, 1L, 1L) <- if (startsWith(signature, "a")) {
            "b"
          } else {
            "a"
          }
          pieces[[3L]] <- signature
          checks <- list(
            tampered = rejects(paste(pieces, collapse = ".")),
            wrong_ca = rejects(
              token,
              ca = "/fixtures/tls/untrusted-ca.pem",
              pattern = "certificate"
            ),
            wrong_hostname = rejects(
              token,
              host = "fixture-mismatch",
              pattern = "certificate"
            )
          )
          control <- negative_connection(token)
          checks$valid_control <- identical(
            DBI::dbGetQuery(control, "SELECT current_user::text AS name")$name,
            database_role()
          )
          DBI::dbDisconnect(control)
          negative_results(checks)
        },
        error = function(e) {
          negative_results(list(
            fixture_error = postgres_fixture_error_detail(e)
          ))
        }
      )
    })
    shiny::observeEvent(input$expired_credential, {
      shiny::req(
        original_token,
        original_expiry,
        as.numeric(Sys.time()) > original_expiry + 1
      )
      expired_denied(rejects(original_token, user = original_role))
    })
    previous <- NULL
    con <- function() {
      reference <- authorization()
      if (!is.null(reference)) {
        held_provider <<- reference$access_token
      }
      opening <- is.null(previous) ||
        !getFromNamespace(
          ".odb_postgres_connection_valid",
          "shinyOAuthDB"
        )(previous)
      if (
        opening && !is.null(reference) && reference$has_scopes("database.read")
      ) {
        connect_attempts(shiny::isolate(connect_attempts()) + 1L)
      }
      native <- tryCatch(database(), error = function(e) {
        if (!inherits(e, "shiny.silent.error")) {
          native_error_detail(postgres_fixture_error_detail(e))
        }
        stop(e)
      })
      if (!identical(native, previous)) {
        successful_connections(shiny::isolate(successful_connections()) + 1L)
        connections(c(shiny::isolate(connections()), list(native)))
        previous <<- native
      }
      native
    }

    last_error <- shiny::reactiveVal(NULL)
    dbplyr_checks <- shiny::reactiveVal(NULL)
    shiny::observeEvent(input$dbplyr, {
      native <- con()
      tryCatch(
        {
          table <- dplyr::tbl(
            native,
            DBI::Id(schema = "public", table = "visible_rows")
          )
          marker <- paste0(database_role(), "-visible-1")
          filtered <- dplyr::collect(dplyr::select(
            dplyr::filter(table, .data$marker == !!marker),
            "marker"
          ))
          empty <- dplyr::collect(dplyr::select(
            dplyr::filter(table, .data$marker == "absent-fixture-row"),
            "marker"
          ))
          value <- "quoted ' text; -- café 雪"
          typed <- DBI::dbGetQuery(
            native,
            paste(
              "SELECT $1::text AS value, NULL::text AS missing,",
              "9223372036854775807::bigint AS integer_value, TIMESTAMPTZ '2020-02-29 12:34:56.125+00' AS instant"
            ),
            params = list(value)
          )
          dbplyr_checks(list(
            filter = identical(filtered$marker, marker),
            empty = identical(names(empty), "marker") && nrow(empty) == 0L,
            parameter = identical(typed$value, value),
            null = is.na(typed$missing),
            bigint = identical(
              as.character(typed$integer_value),
              "9223372036854775807"
            ),
            timestamp = inherits(typed$instant, "POSIXct") &&
              abs(
                as.numeric(typed$instant) -
                  as.numeric(as.POSIXct("2020-02-29 12:34:56", tz = "UTC")) -
                  0.125
              ) <
                0.0001
          ))
        },
        error = function(e) {
          dbplyr_checks(list(fixture_error = postgres_fixture_error_detail(e)))
        }
      )
    })

    query_attempts <- shiny::reactiveVal(0L)

    refreshes <- shiny::reactiveVal(0L)

    credential_rotated <- shiny::reactiveVal(FALSE)
    refresh_rejected <- shiny::reactiveVal(NULL)

    reset_count <- shiny::reactiveVal(0L)
    terminated_pid <- shiny::reactiveVal(NULL)

    role_probe_attempts <- shiny::reactiveVal(0L)

    other_role_denied <- shiny::reactiveVal(NULL)

    grant_probe_attempts <- shiny::reactiveVal(0L)

    own_table_allowed <- shiny::reactiveVal(NULL)

    other_table_denied <- shiny::reactiveVal(NULL)

    native_scope_probe_attempts <- shiny::reactiveVal(0L)

    native_scope_denied <- shiny::reactiveVal(NULL)

    held_connection <- NULL
    held_owner <- NULL
    held_provider <- NULL

    held_query_failures <- shiny::reactiveVal(0L)

    held_provider_usable <- shiny::reactiveVal(NULL)

    held_connection_valid <- shiny::reactiveVal(NULL)

    owner <- shiny::reactive({
      reference <- authorization()
      if (is.null(reference)) {
        NULL
      } else {
        list(id = reference$id)
      }
    })

    observed_owner <- shiny::reactiveVal(NULL)

    shiny::observeEvent(
      owner(),
      {
        current_owner <- owner()
        if (!identical(observed_owner(), current_owner)) {
          observed_owner(current_owner)
          last_error(NULL)
          other_role_denied(NULL)
          own_table_allowed(NULL)
          other_table_denied(NULL)
          native_scope_denied(NULL)

          native_error_detail(NULL)
          refresh_job <<- NULL
          refreshing(FALSE)
          terminated_pid(NULL)
        }
      },
      ignoreNULL = FALSE,
      priority = 200
    )
    shiny::observeEvent(auth$has_browser_token(), {
      if (
        isTRUE(auth$has_browser_token()) &&
          is.null(authorization()) &&
          shiny::isolate(feedback())$sequence == 0L
      ) {
        notice("Sign in as Alice or Bob to query the database.")
      }
    })

    shiny::observeEvent(input$login, {
      refresh_job <<- NULL
      refreshing(FALSE)
      notice("Opening Keycloak sign-in...")
      reference <- authorization()
      if (is.null(reference)) {
        auth$request_login()
      } else {
        auth$reauthorize()
      }
      invisible(NULL)
    })
    shiny::observeEvent(auth$error, {
      if (!is.null(auth$error) && !identical(auth$error, "logged_out")) {
        notice(
          "Sign-in or token renewal failed. Try signing in again.",
          "danger"
        )
      }
    })
    if (isTRUE(config$playground)) {
      shiny::observeEvent(input$stop_playground, shiny::stopApp())
    }

    shiny::observeEvent(
      input$load,
      {
        last_error(NULL)
        notice("Reading your rows from PostgreSQL...")
      },
      priority = 100
    )

    # Ordinary Shiny reactivity: login/replacement and the reload button read
    # through the native connection accessor. There is no separate result API.
    result <- shiny::reactive({
      input$load
      native <- tryCatch(con(), error = function(e) {
        if (!inherits(e, "shiny.silent.error")) {
          notice(
            "Could not connect to PostgreSQL. Expand Connection details for the database error.",
            "danger"
          )
        }
        stop(e)
      })
      query_attempts(shiny::isolate(query_attempts()) + 1L)
      rows <- tryCatch(
        DBI::dbGetQuery(
          native,
          paste(
            "SELECT current_user::text AS database_user, row_id, owner_name, marker",
            "FROM public.visible_rows ORDER BY row_id"
          )
        ),
        error = function(e) {
          notice(
            "The database read failed. If the connection was broken, reload rows to reconnect.",
            "danger"
          )
          stop(e)
        }
      )
      pid <- DBI::dbGetQuery(
        native,
        "SELECT pg_backend_pid()::integer AS backend_pid"
      )$backend_pid[[1L]]
      held_connection <<- native
      if (!is.null(original_token)) {
        credential_rotated(
          !identical(
            original_token,
            shiny::isolate(authorization()$access_token(
              min_valid_for_seconds = 0
            ))
          )
        )
      }
      held_owner <<- shiny::isolate(owner())
      held_connection_valid(TRUE)
      held_provider_usable(TRUE)
      native_error_detail(NULL)
      notice(
        paste0(
          "Loaded ",
          nrow(rows),
          " rows as ",
          unique(rows$database_user),
          ". Read ",
          shiny::isolate(query_attempts()),
          " completed."
        ),
        "success"
      )
      list(
        database_user = unique(rows$database_user),
        owner_names = unique(rows$owner_name),
        markers = rows$marker,
        backend_pid = pid
      )
    })

    shiny::observeEvent(input$refresh, {
      reference <- authorization()
      shiny::req(reference)
      last_error(NULL)

      shiny::req(!refreshing())
      before <- reference$access_token(min_valid_for = 0)
      job <- new.env(parent = emptyenv())
      refresh_job <<- job
      refreshing(TRUE)
      notice(
        "Refreshing your token in the background. Your existing database connection stays open."
      )
      failed <- function(e) {
        if (session$isClosed() || !identical(refresh_job, job)) {
          return(NULL)
        }
        refreshing(FALSE)
        last_error("credential_refresh_failed")
        notice("Token refresh failed. Try again or sign in again.", "danger")
        NULL
      }
      pending <- tryCatch(
        reference$access_token(
          force_refresh = TRUE,
          min_valid_for = 1,
          async = TRUE
        ),
        error = function(e) {
          failed(e)
          NULL
        }
      )
      if (!is.null(pending)) {
        promises::then(
          pending,
          onFulfilled = function(after) {
            if (session$isClosed() || !identical(refresh_job, job)) {
              return(NULL)
            }
            credential_rotated(!identical(before, after))
            refreshes(shiny::isolate(refreshes()) + 1L)
            refreshing(FALSE)
            notice(
              "Token refreshed. Your database connection was reused.",
              "success"
            )
            NULL
          },
          onRejected = failed
        )
      }
      # Let this session process other inputs while the refresh is pending.
      invisible(NULL)
    })

    shiny::observeEvent(input$request_other_role, {
      reference <- authorization()
      shiny::req(reference)
      credential <- reference$access_token(
        required_scopes = "database.read",
        min_valid_for = 1
      )
      subject <- reference$identity(claims = "sub")$id_token_claims$sub

      # Fixed negative fixture: request the opposite trusted role with this
      # user's valid token. PostgreSQL must independently reject the mismatch.
      other_role <- switch(
        subject,
        "11111111-1111-4111-8111-111111111111" = "bob",
        "22222222-2222-4222-8222-222222222222" = "alice",
        NULL
      )
      shiny::req(other_role)
      role_probe_attempts(shiny::isolate(role_probe_attempts()) + 1L)

      denied <- tryCatch(
        {
          native <- getFromNamespace(
            ".odb_postgres_connect_bearer",
            "shinyOAuthDB"
          )(
            token = credential,
            issuer = config$issuer,
            scope = "database.read",
            host = config$pg_host,
            port = config$pg_port,
            dbname = config$pg_dbname,
            user = other_role,
            sslrootcert = config$ca_file,
            connect_timeout = 5L
          )

          DBI::dbDisconnect(native)

          FALSE
        },

        error = function(e) TRUE
      )

      other_role_denied(denied)
      notice(
        if (denied) {
          "PostgreSQL rejected the other database role, as expected."
        } else {
          "The other database role was accepted. Review the server's identity mapping."
        },
        if (denied) "success" else "danger"
      )
    })

    shiny::observeEvent(input$probe_table_grants, {
      native <- con()
      role <- DBI::dbGetQuery(
        native,
        "SELECT current_user::text AS database_user"
      )$database_user[[1L]]
      shiny::req(role %in% c("alice", "bob"))
      grant_probe_attempts(shiny::isolate(grant_probe_attempts()) + 1L)

      # All statements are trusted fixture constants. Both reads use this same
      # authenticated native connection and the database's own table grants.
      own_statement <- switch(
        role,
        alice = "SELECT marker FROM public.alice_only",
        bob = "SELECT marker FROM public.bob_only"
      )
      other_statement <- switch(
        role,
        alice = "SELECT marker FROM public.bob_only",
        bob = "SELECT marker FROM public.alice_only"
      )

      allowed <- tryCatch(
        {
          rows <- DBI::dbGetQuery(native, own_statement)

          identical(rows$marker, paste0(role, "-grant-only"))
        },

        error = function(e) FALSE
      )

      denied <- tryCatch(
        {
          DBI::dbGetQuery(native, other_statement)

          FALSE
        },

        error = function(e) TRUE
      )

      own_table_allowed(allowed)

      other_table_denied(denied)
      notice(
        if (allowed && denied) {
          "Table access checked: your table is readable; the other account's table is denied."
        } else {
          "The table grants did not match the expected account permissions."
        },
        if (allowed && denied) "success" else "warning"
      )
    })

    shiny::observeEvent(input$probe_native_scope, {
      reference <- authorization()
      shiny::req(reference)

      # Deliberately omit the bridge's database scope check for this negative
      # fixture. PostgreSQL must reject the real browser-issued reduced grant.
      credential <- reference$access_token(min_valid_for = 1)
      subject <- reference$identity(claims = "sub")$id_token_claims$sub
      role <- switch(
        subject,
        "11111111-1111-4111-8111-111111111111" = "alice",
        "22222222-2222-4222-8222-222222222222" = "bob",
        NULL
      )
      shiny::req(role)
      native_scope_probe_attempts(
        shiny::isolate(native_scope_probe_attempts()) + 1L
      )

      denied <- tryCatch(
        {
          native <- getFromNamespace(
            ".odb_postgres_connect_bearer",
            "shinyOAuthDB"
          )(
            token = credential,
            issuer = config$issuer,
            scope = "database.read",
            host = config$pg_host,
            port = config$pg_port,
            dbname = config$pg_dbname,
            user = role,
            sslrootcert = config$ca_file,
            connect_timeout = 5L
          )

          DBI::dbDisconnect(native)

          FALSE
        },

        error = function(e) TRUE
      )

      native_scope_denied(denied)
      notice(
        if (denied) {
          "PostgreSQL rejected this token for database.read."
        } else {
          "PostgreSQL accepted this token for database.read."
        },
        if (denied) "warning" else "success"
      )
    })

    shiny::observeEvent(input$fail_refresh, {
      reference <- shiny::req(authorization())
      subject <- reference$identity(claims = "sub")$id_token_claims$sub
      admin <- httr2::request(
        "https://localhost:18443/realms/master/protocol/openid-connect/token"
      ) |>
        httr2::req_body_form(
          grant_type = "password",
          client_id = "admin-cli",
          username = "fixture-admin",
          password = "fixture-admin-password"
        ) |>
        httr2::req_perform() |>
        httr2::resp_body_json()
      httr2::request(paste0(
        "https://localhost:18443/admin/realms/shinyoauthdb/users/",
        subject,
        "/logout"
      )) |>
        httr2::req_auth_bearer_token(admin$access_token) |>
        httr2::req_method("POST") |>
        httr2::req_perform()
      refresh_rejected(tryCatch(
        {
          reference$access_token(force_refresh = TRUE, async = FALSE)
          FALSE
        },
        error = function(e) TRUE
      ))
      tryCatch(con(), error = function(e) NULL)
      held_connection_valid(
        if (is.null(held_connection)) FALSE else DBI::dbIsValid(held_connection)
      )
      held_provider_usable(tryCatch(
        {
          held_provider()
          TRUE
        },
        error = function(e) FALSE
      ))
    })

    shiny::observeEvent(input$logout, {
      refresh_job <<- NULL
      refreshing(FALSE)
      auth$logout()
      # Observe retirement before inspecting the intentionally retained fixture
      # connection. Production output simply calls con() in its render code.
      tryCatch(con(), error = function(e) NULL)

      held_provider_usable(
        if (is.null(held_provider)) {
          NULL
        } else {
          tryCatch(
            {
              held_provider()

              TRUE
            },

            error = function(e) FALSE
          )
        }
      )

      held_connection_valid(
        if (is.null(held_connection)) {
          NULL
        } else {
          suppressWarnings(tryCatch(
            DBI::dbIsValid(held_connection),
            error = function(e) FALSE
          ))
        }
      )

      last_error(NULL)
      notice("Signed out. Your database connection is closed.", "success")
    })

    shiny::observeEvent(input$reset_backend, {
      saved <- result()
      shiny::req(saved, saved$backend_pid)

      tryCatch(
        {
          admin <- DBI::dbConnect(
            RPostgres::Postgres(),
            host = config$pg_host,
            port = config$pg_port,
            dbname = config$pg_dbname,
            user = "postgres",
            password = config$admin_password,
            sslmode = "verify-full",
            sslrootcert = config$ca_file,
            connect_timeout = 5L
          )

          on.exit(DBI::dbDisconnect(admin), add = TRUE)
          terminated <- DBI::dbGetQuery(
            admin,
            "SELECT pg_terminate_backend($1)::boolean AS terminated",
            params = list(saved$backend_pid)
          )
          if (!isTRUE(terminated$terminated[[1L]])) {
            stop("Fixture backend was unavailable.")
          }

          reset_count(shiny::isolate(reset_count()) + 1L)
          terminated_pid(saved$backend_pid)
          notice(
            "Database connection terminated. Reload rows to detect the failure, then reload again to reconnect.",
            "warning"
          )
        },

        error = function(e) {
          last_error("fixture_backend_reset_failed")
          notice(
            "Could not terminate the database connection. Reload rows and try again.",
            "danger"
          )
        }
      )
    })

    shiny::observeEvent(input$retry_native, {
      shiny::req(held_connection, identical(held_owner, owner()))
      # These direct native calls deliberately bypass the broker's reconnection
      # path. The second call exercises RPostgres/libpq recovery after the first
      # detects the terminated socket, with no credential hook left installed.
      failures <- 0L

      for (attempt in seq_len(2L)) {
        failed <- tryCatch(
          {
            DBI::dbGetQuery(
              held_connection,
              "SELECT current_user::text AS database_user"
            )

            FALSE
          },

          error = function(e) TRUE
        )

        failures <- failures + as.integer(failed)
      }

      held_query_failures(shiny::isolate(held_query_failures()) + failures)

      last_error(
        if (failures == 2L) {
          "held_native_query_failed"
        } else {
          "unexpected_native_recovery"
        }
      )
      notice(
        if (failures == 2L) {
          "The old connection failed both reads, as expected. Reload rows to open a fresh connection."
        } else {
          "The old connection still accepts queries. Break it first to test recovery."
        },
        if (failures == 2L) "success" else "info"
      )
    })

    output$rows <- shiny::renderTable({
      saved <- tryCatch(result(), error = function(e) NULL)
      shiny::req(saved)
      data.frame(
        "Database role" = saved$database_user,
        Owner = saved$owner_names,
        "Row value" = saved$markers,
        check.names = FALSE
      )
    })

    state <- shiny::reactive({
      current_owner <- owner()
      query_error <- NULL
      saved <- tryCatch(
        result(),
        shiny.silent.error = function(e) NULL,
        error = function(e) {
          query_error <<- "database_operation_failed"
          NULL
        }
      )

      list(
        ready = isTRUE(auth$has_browser_token()),
        authorized = !is.null(current_owner),
        authorization_id = if (is.null(current_owner)) {
          NULL
        } else {
          current_owner$id
        },
        database_status = if (is.null(current_owner)) {
          "waiting_for_authorization"
        } else {
          if (isTRUE(authorization()$has_scopes("database.read"))) {
            "authorized"
          } else {
            "insufficient_scope"
          }
        },
        auth_error = if (is.null(auth$error)) {
          NULL
        } else {
          "authorization_failed"
        },
        error = if (is.null(last_error())) query_error else last_error(),
        result = saved,
        native_error_detail = native_error_detail(),
        native_checks = negative_results(),
        dbplyr_checks = dbplyr_checks(),
        original_expired = !is.null(original_expiry) &&
          as.numeric(Sys.time()) > original_expiry + 1,
        expired_denied = expired_denied(),
        query_attempts = query_attempts(),
        connect_attempts = connect_attempts(),
        successful_connections = successful_connections(),
        disconnects = disconnects(),
        refreshes = refreshes(),
        credential_rotated = credential_rotated(),
        refresh_rejected = refresh_rejected(),
        held_provider_usable = held_provider_usable(),
        held_connection_valid = held_connection_valid(),
        reset_count = reset_count(),
        terminated_pid = terminated_pid(),
        refreshing = refreshing(),
        action_message = feedback()$text,
        signed_in_as = if (is.null(current_owner)) {
          NULL
        } else {
          tryCatch(database_role(), error = function(e) NULL)
        },
        held_query_failures = held_query_failures(),
        role_probe_attempts = role_probe_attempts(),
        other_role_denied = other_role_denied(),
        grant_probe_attempts = grant_probe_attempts(),
        own_table_allowed = own_table_allowed(),
        other_table_denied = other_table_denied(),
        native_scope_probe_attempts = native_scope_probe_attempts(),
        native_scope_denied = native_scope_denied(),
        hook_restored = with(
          getFromNamespace(".odb_postgres_runtime", "shinyOAuthDB")(),
          !isTRUE(active) && isTRUE(default_hook) && isTRUE(same_libpq)
        )
      )
    })

    output$snapshot <- shiny::renderText(jsonlite::toJSON(
      state(),
      auto_unbox = TRUE,
      null = "null"
    ))
    shiny::outputOptions(output, "snapshot", suspendWhenHidden = FALSE)

    output$action_status <- shiny::renderUI({
      value <- feedback()
      shiny::div(
        class = paste("alert", paste0("alert-", value$kind)),
        `data-action-sequence` = value$sequence,
        value$text
      )
    })
    fields <- function(...) {
      entries <- list(...)
      shiny::tags$dl(lapply(names(entries), function(label) {
        shiny::tagList(
          shiny::tags$dt(label),
          shiny::tags$dd(entries[[label]])
        )
      }))
    }
    output$session_status <- shiny::renderUI({
      value <- state()
      fields(
        "Signed in as" = if (is.null(value$signed_in_as)) {
          "Not signed in"
        } else {
          value$signed_in_as
        },
        "Database permission" = if (!value$authorized) {
          "Sign-in required"
        } else if (value$database_status == "authorized") {
          "database.read granted"
        } else {
          "database.read missing"
        },
        "Token refresh" = if (value$refreshing) "In progress" else "Ready",
        "Completed refreshes" = value$refreshes
      )
    })
    output$data_status <- shiny::renderUI({
      value <- state()
      if (!value$authorized) {
        return(shiny::p(
          "Sign in to see the rows available to your database role."
        ))
      }
      if (value$database_status == "insufficient_scope") {
        return(shiny::p(
          "This sign-in is missing database.read. Authorize an account with database access."
        ))
      }
      if (!is.null(value$error) && is.null(value$result)) {
        return(shiny::div(
          class = "alert alert-warning",
          "No rows loaded. Reload rows to retry using the current sign-in."
        ))
      }
      if (is.null(value$result)) {
        return(shiny::p("Loading your database rows..."))
      }
      shiny::p(paste0(
        "Showing ",
        length(value$result$markers),
        " rows for ",
        value$result$database_user,
        ". Row-level security runs inside PostgreSQL."
      ))
    })
    output$connection_status <- shiny::renderUI({
      value <- state()
      fields(
        "Database" = config$pg_dbname,
        "Backend process" = if (is.null(value$result)) {
          "No successful read"
        } else {
          value$result$backend_pid
        },
        "Read attempts" = value$query_attempts,
        "Connections opened" = value$successful_connections,
        "Connections closed" = value$disconnects,
        "Token hook" = if (value$hook_restored) {
          "Restored after connection opening"
        } else {
          "Not restored"
        },
        "Authorization ID" = if (is.null(value$authorization_id)) {
          "None"
        } else {
          shiny::tags$code(value$authorization_id)
        },
        "Last database error" = if (is.null(value$native_error_detail)) {
          "None"
        } else {
          value$native_error_detail
        }
      )
    })
    output$role_status <- shiny::renderText({
      value <- state()$other_role_denied
      if (is.null(value)) {
        "Not checked yet."
      } else if (value) {
        "The other role was rejected. Your token can only authenticate your mapped role."
      } else {
        "The other role was accepted. Review the database identity mapping."
      }
    })
    output$grants_status <- shiny::renderText({
      value <- state()
      if (is.null(value$own_table_allowed)) {
        "Not checked yet."
      } else {
        paste0(
          "Your private table: ",
          if (value$own_table_allowed) "readable" else "denied",
          ". Other account's table: ",
          if (value$other_table_denied) "denied" else "readable",
          "."
        )
      }
    })
    output$scope_status <- shiny::renderText({
      value <- state()$native_scope_denied
      if (is.null(value)) {
        "Not checked yet."
      } else if (value) {
        "PostgreSQL rejected this token for database.read."
      } else {
        "PostgreSQL accepted this token for database.read."
      }
    })
    output$recovery_status <- shiny::renderText({
      value <- state()
      if (is.null(value$terminated_pid)) {
        "The current connection has not been deliberately broken."
      } else if (
        !is.null(value$result) &&
          value$result$backend_pid != value$terminated_pid
      ) {
        "Reconnected successfully with a fresh database connection."
      } else if (value$held_query_failures >= 2L) {
        "Both reads on the old connection failed. Reload rows to reconnect."
      } else {
        "The connection was terminated. Reload rows to detect the failure."
      }
    })
    shiny::observe(
      {
        value <- state()
        feedback()
        usable <- value$authorized &&
          value$database_status == "authorized" &&
          !value$refreshing
        session$sendCustomMessage(
          "postgres.controls",
          list(
            signed_in = value$authorized,
            enabled = list(
              login = value$ready && !value$refreshing,
              logout = value$authorized,
              load = usable,
              refresh = value$authorized && !value$refreshing,
              request_other_role = usable,
              probe_table_grants = usable,
              probe_native_scope = value$authorized && !value$refreshing,
              reset_backend = usable && !is.null(value$result),
              retry_native = usable &&
                !is.null(held_connection) &&
                identical(held_owner, owner()) &&
                !is.null(value$terminated_pid) &&
                (is.null(value$result) ||
                  identical(value$result$backend_pid, value$terminated_pid)),
              stop_playground = isTRUE(config$playground)
            )
          )
        )
      },
      priority = -100
    )
  }

  shiny::shinyApp(ui, server, uiPattern = ".*")
}

postgres_browser_run_app <- function(config) {
  mirai::daemons(2L)
  on.exit(mirai::daemons(0L), add = TRUE)
  shiny::runApp(
    postgres_browser_app(config),
    host = "0.0.0.0",
    port = as.integer(httr2::url_parse(config$origin)$port),
    launch.browser = FALSE,
    quiet = TRUE
  )
}
