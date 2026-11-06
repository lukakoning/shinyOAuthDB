fixture_run_app <- function(config) {
  source(file.path("integration", paste0(config$backend, "-keycloak"), "backend.R"), local = TRUE)
  spec <- fixture_backend
  options(shinyOAuth.allowed_hosts = c("localhost", "127.0.0.1", "::1"))
  provider <- shinyOAuth::oauth_provider_oidc_discover(config$issuer,
    token_auth_style = "body", id_token_validation = TRUE)
  provider@par_url <- NA_character_
  provider@extra_auth_params <- list(prompt = "login")
  client <- shinyOAuth::oauth_client(provider, client_id = config$client_id,
    client_secret = "", redirect_uri = paste0(config$origin, "/callback"),
    scopes = c("openid", "profile", if (config$client_id != "shiny-missing-scope") "database.read"),
    required_scopes = "openid")
  ui <- shinyOAuth::oauth_ui(shiny::fluidPage(
    shiny::tags$h1(paste(config$backend, "local integration fixture")),
    shiny::actionButton("login", "Sign in"), shiny::actionButton("logout", "Sign out"),
    shiny::actionButton("load", "Read rows"), shiny::actionButton("refresh", "Refresh token"),
    shiny::actionButton("probe", "Check denied access"),
    shiny::actionButton("tamper", "Check modified token"),
    shiny::actionButton("expired", "Check expired token"),
    shiny::actionButton("tls", "Check TLS rejection"),
    shiny::actionButton("data", "Check values"),
    shiny::actionButton("break_connection", "Close native connection"),
    shiny::actionButton("end", "End session"),
    shiny::tableOutput("rows"), shiny::verbatimTextOutput("snapshot")
  ), id = "auth", client = client)
  server <- function(input, output, session) {
    request_baseline <- if (is.function(spec$request_count)) spec$request_count() else NULL
    auth <- shinyOAuth::oauth_module_server("auth", client,
      auto_redirect = FALSE, async = FALSE, refresh_proactively = FALSE)
    username <- function() {
      reference <- shiny::req(auth$connection())
      shiny::req(reference$identity(claims = "preferred_username")$id_token_claims$preferred_username)
    }
    native <- spec$bind(auth$connection, username, config)
    calls <- shiny::reactiveVal(0L)
    read_attempts <- shiny::reactiveVal(0L)
    refresh_failed <- shiny::reactiveVal(NULL)
    held_usable <- shiny::reactiveVal(NULL)
    refreshes <- shiny::reactiveVal(0L)
    rotated <- shiny::reactiveVal(FALSE)
    denied <- shiny::reactiveVal(NULL)
    tampered <- shiny::reactiveVal(NULL)
    expired_denied <- shiny::reactiveVal(NULL)
    tls_checks <- shiny::reactiveVal(NULL)
    data_checks <- shiny::reactiveVal(NULL)
    data_error <- shiny::reactiveVal(NULL)
    broken <- shiny::reactiveVal(FALSE)
    held <- NULL
    previous <- NULL
    openings <- shiny::reactiveVal(0L)
    old_bearer <- NULL
    old_expiry <- NULL
    old_username <- NULL
    owner_id <- NULL
    result <- shiny::reactive({
      input$load
      reference <- shiny::req(auth$connection())
      value <- native()
      if (!identical(owner_id, reference$id)) {
        owner_id <<- reference$id
        old_bearer <<- reference$access_token(min_valid_for_seconds = 0)
        old_username <<- username()
        segment <- strsplit(old_bearer, ".", fixed = TRUE)[[1L]][[2L]]
        segment <- chartr("-_", "+/", segment)
        segment <- paste0(segment, strrep("=", (4L - nchar(segment) %% 4L) %% 4L))
        old_expiry <<- jsonlite::fromJSON(rawToChar(openssl::base64_decode(segment)))$exp
      }
      if (!identical(value, previous)) {
        openings(shiny::isolate(openings()) + 1L)
        previous <<- value
      }
      held <<- value
      read_attempts(shiny::isolate(read_attempts()) + 1L)
      rows <- spec$read(value)
      calls(shiny::isolate(calls()) + 1L)
      rows
    })
    shiny::observeEvent(input$login, {
      if (is.null(auth$connection())) auth$request_login() else auth$reauthorize()
    })
    shiny::observeEvent(input$logout, auth$logout())
    shiny::observeEvent(input$refresh, {
      reference <- shiny::req(auth$connection())
      before <- reference$access_token(min_valid_for_seconds = 0)
      after <- reference$access_token(force_refresh = TRUE, min_valid_for_seconds = 1)
      rotated(!identical(before, after))
      refreshes(shiny::isolate(refreshes()) + 1L)
    })
    shiny::observeEvent(input$fail_refresh, {
      reference <- shiny::req(auth$connection())
      subject <- reference$identity(claims = "sub")$id_token_claims$sub
      # Administrative control is confined to this disposable Keycloak realm.
      admin <- httr2::request("https://localhost:18443/realms/master/protocol/openid-connect/token") |>
        httr2::req_body_form(grant_type = "password", client_id = "admin-cli",
          username = "fixture-admin", password = "fixture-admin-password") |>
        httr2::req_perform() |> httr2::resp_body_json()
      httr2::request(paste0("https://localhost:18443/admin/realms/shinyoauthdb/users/", subject, "/logout")) |>
        httr2::req_auth_bearer_token(admin$access_token) |>
        httr2::req_method("POST") |> httr2::req_perform()
      failed <- tryCatch({ reference$access_token(force_refresh = TRUE); FALSE }, error = function(e) TRUE)
      refresh_failed(failed)
      held_usable(tryCatch({ spec$read(held); TRUE }, error = function(e) FALSE))
    })
    shiny::observeEvent(input$probe, {
      checks <- spec$denied(native(), username(), config)
      if (is.function(spec$credential_checks)) {
        bearer <- auth$connection()$access_token(min_valid_for_seconds = 1)
        checks <- c(list(table_access = checks), spec$credential_checks(bearer, username(), config))
      }
      denied(checks)
    })
    shiny::observeEvent(input$tamper, {
      bearer <- shiny::req(auth$connection())$access_token(min_valid_for_seconds = 1)
      pieces <- strsplit(bearer, ".", fixed = TRUE)[[1L]]
      first <- substr(pieces[[3L]], 1L, 1L)
      pieces[[3L]] <- paste0(if (first == "A") "B" else "A", substring(pieces[[3L]], 2L))
      tampered(spec$token_denied(paste(pieces, collapse = "."), username(), config))
    })
    shiny::observeEvent(input$expired, {
      shiny::req(!is.null(old_expiry), as.numeric(Sys.time()) > old_expiry + 2)
      expired_denied(spec$token_denied(old_bearer, old_username, config))
    })
    shiny::observeEvent(input$tls, {
      if (is.function(spec$tls_checks)) {
        checks <- spec$tls_checks(auth$connection, username, config)
      } else {
        control <- function() httr2::resp_body_json(httr2::req_perform(httr2::request("https://localhost:18447")))
        before <- control()
        checks <- list()
        for (name in c("untrusted_ca", "wrong_hostname")) {
          bad <- config
          bad$port <- if (name == "untrusted_ca") 18445L else 18446L
          error <- tryCatch(spec$read(spec$bind(auth$connection, username, bad)()), error = identity)
          after <- control()
          expected <- if (config$backend == "postgrest") inherits(error, "shinyOAuthDB_request_failed") else
            inherits(error, "error") && grepl("SSL|TLS|certificate", conditionMessage(error), ignore.case = TRUE)
          checks[[name]] <- expected && identical(before[[name]], after[[name]])
        }
      }
      tls_checks(checks)
    })
    shiny::observeEvent(input$data, {
      data_error(NULL)
      checks <- tryCatch(spec$data_checks(native(), username(), config),
        error = function(e) {
          detail <- gsub("eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+",
            "[redacted credential]", conditionMessage(e))
          detail <- gsub("https?://[^[:space:]]+", "[configured endpoint]", detail)
          data_error(substr(detail, 1L, 1000L))
          list(operation_succeeded = FALSE)
        })
      data_checks(checks)
    })
    shiny::observeEvent(input$break_connection, {
      shiny::req(spec$dbi)
      DBI::dbDisconnect(native())
      broken(TRUE)
    })
    shiny::observeEvent(input$end, session$close())
    session$onSessionEnded(function() {
      usable <- shiny::withReactiveDomain(session,
        shiny::isolate(tryCatch({ spec$read(native()); TRUE }, error = function(e) FALSE)))
      jsonlite::write_json(list(authorization_id = owner_id, accessor_usable = usable,
        native_valid = if (inherits(held, "DBIConnection")) DBI::dbIsValid(held) else NULL),
        config$ended, auto_unbox = TRUE)
    })
    output$rows <- shiny::renderTable(result())
    output$snapshot <- shiny::renderText({
      reference <- auth$connection()
      failure <- NULL
      rows <- tryCatch(result(), error = function(e) {
        if (!inherits(e, "shiny.silent.error")) failure <<- "backend_operation_failed"
        NULL
      })
      jsonlite::toJSON(list(ready = isTRUE(auth$has_browser_token()), authorized = !is.null(reference),
        authorization_id = if (!is.null(reference)) reference$id else NULL,
        auth_error = if (is.null(auth$error)) NULL else "authorization_failed",
        result = rows, error = failure, calls = calls(), read_attempts = read_attempts(),
        remote_read_attempts = if (is.null(request_baseline)) NULL else spec$request_count() - request_baseline,
        openings = openings(),
        refresh_failed = refresh_failed(), held_usable = held_usable(),
        refreshes = refreshes(), rotated = rotated(), denied = denied(), tampered_denied = tampered(),
        expired_denied = expired_denied(), original_expiry = old_expiry,
        tls_checks = tls_checks(), data_checks = data_checks(), data_error = data_error(), broken = broken(),
        held_valid = if (inherits(held, "DBIConnection")) DBI::dbIsValid(held) else NULL),
        auto_unbox = TRUE, null = "null", dataframe = "rows")
    })
    shiny::outputOptions(output, "snapshot", suspendWhenHidden = FALSE)
  }
  shiny::runApp(shiny::shinyApp(ui, server, uiPattern = ".*"),
    port = 18100L, host = "127.0.0.1", launch.browser = FALSE)
}
