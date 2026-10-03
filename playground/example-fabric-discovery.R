# Run from the shinyOAuthDB repository root after configuring the environment
# described in playground/README.md. This example opens no browser automatically.
# This is a complete app: adapt its source, native call, UI and server.
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)
library(fabricQueryR)

# Endpoint and OAuth settings are trusted server configuration.
config <- list(
  tenant_id = Sys.getenv("OAUTHDB_TENANT_ID"),
  client_id = Sys.getenv("OAUTHDB_CLIENT_ID"),
  client_secret = Sys.getenv("OAUTHDB_CLIENT_SECRET"),
  redirect_uri = Sys.getenv("OAUTHDB_REDIRECT_URI", "http://localhost:8100")
)
if (
  any(!nzchar(unlist(config[c("tenant_id", "client_id")], use.names = FALSE)))
) {
  stop(
    "Set the required OAuth and backend environment variables listed in playground/README.md.",
    call. = FALSE
  )
}

port <- suppressWarnings(as.integer(Sys.getenv("OAUTHDB_PORT", "8100")))
if (is.na(port) || port < 1L || port > 65535L) {
  stop("OAUTHDB_PORT must be a valid TCP port.", call. = FALSE)
}

executor <- match.arg(
  Sys.getenv("OAUTHDB_EXECUTOR", "mirai"),
  c("mirai", "future")
)

db_source <- shinyOAuthDB::oauth_db_fabric(service = "fabric")

# Other apps can use known endpoints directly. This example lists only the
# workspaces visible to the selected user.

client <- shinyOAuthDB::oauth_db_microsoft_client(
  sources = list(database = db_source),
  tenant_id = config$tenant_id,
  client_id = config$client_id,
  client_secret = config$client_secret,
  redirect_uri = config$redirect_uri
)

ui <- shinyOAuth::oauth_ui(
  shiny::fluidPage(
    shiny::titlePanel("shinyOAuthDB: Fabric workspace discovery"),
    shiny::p(
      "List this user's workspaces. The role selector filters the authorized listing."
    ),
    shiny::actionButton("login", "Sign in"),
    shiny::actionButton("logout", "Sign out"),
    shiny::selectInput(
      "role",
      "Workspace role filter",
      choices = c("All roles" = "", "Admin", "Member", "Contributor", "Viewer")
    ),
    shiny::actionButton("run_sync", "Run native call"),
    shiny::actionButton("run_async", "Run in background"),
    shiny::actionButton("cancel", "Discard background result"),
    shiny::h4("Authorization status"),
    shiny::verbatimTextOutput("status"),
    shiny::h4("Native result"),
    shiny::textOutput("sync_error"),
    shiny::verbatimTextOutput("sync_result"),
    shiny::h4("Background status and result"),
    shiny::verbatimTextOutput("async_status"),
    shiny::verbatimTextOutput("async_result")
  ),
  id = "auth",
  client = client
)

server <- function(input, output, session) {
  auth <- shinyOAuth::oauth_module_server(
    "auth",
    client,
    auto_redirect = FALSE,
    async = TRUE,
    refresh_proactively = TRUE
  )

  # Follow the module's modern connection object; shinyOAuth owns refresh.
  authorization <- shiny::reactive(auth$connection())

  db <- shinyOAuthDB::oauth_db_session(
    db_source,
    authorization = authorization,
    session = session,
    connection_policy = "session"
  )

  # The adapter supplies trusted source bindings and a fixed worker token.
  # Live Shiny authorizations/providers stay in the owning Shiny process.
  task_error <- NULL

  task <- tryCatch(
    shinyOAuthDB::oauth_db_task(
      db,
      fabricQueryR::fabric_workspaces,
      executor = executor,
      effect = "read",
      pending = "latest"
    ),
    error = function(e) {
      task_error <<- "Background execution is unavailable. Check source capabilities and worker dependencies."

      NULL
    }
  )

  last_result <- shiny::reactiveVal(NULL)
  last_error <- shiny::reactiveVal(NULL)

  owner <- shiny::reactive({
    connection <- authorization()
    if (is.null(connection)) {
      NULL
    } else {
      list(id = connection$id, generation = db$generation())
    }
  })

  observed_owner <- shiny::reactiveVal(NULL)

  shiny::observeEvent(
    owner(),
    {
      next_owner <- owner()
      if (!identical(observed_owner(), next_owner)) {
        observed_owner(next_owner)
        last_result(NULL)
        last_error(NULL)
        if (!is.null(task)) task$cancel()
      }
    },
    ignoreNULL = FALSE,
    priority = 100
  )

  operation_args <- function() {
    role <- input$role
    shiny::req(
      is.character(role),
      length(role) == 1L,
      role %in% c("", "Admin", "Member", "Contributor", "Viewer")
    )

    list(roles = if (nzchar(role)) role else NULL)
  }

  shiny::observeEvent(input$login, auth$request_login())
  shiny::observeEvent(input$logout, auth$logout())

  shiny::observeEvent(input$run_sync, {
    captured_owner <- owner()
    shiny::req(captured_owner)
    args <- operation_args()
    last_result(NULL)
    last_error(NULL)

    tryCatch(
      {
        value <- suppressWarnings(suppressMessages(
          fabricQueryR::fabric_workspaces(
            roles = args$roles,
            output = "list",
            token = db$token_provider()
          )
        ))
        if (identical(captured_owner, owner())) {
          last_result(list(owner = captured_owner, value = value))
        }
      },

      error = function(e) {
        # Native conditions may contain sensitive request details. Render only a
        # safe message belonging to the still-current authorization.
        if (identical(captured_owner, owner())) {
          last_error(list(
            owner = captured_owner,
            message = "The operation failed. Check the user's grants and backend configuration."
          ))
        }
      }
    )
  })

  shiny::observeEvent(input$run_async, {
    shiny::req(task, owner())
    args <- operation_args()

    task$invoke(roles = args$roles)
  })

  shiny::observeEvent(input$cancel, {
    if (!is.null(task)) task$cancel()
  })

  sync_result <- shiny::reactive({
    saved <- last_result()
    shiny::req(saved, identical(saved$owner, owner()))

    saved$value
  })

  output$status <- shiny::renderPrint(db$status())

  output$sync_error <- shiny::renderText({
    saved <- last_error()
    shiny::req(saved, identical(saved$owner, owner()))

    saved$message
  })

  output$sync_result <- shiny::renderPrint(sync_result())

  output$async_status <- shiny::renderPrint({
    if (is.null(task)) task_error else task$status()
  })

  # oauth_db_task hides background results/errors after authorization changes.
  output$async_result <- shiny::renderPrint({
    shiny::req(task)

    task$result()
  })
}

app <- shiny::shinyApp(ui = ui, server = server, uiPattern = ".*")

# Configure workers once outside server(), then restore them when the app ends.
if (identical(executor, "mirai")) {
  library(mirai)

  mirai::daemons(2L)
} else {
  library(future)
  previous_plan <- future::plan(future::multisession, workers = 2L)
}

message(
  "Open the exact OAUTHDB_REDIRECT_URI in your browser, then click Sign in."
)
tryCatch(
  shiny::runApp(app, host = "127.0.0.1", port = port, launch.browser = FALSE),
  finally = {
    if (identical(executor, "mirai")) {
      mirai::daemons(0L)
    } else {
      future::plan(previous_plan)
    }
  }
)
