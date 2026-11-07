.odb_cloud_default_path <- function(platform) {
  file.path(tools::R_user_dir("shinyOAuthDB", "cache"), "cloud-demo", platform)
}

.odb_cloud_identity_fields <- function(platform) {
  if (platform == "databricks") "host" else if (platform == "snowflake") "server" else "tenant_id"
}

.odb_cloud_edit_marker <- function(path) file.path(path, ".shinyOAuthDB-edit-setup")

.odb_cloud_edit_fields <- function(platform) {
  if (platform == "databricks") {
    fields <- list(
      edition = .odb_cloud_field("Workspace edition", "Use workspace, trial, free or unknown. Free Edition lacks the custom registration used by this demo.", "edition"),
      host = .odb_cloud_field("Workspace URL", "Paste your workspace URL, rather than the account console address.", "workspace"),
      warehouse_id = .odb_cloud_field("Default warehouse ID", "Copy the warehouse ID from SQL Warehouses > Connection details, or clear it to choose after sign-in.")
    )
  } else fields <- .odb_cloud_specs()[[platform]]$fields
  fields$client_id <- .odb_cloud_field("OAuth client ID", "Copy the application/client ID from your Shiny app registration. This is not its client secret.")
  if (platform == "databricks" || length(.odb_cloud_specs()[[platform]]$client_types) > 1L) {
    fields$client_type <- .odb_cloud_field("Registration type", "Use public (or 1) for PKCE without a secret, or confidential (or 2) for a registration with a client secret.", "client_type")
  }
  fields$port <- .odb_cloud_field("Local Shiny port", "Choose a port from 1024 to 65535. Update the registered return address to http://localhost:<port> before signing in.")
  fields
}

.odb_cloud_edit_setup <- function(config, path, platform) {
  fields <- .odb_cloud_edit_fields(platform)
  repeat {
    cli::cli_h2("Review your saved setup")
    labels <- paste0(seq_along(fields), ". ", vapply(fields, `[[`, "", "label"))
    values <- vapply(names(fields), function(name) {
      if (is.null(config[[name]])) "(not set)" else as.character(config[[name]])
    }, "")
    cli::cli_dl(stats::setNames(values, labels))
    cli::cli_text("Enter a setting number to change it, 0 to continue, or cancel to save and return to R. Secrets are never shown or saved here.")
    choice <- tolower(trimws(.odb_cloud_read("Setting")))
    if (!nzchar(choice) || choice == "cancel") return(structure(config, paused = TRUE))
    if (choice %in% c("0", "start", "done")) return(config)
    if (!choice %in% as.character(seq_along(fields))) {
      cli::cli_alert_info("Choose one of the setting numbers, 0, or cancel.")
      next
    }
    name <- names(fields)[[as.integer(choice)]]
    field <- fields[[name]]
    cli::cli_h3("{field$label}")
    cli::cli_text("{field$help}")
    cli::cli_text("Enter a new value, clear to remove the saved value, or press Enter to keep it.")
    value <- trimws(.odb_cloud_read("New value"))
    if (!nzchar(value) || tolower(value) == "back") next
    if (tolower(value) == "cancel") return(structure(config, paused = TRUE))
    candidate <- tryCatch({
      updated <- config
      updated[[name]] <- if (tolower(value) == "clear") NULL else switch(field$type,
        workspace = .odb_cloud_host(value),
        edition = match.arg(value, c("workspace", "trial", "free", "unknown")),
        client_type = if (value %in% c("1", "2")) c("public", "confidential")[[as.integer(value)]] else match.arg(value, c("public", "confidential")),
        .odb_cloud_value(value, field$type))
      if (name %in% .odb_cloud_identity_fields(platform) && !identical(config[[name]], updated[[name]])) {
        updated$client_id <- updated$client_type <- NULL
        if (platform == "databricks") updated$warehouse_id <- NULL
      }
      if (name == "resource" && !identical(config$resource, updated$resource)) updated$scope <- NULL
      if (platform == "databricks") .odb_cloud_validate(updated) else .odb_cloud_platform_validate(updated, .odb_cloud_specs()[[platform]])
    }, error = function(error) { cli::cli_alert_warning(conditionMessage(error), wrap = TRUE); NULL })
    if (is.null(candidate)) next
    config <- candidate
    .odb_cloud_save(config, path, platform)
    cli::cli_alert_success("Setting saved. Your app code is kept.")
  }
}

.odb_cloud_files_message <- function(platform, path) {
  cli::cli_alert_success("Editable demo saved at {.path {path}}.", wrap = TRUE)
  cli::cli_text("Open the app code with:")
  cli::cli_code(paste0("file.edit(", deparse(file.path(path, "app.R")), ")"))
  .odb_cloud_resume(platform, path)
}
