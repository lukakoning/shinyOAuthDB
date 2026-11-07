# Console design preview. All inputs and check results are fictional.
# Rscript --vanilla tools/preview-cloud-demo.R [ready|registration|redirect|warehouse]
preview_cloud_demo <- function(
  scenario = c("ready", "registration", "redirect", "warehouse")
) {
  scenario <- match.arg(scenario)
  if (!requireNamespace("cli", quietly = TRUE)) {
    stop(
      "Install cli to run the preview: install.packages('cli')",
      call. = FALSE
    )
  }
  workspace <- "https://example.cloud.databricks.com"
  callback <- "http://localhost:8100"
  app_path <- "my-databricks-demo/app.R"
  registration <- "https://docs.databricks.com/aws/en/integrations/enable-disable-oauth"

  cli::cli_h1("Databricks Shiny demo")
  cli::cli_alert_info(
    "Design preview: every entry and check below is an example. No credentials are collected and no workspace is contacted.",
    wrap = TRUE
  )
  cli::cli_text(
    "Build a local Shiny app that queries your existing workspace using the person who signs in. Databricks keeps enforcing their data permissions."
  )

  cli::cli_h2("1. Find your workspace")
  cli::cli_text(
    "Open your Databricks workspace and copy the address from the browser. You can paste the whole address; we'll keep its workspace origin."
  )
  cli::cli_text("{.strong Prompt:} Workspace URL")
  cli::cli_text("{.emph Example entry:} {.url {workspace}}")
  cli::cli_alert_success(
    "Example check: workspace sign-in information is reachable.",
    wrap = TRUE
  )

  cli::cli_h2("2. Connect your Shiny app")
  cli::cli_text(
    "The client ID identifies your Shiny app. Registering its return address tells Databricks where to send the browser after sign-in."
  )
  cli::cli_text(
    "{.strong Prompt:} Do you already have an OAuth app client ID for this workspace?"
  )
  cli::cli_ol(c("I have a client ID", "Show me how to get one"))
  cli::cli_text("You can also ask for help, go back or cancel.")
  cli::cli_text(
    "Your app's return address is {.url {callback}}. Register this exact address."
  )

  if (scenario == "registration") {
    cli::cli_h3("Get an OAuth app registration")
    cli::cli_text(
      "An account administrator creates the connection in Settings > App connections. Open {.url {registration}} for the steps."
    )
    cli::cli_text("{.strong Copy for your administrator:}")
    cli::cli_blockquote(paste0(
      "Please register a Databricks OAuth app for my local Shiny demo. ",
      "Redirect address: ",
      callback,
      ". Enable SQL access. Send me its client ID and tell me ",
      "whether it is public or requires a client secret."
    ))
    cli::cli_alert_info(
      "You can pause here and resume when the registration is ready. The draft keeps your workspace and callback, without credentials.",
      wrap = TRUE
    )
    cli::cli_code(
      'shinyOAuthDB::oauth_db_cloud_demo("databricks", path = "my-databricks-demo")'
    )
    cli::cli_text(
      "{.emph Preview only: this example hasn't created a draft directory.}"
    )
    return(invisible(NULL))
  }

  cli::cli_text("{.strong Prompt:} OAuth app client ID")
  cli::cli_text("{.emph Example entry:} example-client-id")
  cli::cli_text(
    "{.strong Prompt:} Did your app registration give you a client secret?"
  )
  cli::cli_text(
    "{.emph Example choice:} Public registration; no secret to enter."
  )
  cli::cli_text(
    "For a confidential registration, the guide would request the secret using masked input. It wouldn't write it into your app files."
  )

  cli::cli_h2("3. Sign in through the Shiny app")
  cli::cli_alert_success(
    "Example check: local callback port is available.",
    wrap = TRUE
  )
  cli::cli_text(
    "The guide now creates your editable app and opens {.url {callback}}. Click Sign in there and use your normal Databricks account."
  )

  if (scenario == "redirect") {
    cli::cli_alert_danger(
      "Example problem: the sign-in page reports a redirect-address mismatch.",
      wrap = TRUE
    )
    cli::cli_text(
      "Check that the app registration contains {.url {callback}} exactly, including its path and trailing slash."
    )
    cli::cli_text(
      "{.strong Next choice:} Return to app settings / Retry sign-in / Cancel"
    )
    return(invisible(NULL))
  }

  cli::cli_alert_success(
    "Example browser result: signed in. No SQL has run.",
    wrap = TRUE
  )
  cli::cli_h2("4. Choose a warehouse in the app")
  cli::cli_text(
    "A SQL warehouse runs the query for your app. Choose one you normally use in Databricks."
  )
  cli::cli_text(
    "The app lists warehouse names using your sign-in. You don't have to find an ID first."
  )

  if (scenario == "warehouse") {
    cli::cli_alert_info(
      "Example result: no warehouses were listed for this account.",
      wrap = TRUE
    )
    cli::cli_text(
      "Open SQL Warehouses in the workspace to find one or ask for access. If you already have a warehouse ID or HTTP path, enter it in the app."
    )
    cli::cli_text(
      "{.strong Next choice:} Refresh list / Enter ID or HTTP path / Return to setup"
    )
    return(invisible(NULL))
  }

  cli::cli_bullets(c(
    " " = "Reporting demo: Running (example)",
    " " = "Team analytics: Stopped (example)"
  ))
  cli::cli_text(
    "Choose a warehouse, review the query and click {.strong Run example query}."
  )
  cli::cli_code("SELECT current_user() AS signed_in_user", language = "SQL")
  cli::cli_alert_info(
    "The app explains here that running SQL can start the warehouse and incur normal compute charges.",
    wrap = TRUE
  )
  cli::cli_alert_success(
    "Example query result: analyst@example.org. The app used the signed-in person's account.",
    wrap = TRUE
  )

  cli::cli_h2("5. Try your own R code")
  cli::cli_text(
    "Edit {.path {app_path}} to change the example query or UI. Save it and reload the browser to try your changes."
  )
  cli::cli_code('file.edit("my-databricks-demo/app.R")')
  cli::cli_text(
    "Stop demo closes the local app. Your shared cloud warehouse stays under its normal Databricks settings."
  )
  cli::cli_rule("End of design preview")
  invisible(NULL)
}

if (sys.nframe() == 0L) {
  arguments <- commandArgs(trailingOnly = TRUE)
  preview_cloud_demo(if (length(arguments)) arguments[[1L]] else "ready")
}
