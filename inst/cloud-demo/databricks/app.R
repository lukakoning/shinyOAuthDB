library(shiny)
library(bslib)
library(shinyOAuth)
library(shinyOAuthDB)

settings <- as.list(read.dcf("settings.dcf")[1L, ])
host <- settings$host

client <- oauth_db_databricks_client(
  host = host,
  client_id = settings$client_id,
  client_secret = if (identical(settings$client_type, "confidential")) {
    Sys.getenv("OAUTHDB_DATABRICKS_CLIENT_SECRET")
  } else {
    NULL
  },
  redirect_uri = paste0("http://localhost:", settings$port),
  scopes = c("openid", "profile", "email", "offline_access", "sql")
)

# Change this query to read your own tables after the identity example works.
example_query <- "SELECT current_user() AS signed_in_user"

ui <- oauth_ui(
  page_sidebar(
    title = h2("Databricks Shiny demo", class = "h3 mb-0"),

    theme = bs_theme(
      version = 5,
      primary = "#17646c",
      bg = "#f4f6f9",
      fg = "#23313d",
      base_font = "system-ui"
    ),

    fillable = FALSE,
    lang = "en",

    sidebar = sidebar(
      width = 320,
      bg = "#fff",
      fg = "#23313d",
      open = list(desktop = "always", mobile = "always-above"),
      h3("1. Sign in", class = "h5"),
      p("Use your Databricks account. Your existing data permissions apply."),
      div(
        class = "d-flex gap-2 flex-wrap",
        actionButton("login", "Sign in", class = "btn-primary"),
        actionButton("logout", "Sign out")
      ),
      div(role = "status", textOutput("account")),
      hr(),
      tags$dl(
        class = "demo-details",
        tags$dt("Workspace"),
        tags$dd(code(host)),
        tags$dt("Connection"),
        tags$dd("DBI / brickster with your OAuth token")
      ),
      p(a(
        "Databricks setup and query guide",
        href = "https://lukakoning.github.io/shinyOAuthDB/articles/databricks.html"
      )),
      actionButton("setup", "Back to setup"),
      p("Return to the R console to review settings.", class = "demo-note"),
      actionButton("stop", "Stop demo"),
      p(
        "Ends this local app. It doesn't stop a shared warehouse.",
        class = "demo-note"
      )
    ),

    tags$style(
      ".demo-details { display: grid; grid-template-columns: minmax(7rem, 1fr) minmax(0, 3fr); gap: .6rem 1rem; }
    .demo-details dt { font-size: .9rem; color: #485867; }
    .demo-details dd { margin: 0; overflow-wrap: anywhere; }
    .sidebar .demo-details { grid-template-columns: 1fr; gap: .25rem; }
    .sidebar .demo-details dd { margin-bottom: .5rem; }
    @media (max-width: 575px) { .main .demo-details { grid-template-columns: 1fr; gap: .25rem; } .main .demo-details dd { margin-bottom: .6rem; } }
    .demo-details code { color: inherit; white-space: normal; overflow-wrap: anywhere; }
    .demo-results { overflow-x: auto; }
    .demo-note { color: #485867; font-size: .95rem; }
    .btn { min-height: 44px; }
    pre { white-space: pre-wrap; overflow-wrap: anywhere; }
    .card-header h3 { font-size: 1.1rem; margin: 0; }
    .card, .sidebar { background: #fff; }
    .bslib-card { margin-top: 1rem; }
    .card-body > p { margin-bottom: 0; }"
    ),

    p(
      "Run SQL from Shiny with your Databricks identity and data permissions.",
      class = "lead"
    ),

    card(
      fill = FALSE,
      card_header(h3("2. Choose a SQL warehouse")),
      p(
        "A SQL warehouse runs your query. Choose one you normally use in Databricks."
      ),
      uiOutput("refresh_actions"),
      uiOutput("warehouse_controls"),
      div(role = "status", textOutput("warehouse_status"))
    ),

    card(
      fill = FALSE,
      card_header(h3("3. Check your database identity")),
      pre(example_query),
      p(
        "Running SQL can start a stopped warehouse and use your normal compute credits.",
        class = "demo-note"
      ),
      uiOutput("query_actions"),
      div(role = "status", textOutput("query_status")),
      div(class = "demo-results", tableOutput("rows")),
      p(
        "The result shows who connects to Databricks. A visible warehouse still needs CAN USE; your own tables also need catalog/schema access and SELECT permission."
      )
    ),

    tags$details(
      tags$summary("Try your own query"),
      p(
        "Edit example_query in app.R to read one of your tables. Save and reload the browser. You can change the app layout in the same file."
      )
    )
  ),

  id = "auth",
  client = client
)

server <- function(input, output, session) {
  auth <- oauth_module_server(
    "auth",
    client,
    auto_redirect = FALSE,
    async = TRUE
  )

  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())

  observeEvent(input$setup, stopApp("setup"))
  observeEvent(input$stop, stopApp())

  database <- oauth_db_databricks_api(
    auth$connection,
    host = host,
    required_scopes = "sql"
  )

  current <- reactive({
    reference <- tryCatch(
      auth$connection(),
      shiny.silent.error = function(error) NULL
    )

    if (is.null(reference) || !isTRUE(reference$has_scopes("sql"))) {
      NULL
    } else {
      reference
    }
  })

  owner <- reactiveVal(NULL)

  warehouse_task <- oauth_db_task(database, method = "warehouses")

  warehouses <- reactive({
    reference <- current()

    if (is.null(reference)) {
      return(NULL)
    }

    value <- tryCatch(warehouse_task$result(), error = function(error) NULL)

    if (is.null(value)) NULL else list(owner = reference$id, data = value)
  })

  binding <- reactiveVal(NULL)

  result <- reactive({
    reference <- current()
    selected <- binding()

    if (
      is.null(reference) ||
        is.null(selected) ||
        !identical(selected$owner, reference$id)
    ) {
      return(NULL)
    }

    value <- tryCatch(selected$task$result(), error = function(error) NULL)

    if (is.null(value)) NULL else list(owner = reference$id, data = value)
  })

  warehouse_status <- reactive({
    if (warehouse_task$status() == "running") {
      return("Listing warehouses...")
    }

    if (warehouse_task$status() == "error") {
      return(
        "Couldn't list warehouses. Check SQL access or refresh your sign-in. You can also enter a known ID or HTTP path below."
      )
    }

    value <- warehouses()

    if (is.null(value)) {
      return("")
    }

    if (nrow(value$data)) {
      "Listing a warehouse doesn't establish permission to query it; Databricks checks that when you run SQL."
    } else {
      "No warehouses were listed. Open SQL Warehouses in your workspace to find one or ask for access, or enter a known ID or HTTP path below."
    }
  })

  query_status <- reactiveVal("")

  observe(
    {
      reference <- current()
      id <- if (is.null(reference)) NULL else reference$id

      if (!identical(id, isolate(owner()))) {
        owner(id)
        binding(NULL)
        query_status("")
      }
    },
    priority = 100
  )

  output$account <- renderText({
    if (
      !is.null(auth$error) && !auth$error %in% c("logged_out", "access_denied")
    ) {
      return(
        "Sign-in didn't finish. Check the workspace, registered return address and OAuth registration using the guide below, then try again."
      )
    }

    reference <- tryCatch(auth$connection(), error = function(error) NULL)

    if (is.null(reference)) {
      return("Not signed in. Click Sign in to use your Databricks account.")
    }

    if (is.null(current())) {
      return(
        "Your sign-in needs SQL access. Check the SQL scope in the OAuth registration, or use Back to setup."
      )
    }

    if (!is.null(result())) {
      return(
        "Signed in. The result uses this account and the selected warehouse."
      )
    }

    if (!is.null(binding())) {
      return("Signed in. Run the query using the selected warehouse.")
    }

    "Signed in. Select a warehouse, then run the query to see your database identity."
  })

  output$query_actions <- renderUI(actionButton(
    "run",
    "Run example query",
    class = "btn-primary",
    disabled = if (is.null(current())) TRUE else NULL
  ))

  output$refresh_actions <- renderUI(actionButton(
    "refresh",
    "Refresh warehouse list",
    disabled = if (is.null(current())) TRUE else NULL
  ))

  observeEvent(
    list(input$refresh, owner()),
    {
      req(current())

      warehouse_task$invoke()
    },
    ignoreNULL = FALSE
  )

  output$warehouse_controls <- renderUI({
    reference <- req(current())
    req(reference$has_scopes("sql"))
    selected <- binding()

    if (!is.null(selected) && identical(selected$owner, reference$id)) {
      return(tagList(
        tags$dl(
          class = "demo-details",
          tags$dt("Selected warehouse"),
          tags$dd(code(selected$id)),
          tags$dt("HTTP path"),
          tags$dd(code(paste0("/sql/1.0/warehouses/", selected$id)))
        ),
        p("Sign out and sign in again to choose another warehouse.")
      ))
    }

    available <- warehouses()
    choices <- c("Choose a warehouse" = "")

    if (!is.null(available) && identical(available$owner, reference$id)) {
      rows <- available$data

      choices <- c(
        choices,
        stats::setNames(rows$id, paste0(rows$name, " (", rows$state, ")"))
      )
    }

    tagList(
      selectInput("warehouse", "SQL warehouse", choices = choices),
      textInput(
        "manual_warehouse",
        "Or enter a warehouse ID / HTTP path",
        value = settings$warehouse_id %||% ""
      )
    )
  })

  observeEvent(input$run, {
    reference <- req(current())
    req(reference$has_scopes("sql"))
    id <- reference$id
    selected <- binding()

    if (is.null(selected) || !identical(selected$owner, id)) {
      warehouse <- trimws(
        if (nzchar(input$manual_warehouse %||% "")) {
          input$manual_warehouse
        } else {
          input$warehouse %||% ""
        }
      )

      warehouse <- sub("^/sql/1[.]0/warehouses/", "", warehouse)

      if (!grepl("^[A-Za-z0-9_-]+$", warehouse)) {
        query_status(
          "Choose a warehouse, or paste its ID or HTTP path from SQL Warehouses > Connection details."
        )

        return()
      }

      selected <- list(
        owner = id,
        id = warehouse,
        get = oauth_db_databricks(
          auth$connection,
          host = host,
          warehouse_id = warehouse,
          required_scopes = "sql"
        )
      )

      selected$task <- oauth_db_task(selected$get)

      binding(selected)
    }

    query_status("")
    selected$task$invoke(example_query)
  })

  output$warehouse_status <- renderText({
    req(current())

    warehouse_status()
  })

  output$query_status <- renderText({
    req(current())
    selected <- binding()

    if (is.null(selected)) {
      return(query_status())
    }

    status <- selected$task$status()

    if (status == "running") {
      return("Running query...")
    }

    if (status == "error") {
      return(
        "Couldn't run the query. Check CAN USE, catalog/schema access and SELECT permission on this warehouse. Check SQL syntax if you edited the query. Retry explicitly when ready."
      )
    }

    if (!is.null(result())) {
      "Query completed using the signed-in person's database permissions."
    } else {
      query_status()
    }
  })

  output$rows <- renderTable({
    reference <- req(current())
    req(reference$has_scopes("sql"))
    value <- req(result())
    req(identical(value$owner, reference$id))

    value$data
  })
}

`%||%` <- function(value, otherwise) if (is.null(value)) otherwise else value

shinyApp(ui, server, uiPattern = ".*", onStart = function() {
  mirai::daemons(2)

  onStop(function() mirai::daemons(0))
})

# Open the printed app URL in your regular browser.
# (viewers in RStudio/Positron/etc. cannot perform necessary redirects)
