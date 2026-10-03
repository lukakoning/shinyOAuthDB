# Integration-only Shiny app: genuine OAuth code flow and PostgreSQL OAUTHBEARER.
# pgBearerHook is a test fixture for libpq's native OAuth hook, not package code.

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
  base <- shiny::fluidPage(
    shiny::h3("Local PostgreSQL OAuth integration fixture"),
    shiny::actionButton("login", "Authorize database user"),
    shiny::actionButton("load", "Load granted rows"),
    shiny::actionButton("refresh", "Refresh current credential"),
    shiny::actionButton("request_other_role", "Probe the other fixture role"),
    shiny::actionButton("probe_table_grants", "Probe fixture table grants"),
    shiny::actionButton(
      "probe_native_scope",
      "Probe PostgreSQL scope validation"
    ),
    shiny::actionButton("logout", "Logout"),
    shiny::actionButton("reset_backend", "Terminate fixture backend"),
    shiny::actionButton("retry_native", "Retry held native connection"),
    shiny::verbatimTextOutput("snapshot")
  )
  ui <- shinyOAuth::oauth_ui(base, id = "auth", client = client)

  server <- function(input, output, session) {
    auth <- shinyOAuth::oauth_module_server(
      "auth",
      client,
      auto_redirect = FALSE,
      refresh_proactively = FALSE
    )

    authorization <- shiny::reactive(auth$connection())

    connect_attempts <- shiny::reactiveVal(0L)

    successful_connections <- shiny::reactiveVal(0L)

    disconnects <- shiny::reactiveVal(0L)

    native_error_detail <- shiny::reactiveVal(NULL)

    source <- shinyOAuthDB::oauth_db_custom(
      "postgres_oauth_fixture",
      target = NULL,
      scopes = "database.read",
      required_scopes = "database.read",
      config = list(
        issuer = config$issuer,
        host = config$pg_host,
        port = config$pg_port,
        dbname = config$pg_dbname,
        sslrootcert = config$ca_file
      ),
      capabilities = list(
        connector_package = "pgBearerHook",
        delegated_user = TRUE,
        credential_transport = "native_oauthbearer"
      ),
      connect = function(config, token_provider) {
        tryCatch(
          {
            credential <- token_provider()
            reference <- shiny::isolate(authorization())
            identity <- reference$identity(claims = "sub")
            subject <- identity$id_token_claims$sub
            role <- c(
              "11111111-1111-4111-8111-111111111111" = "alice",
              "22222222-2222-4222-8222-222222222222" = "bob"
            )[[subject]]
            if (is.null(role)) {
              stop(
                "The validated fixture identity has no database role.",
                call. = FALSE
              )
            }

            connect_attempts(shiny::isolate(connect_attempts()) + 1L)
            native <- pgBearerHook::pg_connect_bearer(
              token = credential,
              issuer = config$issuer,
              scope = "database.read",
              host = config$host,
              port = config$port,
              dbname = config$dbname,
              user = role,
              sslmode = "verify-full",
              sslrootcert = config$sslrootcert,
              connect_timeout = 5L
            )

            successful_connections(
              shiny::isolate(successful_connections()) + 1L
            )

            native
          },

          error = function(e) {
            native_error_detail(postgres_fixture_error_detail(e))

            stop(e)
          }
        )
      },

      disconnect = function(native) {
        disconnects(shiny::isolate(disconnects()) + 1L)

        DBI::dbDisconnect(native)
      }
    )

    db <- shinyOAuthDB::oauth_db_session(
      source,
      authorization = authorization,
      session = session,
      connection_policy = "session",
      min_valid_for = 1
    )

    result <- shiny::reactiveVal(NULL)

    result_owner <- shiny::reactiveVal(NULL)

    last_error <- shiny::reactiveVal(NULL)

    query_attempts <- shiny::reactiveVal(0L)

    refreshes <- shiny::reactiveVal(0L)

    credential_rotated <- shiny::reactiveVal(FALSE)

    reset_count <- shiny::reactiveVal(0L)

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
        list(id = reference$id, generation = db$generation())
      }
    })

    observed_owner <- shiny::reactiveVal(NULL)

    shiny::observeEvent(
      owner(),
      {
        current_owner <- owner()
        if (!identical(observed_owner(), current_owner)) {
          observed_owner(current_owner)
          result(NULL)
          result_owner(NULL)
          last_error(NULL)
          other_role_denied(NULL)
          own_table_allowed(NULL)
          other_table_denied(NULL)
          native_scope_denied(NULL)

          native_error_detail(NULL)
        }
      },
      ignoreNULL = FALSE,
      priority = 200
    )

    shiny::observeEvent(input$login, auth$request_login())

    shiny::observeEvent(input$load, {
      captured <- owner()
      shiny::req(captured)
      query_attempts(shiny::isolate(query_attempts()) + 1L)
      last_error(NULL)
      result(NULL)

      tryCatch(
        {
          native <- db$connection()
          rows <- DBI::dbGetQuery(
            native,
            paste(
              "SELECT current_user::text AS database_user, row_id, owner_name, marker",
              "FROM public.visible_rows ORDER BY row_id"
            )
          )
          pid <- DBI::dbGetQuery(
            native,
            "SELECT pg_backend_pid()::integer AS backend_pid"
          )$backend_pid[[1L]]
          if (identical(captured, owner())) {
            held_connection <<- native
            held_owner <<- captured
            held_provider <<- db$token_provider()
            held_connection_valid(TRUE)
            held_provider_usable(TRUE)
            result_owner(captured)

            result(list(
              database_user = unique(rows$database_user),
              owner_names = unique(rows$owner_name),
              markers = rows$marker,
              backend_pid = pid
            ))
          }
        },

        error = function(e) {
          if (identical(captured, owner())) {
            last_error("database_operation_failed")
          }
        }
      )
    })

    shiny::observeEvent(input$refresh, {
      reference <- authorization()
      shiny::req(reference)
      last_error(NULL)

      tryCatch(
        {
          before <- reference$access_token(min_valid_for = 1)
          after <- reference$access_token(
            force_refresh = TRUE,
            min_valid_for = 1
          )
          credential_rotated(!identical(before, after))

          refreshes(shiny::isolate(refreshes()) + 1L)
        },

        error = function(e) last_error("credential_refresh_failed")
      )
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
          native <- pgBearerHook::pg_connect_bearer(
            token = credential,
            issuer = config$issuer,
            scope = "database.read",
            host = config$pg_host,
            port = config$pg_port,
            dbname = config$pg_dbname,
            user = other_role,
            sslmode = "verify-full",
            sslrootcert = config$ca_file,
            connect_timeout = 5L
          )

          DBI::dbDisconnect(native)

          FALSE
        },

        error = function(e) TRUE
      )

      other_role_denied(denied)
    })

    shiny::observeEvent(input$probe_table_grants, {
      native <- db$connection()
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
          native <- pgBearerHook::pg_connect_bearer(
            token = credential,
            issuer = config$issuer,
            scope = "database.read",
            host = config$pg_host,
            port = config$pg_port,
            dbname = config$pg_dbname,
            user = role,
            sslmode = "verify-full",
            sslrootcert = config$ca_file,
            connect_timeout = 5L
          )

          DBI::dbDisconnect(native)

          FALSE
        },

        error = function(e) TRUE
      )

      native_scope_denied(denied)
    })

    shiny::observeEvent(input$logout, {
      auth$logout()

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

      result(NULL)
      result_owner(NULL)

      last_error(NULL)
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
        },

        error = function(e) last_error("fixture_backend_reset_failed")
      )
    })

    shiny::observeEvent(input$retry_native, {
      shiny::req(held_connection, identical(held_owner, owner()))
      result(NULL)

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
    })

    output$snapshot <- shiny::renderText({
      current_owner <- owner()
      saved <- result()
      if (!identical(result_owner(), current_owner)) {
        saved <- NULL
      }

      jsonlite::toJSON(
        list(
          ready = isTRUE(auth$has_browser_token()),
          authorized = !is.null(current_owner),
          authorization_id = if (is.null(current_owner)) {
            NULL
          } else {
            current_owner$id
          },
          generation = db$generation(),
          database_status = db$status()$status,
          auth_error = if (is.null(auth$error)) {
            NULL
          } else {
            "authorization_failed"
          },
          error = last_error(),
          result = saved,
          native_error_detail = native_error_detail(),
          query_attempts = query_attempts(),
          connect_attempts = connect_attempts(),
          successful_connections = successful_connections(),
          disconnects = disconnects(),
          refreshes = refreshes(),
          credential_rotated = credential_rotated(),
          held_provider_usable = held_provider_usable(),
          held_connection_valid = held_connection_valid(),
          reset_count = reset_count(),
          held_query_failures = held_query_failures(),
          role_probe_attempts = role_probe_attempts(),
          other_role_denied = other_role_denied(),
          grant_probe_attempts = grant_probe_attempts(),
          own_table_allowed = own_table_allowed(),
          other_table_denied = other_table_denied(),
          native_scope_probe_attempts = native_scope_probe_attempts(),
          native_scope_denied = native_scope_denied(),
          hook_restored = with(
            pgBearerHook::pg_bearer_runtime(),
            !isTRUE(active) && isTRUE(default_hook) && isTRUE(same_libpq)
          )
        ),
        auto_unbox = TRUE,
        null = "null"
      )
    })
  }

  shiny::shinyApp(ui, server, uiPattern = ".*")
}

postgres_browser_run_app <- function(config) {
  shiny::runApp(
    postgres_browser_app(config),
    host = "0.0.0.0",
    port = as.integer(httr2::url_parse(config$origin)$port),
    launch.browser = FALSE,
    quiet = TRUE
  )
}
