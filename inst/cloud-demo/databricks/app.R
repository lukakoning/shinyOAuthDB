library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

settings <- as.list(read.dcf("settings.dcf")[1L, ])
host <- settings$host
client <- oauth_db_databricks_client(
  host = host, client_id = settings$client_id,
  client_secret = if (identical(settings$client_type, "confidential")) {
    Sys.getenv("OAUTHDB_DATABRICKS_CLIENT_SECRET")
  } else NULL,
  redirect_uri = paste0("http://localhost:", settings$port),
  scopes = c("openid", "profile", "email", "offline_access", "sql")
)

# Change this query to read your own tables after the identity example works.
example_query <- "SELECT current_user() AS signed_in_user"

ui <- oauth_ui(fluidPage(
  h2("Your Databricks Shiny demo"),
  p("Sign in with your Databricks account. Your existing data permissions apply."),
  actionButton("login", "Sign in"), actionButton("logout", "Sign out"),
  textOutput("account"),
  h3("Choose a SQL warehouse"),
  p("A SQL warehouse runs the query for this app. Choose one you normally use in Databricks."),
  actionButton("refresh", "Refresh warehouse list"),
  uiOutput("warehouse_controls"),
  textOutput("warehouse_status"),
  h3("Run the example"),
  pre(example_query),
  p("Running SQL can start a stopped warehouse and use your normal compute credits."),
  actionButton("run", "Run example query"),
  textOutput("query_status"), tableOutput("rows"),
  p("Edit app.R, save and reload the browser to change the query or UI."),
  actionButton("setup", "Back to setup"), actionButton("stop", "Stop demo")
), id = "auth", client = client)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())
  observeEvent(input$setup, stopApp("setup"))
  observeEvent(input$stop, stopApp())

  database <- oauth_db_databricks_api(auth$connection, host = host, required_scopes = "sql")
  current <- reactive({
    reference <- tryCatch(auth$connection(), shiny.silent.error = function(error) NULL)
    if (is.null(reference) || !isTRUE(reference$has_scopes("sql"))) NULL else reference
  })
  owner <- reactiveVal(NULL)
  warehouses <- reactiveVal(NULL)
  binding <- reactiveVal(NULL)
  result <- reactiveVal(NULL)
  warehouse_status <- reactiveVal("")
  query_status <- reactiveVal("")

  observe({
    reference <- current()
    id <- if (is.null(reference)) NULL else reference$id
    if (!identical(id, isolate(owner()))) {
      owner(id)
      warehouses(NULL)
      binding(NULL)
      result(NULL)
      warehouse_status("")
      query_status("")
    }
  }, priority = 100)

  output$account <- renderText({
    req(current())
    "Signed in. Select a warehouse, then run the query to see your database identity."
  })

  observeEvent(list(input$refresh, owner()), {
    reference <- req(current())
    id <- reference$id
    available <- tryCatch(database$warehouses(), error = function(error) {
      warehouse_status("Couldn't list warehouses. Check SQL access or refresh your sign-in. You can also enter a known ID or HTTP path below.")
      NULL
    })
    now <- current()
    if (is.null(now) || !identical(now$id, id) || is.null(available)) return()
    warehouses(list(owner = id, data = available))
    warehouse_status(if (nrow(available)) {
      "Listing a warehouse doesn't establish permission to query it; Databricks checks that when you run SQL."
    } else "No warehouses were listed. Open SQL Warehouses in your workspace to find one or ask for access, or enter a known ID or HTTP path below.")
  }, ignoreNULL = FALSE)

  output$warehouse_controls <- renderUI({
    reference <- req(current())
    req(reference$has_scopes("sql"))
    selected <- binding()
    if (!is.null(selected) && identical(selected$owner, reference$id)) {
      return(tagList(p(paste("Selected warehouse:", selected$id)),
        p("Sign out and sign in again to choose another warehouse.")))
    }
    available <- warehouses()
    choices <- c("Choose a warehouse" = "")
    if (!is.null(available) && identical(available$owner, reference$id)) {
      rows <- available$data
      choices <- c(choices, stats::setNames(rows$id, paste0(rows$name, " (", rows$state, ")")))
    }
    tagList(selectInput("warehouse", "SQL warehouse", choices = choices),
      textInput("manual_warehouse", "Or enter a warehouse ID / HTTP path", value = settings$warehouse_id %||% ""))
  })

  observeEvent(input$run, {
    reference <- req(current())
    req(reference$has_scopes("sql"))
    id <- reference$id
    selected <- binding()
    if (is.null(selected) || !identical(selected$owner, id)) {
      warehouse <- trimws(if (nzchar(input$manual_warehouse %||% "")) input$manual_warehouse else input$warehouse %||% "")
      warehouse <- sub("^/sql/1[.]0/warehouses/", "", warehouse)
      if (!grepl("^[A-Za-z0-9_-]+$", warehouse)) {
        query_status("Choose a warehouse, or paste its ID or HTTP path from SQL Warehouses > Connection details.")
        return()
      }
      selected <- list(owner = id, id = warehouse,
        get = oauth_db_databricks(auth$connection, host = host, warehouse_id = warehouse, required_scopes = "sql"))
      binding(selected)
    }
    result(NULL)
    rows <- tryCatch({
      connection <- selected$get()
      DBI::dbGetQuery(connection, example_query)
    }, error = function(error) {
      query_status("Couldn't run the query. Check CAN USE on this warehouse. Queries against your own tables also need catalog/schema access and SELECT permission. Retry explicitly when ready.")
      NULL
    })
    now <- current()
    if (is.null(rows) || is.null(now) || !identical(now$id, id)) return()
    result(list(owner = id, data = rows))
    query_status("Query completed using the signed-in person's database permissions.")
  })

  output$warehouse_status <- renderText({ req(current()); warehouse_status() })
  output$query_status <- renderText({ req(current()); query_status() })
  output$rows <- renderTable({
    reference <- req(current())
    req(reference$has_scopes("sql"))
    value <- req(result())
    req(identical(value$owner, reference$id))
    value$data
  })
}

`%||%` <- function(value, otherwise) if (is.null(value)) otherwise else value
shinyApp(ui, server, uiPattern = ".*")
