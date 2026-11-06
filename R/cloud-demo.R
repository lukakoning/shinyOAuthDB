#' Set up an editable Shiny demo for a cloud workspace
#'
#' A console guide helps you find your workspace and OAuth app settings,
#' then runs a local Shiny app with your installed R packages. Visitors sign
#' in through shinyOAuth and use their own cloud data permissions.
#'
#' @param platform Cloud platform: `"databricks"`, `"fabric"`, `"bigquery"`
#'   or `"snowflake"`.
#' @param host Databricks workspace hostname or browser URL. Paths, queries and
#'   fragments are removed. For other SQL demos, an alias for `server`.
#' @param client_id Client ID from your custom OAuth app registration.
#' @param client_type `"public"` for PKCE without a secret, or `"confidential"`.
#'   The guide asks when needed; noninteractive calls default to `"public"`
#'   where supported. BigQuery and Snowflake demos use confidential registrations.
#' @param warehouse_id Optional default SQL warehouse ID.
#' @param http_path Optional warehouse HTTP path, instead of `warehouse_id`.
#' @param path Empty or existing cloud-demo directory. The default is a temporary
#'   directory. Existing app edits are preserved. Supply a path to resume later.
#' @param port Local Shiny port, default 8100 or the saved setting. Register
#'   `http://localhost:<port>` exactly as the OAuth callback.
#' @param edition `"workspace"`, `"trial"`, `"free"`, or `"unknown"`. Free
#'   Edition lacks the account-level custom registration this example needs.
#' @param action `"start"` guides setup and runs the app; `"files"` writes an
#'   editable draft without network calls or asking for a secret.
#' @param prompt Ask interactively for missing settings. Use `FALSE` in scripts.
#' @param launch_browser Open the local app in a regular browser.
#' @param ... Named platform settings. Fabric uses `server`, `database`,
#'   `tenant_id` and optionally `driver`. Missing required values are explained
#'   and requested interactively. BigQuery uses `project` and optionally
#'   `location` and `maximum_bytes_billed`. Snowflake uses `server`, `role`,
#'   `warehouse` and optionally `database`, `schema`, `driver`.
#'   See the guided cloud demos vignette.
#' @return Invisibly, the demo directory, including after pausing incomplete
#'   interactive setup. Noninteractive starts report missing settings as errors.
#' @details
#' Fabric asks for its SQL server/database and an Entra tenant and app
#' registration. Install fabricQueryR, odbc and Microsoft ODBC Driver 18.
#' Its confidential secret uses `OAUTHDB_FABRIC_CLIENT_SECRET`. The copied
#' `app.R` contains the connection and query code; `demo-ui.R` contains the UI.
#'
#' Databricks needs an account-level custom OAuth app registration with the
#' exact callback and SQL access. Public PKCE registrations need no secret.
#' For confidential apps, set `OAUTHDB_DATABRICKS_CLIENT_SECRET` or use the
#' masked prompt. Secrets and tokens are not written to the generated files
#' or serialized R arguments. The app's child process receives the secret
#' through its environment. Normal cloud TLS verification stays enabled.
#'
#' Settings can also come from `OAUTHDB_DATABRICKS_HOST` and
#' `OAUTHDB_DATABRICKS_CLIENT_ID`. The guide can pause for registration and
#' resume from `path`. The generated `settings.dcf` contains only non-secret
#' configuration; `app.R` stays editable.
#'
#' Local R needs brickster 0.2.14 or later, jsonlite and processx; masked input
#' uses askpass. No Docker is needed. The app discovers SQL warehouses after
#' sign-in, with a manual-ID fallback. Listing doesn't run SQL. Clicking
#' **Run example query** opens the DBI connection and runs `SELECT current_user()`.
#' Queries can start a stopped warehouse and consume compute credits.
#' Stopping the app doesn't stop or change a shared cloud warehouse.
#'
#' Databricks Free Edition has no account-console or account-level API access,
#' so it doesn't offer the custom OAuth registration path used here. A full
#' workspace or eligible full-platform trial needs access to that registration.
#' This is distinct from connecting a local R client using a personal token.
#' @examples
#' \dontrun{
#' oauth_db_cloud_demo("databricks")
#' path <- oauth_db_cloud_demo("databricks", action = "files", prompt = FALSE)
#' file.edit(file.path(path, "app.R"))
#' oauth_db_cloud_demo("databricks", path = path)
#' }
#' @seealso [oauth_db_demo()], [oauth_db_databricks_client()],
#'   [oauth_db_databricks()], [oauth_db_databricks_api()].
#' @export
oauth_db_cloud_demo <- function(
  platform = "databricks", host = NULL, client_id = NULL, client_type = NULL,
  warehouse_id = NULL, http_path = NULL, path = NULL, port = NULL, edition = NULL,
  action = c("start", "files"), prompt = interactive(), launch_browser = interactive(), ...
) {
  platform <- match.arg(platform, c("databricks", names(.odb_cloud_specs())))
  settings <- list(...)
  .odb_named_args(settings, "Platform settings")
  if (platform != "databricks") {
    common <- list(host = host, client_id = client_id, client_type = client_type,
      warehouse_id = warehouse_id, http_path = http_path, edition = edition)
    common <- common[!vapply(common, is.null, logical(1))]
    return(.odb_cloud_platform_demo(platform, c(common, settings), path, port,
      match.arg(action), prompt, launch_browser))
  }
  if (length(settings)) cli::cli_abort("Unknown Databricks settings: {.field {names(settings)}}.")
  action <- match.arg(action)
  for (flag in list(prompt, launch_browser)) {
    if (!is.logical(flag) || length(flag) != 1L || is.na(flag)) cli::cli_abort("{.arg prompt} and {.arg launch_browser} must be TRUE or FALSE.")
  }
  if (prompt && !.odb_cloud_interactive()) cli::cli_abort("Interactive setup needs an R console. Use {.code prompt = FALSE} in scripts.")
  if (is.null(path)) path <- tempfile("shinyOAuthDB-databricks-")
  .odb_string(path, "path")
  marker <- file.path(path, ".shinyOAuthDB-cloud-demo")
  if (dir.exists(path) && !file.exists(marker) && length(list.files(path, all.files = TRUE, no.. = TRUE))) {
    cli::cli_abort("{.arg path} must be empty or contain a shinyOAuthDB cloud demo.")
  }
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  .odb_cloud_check_marker(path, platform)
  config <- .odb_cloud_load(path)
  if (!is.null(host) && !is.null(config$host) && !identical(.odb_cloud_host(host), .odb_cloud_host(config$host))) {
    config$client_id <- config$client_type <- config$warehouse_id <- NULL
  }
  supplied <- list(host = host, client_id = client_id, client_type = client_type,
    warehouse_id = warehouse_id, port = port, edition = edition)
  for (name in names(supplied)) if (!is.null(supplied[[name]])) config[[name]] <- supplied[[name]]
  if (is.null(config$host)) config$host <- .odb_cloud_env("OAUTHDB_DATABRICKS_HOST")
  if (is.null(config$client_id)) config$client_id <- .odb_cloud_env("OAUTHDB_DATABRICKS_CLIENT_ID")
  if (!is.null(http_path)) {
    if (!is.null(warehouse_id)) cli::cli_abort("Supply only one of {.arg warehouse_id} and {.arg http_path}.")
    if (!is.character(http_path) || length(http_path) != 1L || is.na(http_path) ||
        !grepl("^/sql/1[.]0/warehouses/[A-Za-z0-9_-]+$", http_path)) {
      cli::cli_abort("Copy the warehouse HTTP path, such as {.code /sql/1.0/warehouses/warehouse-id}.")
    }
    config$warehouse_id <- sub("^/sql/1[.]0/warehouses/", "", http_path)
  }
  config <- .odb_cloud_validate(config)
  cli::cli_h1("Databricks Shiny demo")
  cli::cli_text("Use your existing workspace and data permissions in an editable local Shiny app.")
  if (action == "start" && identical(config$edition, "free")) {
    .odb_cloud_save(config, path)
    .odb_cloud_files(path)
    .odb_cloud_free()
  }
  if (action == "start" && prompt) {
    .odb_cloud_port_available(config$port)
    config <- .odb_cloud_collect(config, path)
  }
  paused <- isTRUE(attr(config, "paused"))
  attr(config, "paused") <- NULL
  if (!paused && action == "start" && is.null(config$client_type)) config$client_type <- "public"
  .odb_cloud_save(config, path)
  .odb_cloud_files(path)
  if (action == "files") {
    cli::cli_alert_success("Editable draft: {.path {path}}")
    return(invisible(path))
  }
  if (identical(config$edition, "free")) .odb_cloud_free()
  missing <- c("host", "client_id")[vapply(c("host", "client_id"), function(name) is.null(config[[name]]), logical(1))]
  if (length(missing) || paused) {
    .odb_cloud_registration(config)
    if (prompt) {
      cli::cli_alert_info("Setup paused. Your draft is at {.path {path}}.", wrap = TRUE)
      cli::cli_code(paste0("shinyOAuthDB::oauth_db_cloud_demo('databricks', path = ", deparse(path), ")"))
      return(invisible(path))
    }
    cli::cli_abort("Supply {.field {missing}} to start, or use {.code action = 'files'} for an incomplete draft.")
  }
  .odb_cloud_port_available(config$port)
  .odb_require("brickster", version = "0.2.14")
  .odb_require("jsonlite")
  .odb_require("processx")
  .odb_cloud_check_workspace(config)
  secret <- if (config$client_type == "confidential") .odb_cloud_secret(prompt) else NULL
  cli::cli_alert_success("App ready: {.path {file.path(path, 'app.R')}}", wrap = TRUE)
  cli::cli_text("Open {.url {paste0('http://localhost:', config$port)}} and click Sign in. Choose a warehouse there, then run the example query.")
  cli::cli_text("Save edits to {.file app.R} and reload the browser to try them. Stop demo ends the local app; the shared cloud warehouse keeps its own settings.")
  status <- .odb_cloud_run(path, config$port, launch_browser, secret)
  if (identical(status, 10L)) {
    config$client_id <- config$client_type <- NULL
    .odb_cloud_save(config, path)
    rm(secret)
    cli::cli_alert_info("Returned to setup. Your app edits are preserved.")
    if (prompt) return(oauth_db_cloud_demo(platform, path = path, prompt = TRUE, launch_browser = launch_browser))
    cli::cli_code(paste0("shinyOAuthDB::oauth_db_cloud_demo('databricks', path = ", deparse(path), ")"))
  }
  invisible(path)
}

.odb_cloud_interactive <- function() interactive()
.odb_cloud_read <- function(label) readline(paste0(label, ": "))
.odb_cloud_env <- function(name) { value <- Sys.getenv(name, ""); if (nzchar(value)) value else NULL }

.odb_cloud_host <- function(value) {
  .odb_string(value, "host")
  value <- trimws(value)
  if (!grepl("^[A-Za-z][A-Za-z0-9+.-]*://", value)) value <- paste0("https://", value)
  url <- tryCatch(httr2::url_parse(value), error = function(error) NULL)
  if (is.null(url) || !identical(tolower(url$scheme), "https") ||
      is.null(url$hostname) || !grepl("^[A-Za-z0-9][A-Za-z0-9.-]*[.][A-Za-z0-9-]+$", url$hostname) ||
      !is.null(url$username) || !is.null(url$password) ||
      !is.null(url$port) && !identical(as.character(url$port), "443")) {
    cli::cli_abort("Paste an HTTPS workspace URL without embedded credentials. The demo uses the standard HTTPS port.")
  }
  host <- tolower(url$hostname)
  if (grepl("^accounts[.]|^accounts-", host)) cli::cli_abort("That is an account-console address. Open your workspace and copy its browser address instead.")
  host
}

.odb_cloud_validate <- function(config) {
  allowed <- c("host", "client_id", "client_type", "warehouse_id", "port", "edition")
  if (!is.list(config) || length(setdiff(names(config), allowed))) cli::cli_abort("The saved settings contain unsupported fields. Keep credentials out of {.file settings.dcf}.")
  if (!is.null(config$host)) config$host <- .odb_cloud_host(config$host)
  for (name in intersect(c("client_id", "warehouse_id"), names(config))) {
    .odb_string(config[[name]], name)
    if (grepl("[[:cntrl:]]", config[[name]])) cli::cli_abort("The {.field {name}} setting must not contain control characters.")
  }
  if (!is.null(config$warehouse_id) && !grepl("^[A-Za-z0-9_-]+$", config$warehouse_id)) cli::cli_abort("Copy only the warehouse ID, or use {.arg http_path} for its HTTP path.")
  config$client_type <- if (is.null(config$client_type)) NULL else match.arg(config$client_type, c("public", "confidential"))
  config$edition <- if (is.null(config$edition)) NULL else match.arg(config$edition, c("workspace", "trial", "free", "unknown"))
  if (is.null(config$port)) config$port <- 8100L
  if (length(config$port) != 1L || is.na(config$port) || !grepl("^[0-9]+$", config$port) ||
      as.numeric(config$port) < 1024 || as.numeric(config$port) > 65535) cli::cli_abort("Choose a local port between 1024 and 65535.")
  config$port <- as.integer(config$port)
  config
}

.odb_cloud_load <- function(path) {
  file <- file.path(path, "settings.dcf")
  if (!file.exists(file)) return(list())
  data <- tryCatch(read.dcf(file, all = FALSE), error = function(error) NULL)
  if (is.null(data) || nrow(data) != 1L) cli::cli_abort("Could not read {.file settings.dcf}. Use a new empty path or repair the non-secret settings.")
  stats::setNames(as.list(unname(data[1L, , drop = TRUE])), colnames(data))
}

.odb_cloud_save <- function(config, path, platform = "databricks") {
  values <- vapply(config, as.character, "")
  write.dcf(as.data.frame(as.list(values), stringsAsFactors = FALSE), file.path(path, "settings.dcf"))
  writeLines(platform, file.path(path, ".shinyOAuthDB-cloud-demo"))
}

.odb_cloud_files <- function(path, platform = "databricks") {
  source <- system.file("cloud-demo", platform, package = "shinyOAuthDB", mustWork = TRUE)
  for (name in c("app.R", "README.md")) {
    destination <- file.path(path, name)
    if (!file.exists(destination) && !file.copy(file.path(source, name), destination)) cli::cli_abort("Could not copy the demo app to {.path {path}}.")
  }
  if (platform != "databricks") {
    destination <- file.path(path, "demo-ui.R")
    if (!file.exists(destination) && !file.copy(system.file("cloud-demo", "demo-ui.R",
      package = "shinyOAuthDB", mustWork = TRUE), destination)) cli::cli_abort("Could not copy the demo UI.")
  }
}

.odb_cloud_registration <- function(config) {
  callback <- paste0("http://localhost:", config$port)
  help <- if (!is.null(config$host) && endsWith(config$host, ".azuredatabricks.net")) {
    "https://learn.microsoft.com/azure/databricks/integrations/enable-disable-oauth"
  } else if (!is.null(config$host) && endsWith(config$host, ".gcp.databricks.com")) {
    "https://docs.databricks.com/gcp/en/integrations/enable-disable-oauth"
  } else "https://docs.databricks.com/aws/en/integrations/enable-disable-oauth"
  cli::cli_h2("Get an OAuth app registration")
  cli::cli_text("The client ID identifies your Shiny app. An account administrator creates its registration under Settings > App connections.")
  cli::cli_text("Register this exact return address: {.url {callback}}. Allow SQL access; the app requests openid, profile, email, offline_access and sql.")
  cli::cli_text("For a local demo, a public PKCE registration avoids a shared secret when your organization permits it. A confidential registration needs its client secret.")
  cli::cli_text("Steps: {.url {help}}")
  cli::cli_text("Copy for your administrator:")
  cli::cli_blockquote(paste0("Please register an OAuth app for my local Shiny demo with redirect ", callback,
    " and SQL access. Please give me its client ID and tell me whether it needs a client secret."))
}

.odb_cloud_free <- function() {
  cli::cli_abort(c("Databricks Free Edition doesn't provide the account-level custom OAuth registration needed by this demo.",
    "i" = "Use a full workspace or eligible full-platform trial with custom registration access, or try {.code oauth_db_demo('postgrest')} locally.",
    "i" = "Free Edition limits: {.url https://docs.databricks.com/aws/en/getting-started/free-edition-limitations}"),
    class = "shinyOAuthDB_cloud_demo_unsupported_edition")
}

.odb_cloud_collect <- function(config, path) {
  steps <- c("edition", "host", "client_id", "client_type")
  index <- 1L
  repeat {
    field <- steps[[index]]
    if (!is.null(config[[field]])) {
      index <- index + 1L
      if (index > length(steps)) break
      next
    }
    cli::cli_h2(switch(field, edition = "1. Choose your workspace edition", host = "2. Find your workspace",
      client_id = "3. Connect your Shiny app", client_type = "4. Check the registration type"))
    label <- switch(field, edition = "1: Full workspace or trial; 2: Free Edition; 3: Not sure",
      host = "Open your workspace and paste its browser URL",
      client_id = "OAuth app client ID (Enter to pause; ? for registration steps)",
      client_type = "Did the registration give you a client secret? 1: No (public PKCE); 2: Yes")
    cli::cli_text("{label}")
    cli::cli_text("Enter ? for help, back to revisit a setting, or cancel to keep the draft.")
    value <- trimws(.odb_cloud_read("Your answer"))
    if (tolower(value) == "cancel") return(structure(config, paused = TRUE))
    if (tolower(value) == "back") {
      index <- max(1L, index - 1L)
      config[[steps[[index]]]] <- NULL
      next
    }
    if (value == "?") {
      if (field == "edition") {
        cli::cli_text("Free Edition has no account-console access for custom OAuth registration. A full workspace or eligible full-platform trial needs access to that registration.")
        cli::cli_text("No account yet? Compare the trial options at {.url https://docs.databricks.com/aws/en/getting-started/free-trial}. You can cancel here and resume later.")
      } else if (field == "host") {
        cli::cli_text("Copy the address of the workspace where you use SQL Warehouses, not the account console. Browser paths and query parameters will be removed.")
      } else .odb_cloud_registration(config)
      next
    }
    if (!nzchar(value)) {
      if (field == "client_id") return(structure(config, paused = TRUE))
      cli::cli_alert_info("Enter a value, ask for help with ?, or cancel.")
      next
    }
    candidate <- tryCatch(switch(field,
      edition = if (value %in% c("1", "2", "3")) c("workspace", "free", "unknown")[[as.integer(value)]] else stop("Choose 1, 2 or 3."),
      host = .odb_cloud_host(value), client_id = { .odb_string(value, "client_id"); if (grepl("[[:cntrl:]]", value)) stop("Paste a client ID without control characters."); value },
      client_type = if (value %in% c("1", "2")) c("public", "confidential")[[as.integer(value)]] else stop("Choose 1 or 2.")),
      error = function(error) { cli::cli_alert_warning(conditionMessage(error), wrap = TRUE); NULL })
    if (is.null(candidate)) next
    if (field == "host" && !identical(config$host, candidate)) {
      config$client_id <- config$client_type <- config$warehouse_id <- NULL
    }
    config[[field]] <- candidate
    .odb_cloud_save(config, path)
    if (field == "edition" && candidate == "free") .odb_cloud_free()
    index <- index + 1L
    if (index > length(steps)) break
  }
  config
}

.odb_cloud_port_available <- function(port) {
  socket <- tryCatch(serverSocket(port), error = function(error) NULL)
  if (is.null(socket)) cli::cli_abort("Port {port} is unavailable. Choose another {.arg port}, then register its exact callback address before signing in.")
  close(socket)
  invisible(NULL)
}

.odb_cloud_check_workspace <- function(config) {
  progress <- cli::cli_progress_step("Checking workspace sign-in information", spinner = interactive(), .auto_close = FALSE)
  result <- tryCatch({ oauth_db_databricks_provider(config$host,
    token_auth_style = if (config$client_type == "confidential") "header" else "public"); TRUE }, error = function(error) FALSE)
  cli::cli_progress_done(id = progress, result = if (result) "done" else "failed")
  if (!result) cli::cli_abort(c("Couldn't read the workspace's sign-in information.",
    "i" = "Check the workspace URL, network/VPN access and trusted TLS certificates. This is checked before any client secret is sent."))
  invisible(NULL)
}

.odb_cloud_secret <- function(prompt, envvar = "OAUTHDB_DATABRICKS_CLIENT_SECRET") {
  secret <- .odb_cloud_env(envvar)
  if (is.null(secret) && prompt) {
    .odb_require("askpass")
    secret <- askpass::askpass("OAuth app client secret (not saved)")
  }
  if (is.null(secret) || !is.character(secret) || length(secret) != 1L || is.na(secret) || !nzchar(secret)) {
    cli::cli_abort("This confidential registration needs its secret. Set {.envvar {envvar}}, or rerun interactively for masked input.")
  }
  secret
}

.odb_cloud_run <- function(path, port, launch_browser, secret, secret_env = "OAUTHDB_DATABRICKS_CLIENT_SECRET") {
  env <- c("current", R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
    stats::setNames(if (is.null(secret)) "" else secret, secret_env))
  result <- processx::run(file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rterm.exe" else "R"),
    args = c("--vanilla", "--slave", "-f", system.file("cloud-demo", "run.R", package = "shinyOAuthDB", mustWork = TRUE),
      "--args", path, as.character(port), as.character(launch_browser)), env = env, encoding = "UTF-8",
    echo = TRUE, error_on_status = FALSE, supervise = TRUE, cleanup_tree = TRUE, windows_hide_window = TRUE)
  if (!result$status %in% c(0L, 10L)) cli::cli_abort("The local Shiny app stopped unexpectedly (exit status {result$status}). Check its console output and resume from the saved demo directory.")
  invisible(result$status)
}
