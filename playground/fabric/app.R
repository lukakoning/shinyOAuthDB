# From the repository root: shiny::runApp("playground/fabric", port = 8100)
library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)
source("queries.R", local = TRUE)

# Reuse the existing Fabric playground settings. OAUTHDB_* also works.
setting <- function(name, fallback, default = "") Sys.getenv(name, Sys.getenv(fallback, default))
tenant <- setting("ENTRA_TENANT_ID", "OAUTHDB_TENANT_ID")
client_id <- setting("ENTRA_CLIENT_ID", "OAUTHDB_CLIENT_ID")
secret <- setting("ENTRA_CLIENT_SECRET", "OAUTHDB_CLIENT_SECRET")
redirect <- setting("ENTRA_REDIRECT_URI", "OAUTHDB_REDIRECT_URI", "http://localhost:8100/")
workspace_name <- Sys.getenv("FABRIC_SHINY_WORKSPACE", "fabricqueryr-shiny-dhrkoning")
mode <- match.arg(Sys.getenv("FABRIC_SHINY_AUTH", "auto"), c("auto", "delegated", "sandbox"))
if (mode == "auto") mode <- if (any(nzchar(c(tenant, client_id, secret)))) "delegated" else "sandbox"
services <- c("fabric", "sql", "dax", "kql", "onelake", "graphql")
client <- if (mode == "delegated") oauth_db_microsoft_client(services,
  tenant_id = tenant, client_id = client_id, client_secret = secret, redirect_uri = redirect) else NULL
shared_token <- if (mode == "sandbox") fabric_demo_shared_token() else NULL

ui <- fluidPage(
  titlePanel("Fabric with shinyOAuthDB"),
  p(workspace_name),
  p(if (mode == "delegated") "Queries use the signed-in visitor's permissions." else
    "Shared sandbox identity: queries use the configured sandbox application, not a visitor."),
  sidebarLayout(
    sidebarPanel(
      if (mode == "delegated") tagList(actionButton("login", "Sign in"), actionButton("logout", "Sign out")),
      selectInput("source", "Data source", fabric_demo_sources),
      conditionalPanel("['warehouse', 'lakehouse'].includes(input.source)",
        selectInput("backend", "SQL driver", c("ODBC" = "odbc", "ADBC" = "adbc")),
        numericInput("min_id", "Minimum SQL ID", 1, min = 1, max = 3, step = 1)),
      conditionalPanel("['dax', 'dax_arrow', 'kql'].includes(input.source)",
        selectInput("category", "Category", c("All", "A", "B"))),
      actionButton("run", "Load data"),
      actionButton("discover", "Refresh discovered items")
    ),
    mainPanel(
      p("Choose a source and load its seeded sample data. A missing fixture affects only that source."),
      tableOutput("rows"),
      conditionalPanel("['dax', 'dax_arrow'].includes(input.source)", plotOutput("totals", height = 240)),
      tags$details(tags$summary("Discovered items"), tableOutput("items"))
    )
  )
)
if (mode == "delegated") ui <- oauth_ui(ui, id = "auth", client = client)

server <- function(input, output, session) {
  if (mode == "delegated") {
    auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
    observeEvent(input$login, auth$request_login())
    observeEvent(input$logout, auth$logout())
    # One ordinary credential accessor per service. Native calls stay below.
    callbacks <- setNames(lapply(services, function(service) {
      oauth_db_fabric(auth$connection, service = service)
    }), services)
  } else {
    callbacks <- setNames(lapply(services, function(service) function() shared_token), services)
  }

  sandbox <- reactive({
    callback <- callbacks$fabric()
    input$discover
    fabric_demo_discover(callback, workspace_name)
  })
  output$items <- renderTable(fabric_demo_read("discovery", sandbox(), NULL))

  # Ordinary reactive code: after the first load, controls and authorization
  # changes rerun this block. Logout clears the previous result.
  rows <- reactive({
    source <- input$source
    callback <- callbacks[[fabric_demo_services[[source]]]]()
    current <- sandbox()
    input$min_id
    input$category
    input$backend
    req(input$run > 0L)
    fabric_demo_read(source, current, callback,
      min_id = input$min_id, category = input$category, backend = input$backend,
      shared = mode == "sandbox")
  })
  output$rows <- renderTable(rows())
  output$totals <- renderPlot({
    req(input$source %in% c("dax", "dax_arrow"))
    data <- rows()
    barplot(data$Amount, names.arg = data$Category, ylab = "Amount", col = "#267c9d")
  })
}

app <- shinyApp(ui, server, uiPattern = ".*")
app
