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
    shiny::actionButton("end", "End session"),
    shiny::tableOutput("rows"), shiny::verbatimTextOutput("snapshot")
  ), id = "auth", client = client)
  server <- function(input, output, session) {
    auth <- shinyOAuth::oauth_module_server("auth", client,
      auto_redirect = FALSE, async = FALSE, refresh_proactively = FALSE)
    username <- function() {
      reference <- shiny::req(auth$connection())
      shiny::req(reference$identity(claims = "preferred_username")$id_token_claims$preferred_username)
    }
    native <- spec$bind(auth$connection, username, config)
    calls <- shiny::reactiveVal(0L)
    refreshes <- shiny::reactiveVal(0L)
    rotated <- shiny::reactiveVal(FALSE)
    denied <- shiny::reactiveVal(NULL)
    tampered <- shiny::reactiveVal(NULL)
    expired_denied <- shiny::reactiveVal(NULL)
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
    shiny::observeEvent(input$probe, {
      denied(spec$denied(native(), username(), config))
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
    shiny::observeEvent(input$end, session$close())
    session$onSessionEnded(function() {
      usable <- shiny::withReactiveDomain(session,
        shiny::isolate(tryCatch({ spec$read(native()); TRUE }, error = function(e) FALSE)))
      jsonlite::write_json(list(accessor_usable = usable,
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
        result = rows, error = failure, calls = calls(), openings = openings(),
        refreshes = refreshes(), rotated = rotated(), denied = denied(), tampered_denied = tampered(),
        expired_denied = expired_denied(), original_expiry = old_expiry,
        held_valid = if (inherits(held, "DBIConnection")) DBI::dbIsValid(held) else NULL),
        auto_unbox = TRUE, null = "null", dataframe = "rows")
    })
    shiny::outputOptions(output, "snapshot", suspendWhenHidden = FALSE)
  }
  shiny::runApp(shiny::shinyApp(ui, server, uiPattern = ".*"),
    port = 18100L, host = "127.0.0.1", launch.browser = FALSE)
}
