.odb_cloud_specs <- function() list(fabric = .odb_cloud_spec_fabric())

.odb_cloud_field <- function(label, help, type = "text", default = NULL) {
  list(label = label, help = help, type = type, default = default)
}

.odb_cloud_check_marker <- function(path, platform) {
  marker <- file.path(path, ".shinyOAuthDB-cloud-demo")
  if (file.exists(marker) && !identical(readLines(marker, warn = FALSE), platform)) {
    cli::cli_abort("This directory belongs to another platform. Resume with that platform name or choose a new {.arg path}.")
  }
}

.odb_cloud_platform_demo <- function(platform, supplied, path, port, action, prompt, launch_browser) {
  spec <- .odb_cloud_specs()[[platform]]
  for (flag in list(prompt, launch_browser)) {
    if (!is.logical(flag) || length(flag) != 1L || is.na(flag)) cli::cli_abort("{.arg prompt} and {.arg launch_browser} must be TRUE or FALSE.")
  }
  if (prompt && !.odb_cloud_interactive()) cli::cli_abort("Interactive setup needs an R console. Use {.code prompt = FALSE} in scripts.")
  if (is.null(path)) path <- tempfile(paste0("shinyOAuthDB-", platform, "-"))
  .odb_string(path, "path")
  marker <- file.path(path, ".shinyOAuthDB-cloud-demo")
  if (dir.exists(path) && !file.exists(marker) && length(list.files(path, all.files = TRUE, no.. = TRUE))) {
    cli::cli_abort("{.arg path} must be empty or contain a shinyOAuthDB cloud demo.")
  }
  .odb_cloud_check_marker(path, platform)
  .odb_named_args(supplied, "Platform settings")
  if (!is.null(supplied$host) && "server" %in% names(spec$fields)) {
    if (!is.null(supplied$server)) cli::cli_abort("Supply only one of {.arg host} and {.arg server}.")
    supplied$server <- supplied$host
    supplied$host <- NULL
  }
  allowed <- c(names(spec$fields), "client_id", "client_type", "port")
  if (length(setdiff(names(supplied), allowed))) cli::cli_abort("Unknown {spec$title} settings: {.field {setdiff(names(supplied), allowed)}}.")
  config <- .odb_cloud_load(path)
  context <- intersect(c("server", "tenant_id", "issuer", "url", "project", "resource", "scope", "role"), names(supplied))
  changed <- any(vapply(context, function(name) !is.null(config[[name]]) &&
    !identical(.odb_cloud_value(supplied[[name]], spec$fields[[name]]$type), config[[name]]), logical(1)))
  if (changed) config$client_id <- config$client_type <- NULL
  for (name in names(supplied)) config[[name]] <- supplied[[name]]
  if (!is.null(port)) config$port <- port
  prefix <- paste0("OAUTHDB_", toupper(gsub("-", "_", platform)))
  for (name in c(names(spec$fields), "client_id")) {
    if (is.null(config[[name]])) config[[name]] <- .odb_cloud_env(paste0(prefix, "_", toupper(name)))
  }
  config <- .odb_cloud_platform_validate(config, spec)
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  cli::cli_h1("{spec$title} Shiny demo")
  cli::cli_text("{spec$purpose}")
  cli::cli_text("No account yet? Setup and trial information: {.url {spec$account_url}}. You can save a draft while arranging access.")
  if (action == "start" && prompt) {
    .odb_cloud_port_available(config$port)
    config <- .odb_cloud_platform_collect(config, spec, platform, path)
  }
  paused <- isTRUE(attr(config, "paused"))
  attr(config, "paused") <- NULL
  if (!paused && action == "start" && is.null(config$client_type)) config$client_type <- spec$client_types[[1L]]
  .odb_cloud_save(config, path, platform)
  .odb_cloud_files(path, platform)
  if (action == "files") {
    cli::cli_alert_success("Editable draft: {.path {path}}")
    return(invisible(path))
  }
  missing <- spec$required[vapply(spec$required, function(name) is.null(config[[name]]), logical(1))]
  if (length(missing) || paused) {
    .odb_cloud_platform_help(spec, config)
    .odb_cloud_resume(platform, path)
    if (prompt) return(invisible(path))
    cli::cli_abort("Supply {.field {missing}} to start, or use {.code action = 'files'} for an incomplete draft.")
  }
  .odb_cloud_port_available(config$port)
  .odb_cloud_platform_require(spec, config)
  secret_env <- paste0(prefix, "_CLIENT_SECRET")
  secret <- if (config$client_type == "confidential") .odb_cloud_secret(prompt, secret_env) else NULL
  cli::cli_alert_success("App ready: {.path {file.path(path, 'app.R')}}", wrap = TRUE)
  cli::cli_text("Open {.url {paste0('http://localhost:', config$port)}} and sign in. Click Run example query when ready. {.file app.R} contains the connection settings and SQL; {.file demo-ui.R} contains the editable UI.")
  cli::cli_text("{spec$cost}")
  status <- .odb_cloud_run(path, config$port, launch_browser, secret, secret_env = secret_env)
  if (identical(status, 10L)) {
    config$client_id <- config$client_type <- NULL
    .odb_cloud_save(config, path, platform)
    rm(secret)
    cli::cli_alert_info("Returned to setup. Your app edits are preserved.")
    if (prompt) return(oauth_db_cloud_demo(platform, path = path, prompt = TRUE, launch_browser = launch_browser))
    .odb_cloud_resume(platform, path)
  }
  invisible(path)
}

.odb_cloud_resume <- function(platform, path) {
  cli::cli_alert_info("Resume this saved draft with:")
  cli::cli_code(paste0("shinyOAuthDB::oauth_db_cloud_demo(", deparse(platform), ", path = ", deparse(path), ")"))
}

.odb_cloud_platform_validate <- function(config, spec) {
  allowed <- c(names(spec$fields), "client_id", "client_type", "port")
  if (!is.list(config) || length(setdiff(names(config), allowed))) cli::cli_abort("The settings contain unsupported fields. Keep credentials out of {.file settings.dcf}.")
  # Reuse the port and client-type validation without Databricks-only fields.
  common <- .odb_cloud_validate(config[intersect(names(config), c("client_id", "client_type", "port"))])
  for (name in names(common)) config[[name]] <- common[[name]]
  if (is.null(config$client_type) && length(spec$client_types) == 1L) config$client_type <- spec$client_types[[1L]]
  if (!is.null(config$client_type) && !config$client_type %in% spec$client_types) cli::cli_abort("This example requires a {.field {spec$client_types}} OAuth registration.")
  for (name in names(spec$fields)) {
    field <- spec$fields[[name]]
    if (is.null(config[[name]])) config[[name]] <- field$default
    if (!is.null(config[[name]])) config[[name]] <- .odb_cloud_value(config[[name]], field$type)
  }
  config
}

.odb_cloud_value <- function(value, type = "text") {
  .odb_string(value, "setting")
  if (grepl("[[:cntrl:]]", value)) cli::cli_abort("Settings must not contain control characters.")
  value <- trimws(value)
  if (!nzchar(value)) cli::cli_abort("Enter a non-empty setting.")
  if (type == "hostname") {
    value <- sub("^tcp:", "", value)
    value <- sub("^https://", "", value)
    value <- sub("/$", "", value)
    if (!grepl("^[A-Za-z0-9][A-Za-z0-9.-]*[.][A-Za-z0-9-]+$", value)) cli::cli_abort("Copy only the server hostname, without credentials, a port, paths or a full connection string.")
    return(tolower(value))
  }
  if (type == "uuid" && !grepl("^[A-Fa-f0-9]{8}(-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}$", value)) cli::cli_abort("Copy the Directory (tenant) ID, a GUID, from the Entra registration overview.")
  if (type == "https") {
    url <- tryCatch(httr2::url_parse(value), error = function(error) NULL)
    if (is.null(url) || !identical(url$scheme, "https") || is.null(url$hostname) ||
        !is.null(url$username) || !is.null(url$password) || !is.null(url$query) || !is.null(url$fragment)) cli::cli_abort("Use an HTTPS URL without credentials, a query or a fragment.")
  }
  if (type == "port" && (!grepl("^[0-9]+$", value) || as.numeric(value) < 1 || as.numeric(value) > 65535)) cli::cli_abort("Choose a database port from 1 to 65535.")
  if (type == "scopes") value <- paste(unique(strsplit(value, "[[:space:]]+")[[1L]]), collapse = " ")
  if (type == "project" && !grepl("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", value)) cli::cli_abort("Copy the Google Cloud project ID, not its name or number.")
  if (type == "odbc") .odb_odbc_values(list(value))
  value
}

.odb_cloud_platform_collect <- function(config, spec, platform, path) {
  steps <- c(spec$required, if (length(spec$client_types) > 1L) "client_type")
  index <- 1L
  repeat {
    if (index > length(steps)) break
    field <- steps[[index]]
    if (!is.null(config[[field]])) { index <- index + 1L; next }
    cli::cli_h2("{index}. {if (field == 'client_id') 'Register your Shiny app' else if (field == 'client_type') 'Check the registration type' else spec$fields[[field]]$label}")
    if (field == "client_id") {
      .odb_cloud_platform_help(spec, config)
      cli::cli_text("Paste the OAuth application/client ID, not its secret.")
    } else if (field == "client_type") {
      cli::cli_text("Did the registration give you a secret? 1: No (public PKCE); 2: Yes (confidential). Use the registration type your administrator configured.")
    } else cli::cli_text("{spec$fields[[field]]$help}")
    cli::cli_text("Enter ? for setup help, back to revisit a setting, or Enter/cancel to save a draft.")
    value <- trimws(.odb_cloud_read("Your answer"))
    if (!nzchar(value) || tolower(value) == "cancel") return(structure(config, paused = TRUE))
    if (value == "?") { .odb_cloud_platform_help(spec, config); next }
    if (tolower(value) == "back") {
      index <- max(1L, index - 1L)
      for (name in steps[index:length(steps)]) config[[name]] <- NULL
      next
    }
    candidate <- tryCatch({
      if (field == "client_type") {
        if (!value %in% c("1", "2")) cli::cli_abort("Choose 1 or 2.")
        c("public", "confidential")[[as.integer(value)]]
      } else .odb_cloud_value(value, if (field == "client_id") "text" else spec$fields[[field]]$type)
    }, error = function(error) { cli::cli_alert_warning(conditionMessage(error), wrap = TRUE); NULL })
    if (is.null(candidate)) next
    config[[field]] <- candidate
    .odb_cloud_save(config, path, platform)
    index <- index + 1L
  }
  config
}

.odb_cloud_platform_help <- function(spec, config) {
  cli::cli_h2("Prepare sign-in and database access")
  for (text in spec$registration) cli::cli_text("{text}")
  cli::cli_text("Register the local return address {.url {paste0('http://localhost:', config$port)}} for this app.")
  cli::cli_text("Registration steps: {.url {spec$registration_url}}")
  cli::cli_text("Database setup: {.url {spec$setup_url}}")
  cli::cli_text("The guide saves settings locally; it doesn't create an account, change cloud resources or grant permissions.")
}

.odb_cloud_platform_require <- function(spec, config) {
  .odb_require("processx")
  for (package in names(spec$packages)) .odb_require(package, version = spec$packages[[package]])
  if (!is.null(config$driver)) {
    drivers <- unique(odbc::odbcListDrivers()$name)
    if (!config$driver %in% drivers) cli::cli_abort(c("The configured ODBC driver is not installed.",
      "i" = "Install the platform's native driver, or supply {.arg driver} with an exact name from {.code odbc::odbcListDrivers()}.",
      "i" = "Driver instructions: {.url {spec$driver_url}}"))
  }
  if (!is.null(config$sslrootcert) && !file.exists(config$sslrootcert)) cli::cli_abort("The trusted CA bundle wasn't found. Supply {.arg sslrootcert} with its local file path; see {.url {spec$setup_url}}.")
}
