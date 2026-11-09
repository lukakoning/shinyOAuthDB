library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)
source("queries.R", local = TRUE)

# Reuse the existing Fabric playground settings. OAUTHDB_* also works.
setting <- function(name, fallback, default = "") {
  Sys.getenv(name, Sys.getenv(fallback, default))
}
tenant <- setting("ENTRA_TENANT_ID", "OAUTHDB_TENANT_ID")
client_id <- setting("ENTRA_CLIENT_ID", "OAUTHDB_CLIENT_ID")
secret <- setting("ENTRA_CLIENT_SECRET", "OAUTHDB_CLIENT_SECRET")
redirect <- setting(
  "ENTRA_REDIRECT_URI",
  "OAUTHDB_REDIRECT_URI",
  "http://localhost:8100/"
)
workspace_name <- Sys.getenv(
  "FABRIC_SHINY_WORKSPACE",
  "fabricqueryr-shiny-dhrkoning"
)
mode <- match.arg(
  Sys.getenv("FABRIC_SHINY_AUTH", "auto"),
  c("auto", "delegated", "sandbox")
)
if (mode == "auto") {
  mode <- if (any(nzchar(c(tenant, client_id, secret)))) {
    "delegated"
  } else {
    "sandbox"
  }
}
services <- c("fabric", "sql", "dax", "kql", "onelake", "graphql")
client <- if (mode == "delegated") {
  oauth_db_microsoft_client(
    services,
    tenant_id = tenant,
    client_id = client_id,
    client_secret = secret,
    redirect_uri = redirect
  )
} else {
  NULL
}
# The worker functions carry code and arguments, not the app environment.
worker_functions <- lapply(
  list(
    discover = fabric_demo_discover,
    read = fabric_demo_read,
    item = fabric_demo_item,
    fetch = fabric_demo_fetch,
    shared_token = fabric_demo_shared_token
  ),
  function(fun) eval(parse(text = deparse(fun), keep.source = FALSE), baseenv())
)

ui <- fluidPage(
  titlePanel("Fabric with shinyOAuthDB"),
  p(workspace_name),
  p(
    if (mode == "delegated") {
      "Queries use the signed-in visitor's permissions."
    } else {
      "Shared sandbox identity: queries use the configured sandbox application, not a visitor."
    }
  ),
  sidebarLayout(
    sidebarPanel(
      if (mode == "delegated") {
        tagList(
          actionButton("login", "Sign in"),
          actionButton("logout", "Sign out")
        )
      },
      selectInput("source", "Data source", fabric_demo_sources),
      conditionalPanel(
        "['warehouse', 'lakehouse'].includes(input.source)",
        selectInput(
          "backend",
          "SQL driver",
          c("ODBC" = "odbc", "ADBC" = "adbc")
        ),
        numericInput("min_id", "Minimum SQL ID", 1, min = 1, max = 3, step = 1)
      ),
      conditionalPanel(
        "['dax', 'dax_arrow', 'kql'].includes(input.source)",
        selectInput("category", "Category", c("All", "A", "B"))
      ),
      actionButton("run", "Load data"),
      actionButton("discover", "Refresh discovered items")
    ),
    mainPanel(
      p(
        "Choose a source and load its seeded sample data. A missing fixture affects only that source."
      ),
      tableOutput("rows"),
      conditionalPanel(
        "['dax', 'dax_arrow'].includes(input.source)",
        plotOutput("totals", height = 240)
      ),
      tags$details(tags$summary("Discovered items"), tableOutput("items"))
    )
  )
)
if (mode == "delegated") {
  ui <- oauth_ui(ui, id = "auth", client = client)
}

server <- function(input, output, session) {
  if (mode == "delegated") {
    auth <- oauth_module_server(
      "auth",
      client,
      auto_redirect = FALSE,
      async = TRUE
    )
    observeEvent(input$login, auth$request_login())
    observeEvent(input$logout, auth$logout())
    task_for <- function(source) {
      service <- switch(
        source,
        warehouse = "sql",
        lakehouse = "sql",
        dax = "dax",
        dax_arrow = "dax",
        kql = "kql",
        files = "onelake",
        delta = "onelake",
        mirrored = "onelake",
        graphql = "graphql",
        "fabric"
      )
      targets <- c(fabric = "fabric")
      if (service != "fabric") {
        targets[[service]] <- if (service %in% c("dax", "graphql")) {
          "power_bi"
        } else {
          service
        }
      }
      scopes <- if (service == "graphql") {
        list(
          graphql = "https://analysis.windows.net/powerbi/api/GraphQLApi.Execute.All"
        )
      } else {
        list()
      }
      api <- oauth_db_fabric_api(
        auth$connection,
        targets = targets,
        required_scopes = scopes
      )
      oauth_db_task(api, method = worker_functions$fetch)
    }
  } else {
    task_for <- function(source) {
      running <- NULL
      task <- ExtendedTask$new(function(
        workspace_name,
        source,
        min_id,
        category,
        backend,
        shared,
        helpers
      ) {
        running <<- mirai::mirai(
          {
            # Shared sandbox credentials are read only inside the worker.
            token <- helpers$shared_token()
            helpers$fetch(
              token,
              workspace_name,
              source,
              min_id,
              category,
              backend,
              shared,
              helpers
            )
          },
          workspace_name = workspace_name,
          source = source,
          min_id = min_id,
          category = category,
          backend = backend,
          shared = shared,
          helpers = helpers
        )
        promises::then(running, function(value) {
          running <<- NULL
          value
        })
      })
      session$onSessionEnded(function() {
        if (!is.null(running)) {
          tryCatch(mirai::stop_mirai(running), error = function(error) NULL)
        }
      })
      list(
        invoke = function(...) {
          if (isolate(task$status()) == "running") {
            return(FALSE)
          }
          task$invoke(...)
          TRUE
        },
        result = task$result,
        status = task$status
      )
    }
  }
  tasks <- stats::setNames(
    lapply(unname(fabric_demo_sources), task_for),
    unname(fabric_demo_sources)
  )
  discovery <- task_for("discovery")
  discover <- function() {
    discovery$invoke(
      workspace_name,
      "discovery",
      1L,
      "All",
      "odbc",
      mode == "sandbox",
      worker_functions
    )
  }
  observeEvent(input$discover, discover())
  if (mode == "delegated") {
    previous <- NULL
    observe({
      reference <- auth$connection()
      if (!identical(previous, reference)) {
        previous <<- reference
        if (!is.null(reference)) discover()
      }
    })
  } else {
    observeEvent(TRUE, discover(), once = TRUE)
  }
  output$items <- renderTable(discovery$result())
  active <- reactiveVal(NULL)
  requested <- reactiveVal(NULL)
  parameters <- reactive(list(
    source = req(input$source),
    min_id = input$min_id,
    category = input$category,
    backend = input$backend
  ))
  observeEvent(input$run, {
    values <- parameters()
    selected <- req(tasks[[values$source]])
    if (
      selected$invoke(
        workspace_name,
        values$source,
        values$min_id,
        values$category,
        values$backend,
        mode == "sandbox",
        worker_functions
      )
    ) {
      active(selected)
      requested(values)
    }
  })
  rows <- reactive({
    req(identical(requested(), parameters()))
    selected <- req(active())
    selected$result()
  })
  output$rows <- renderTable(rows())
  output$totals <- renderPlot({
    req(input$source %in% c("dax", "dax_arrow"))
    data <- rows()
    barplot(
      data$Amount,
      names.arg = data$Category,
      ylab = "Amount",
      col = "#267c9d"
    )
  })
}

app <- shinyApp(ui, server, uiPattern = ".*", onStart = function() {
  mirai::daemons(2)
  onStop(function() mirai::daemons(0))
})
app

# From the repository root: shiny::runApp("playground/fabric", port = 8100, launch.browser = FALSE)
# Open the app in your regular browser at http://localhost:8100
# (viewers in RStudio/Positron/etc. cannot perform necessary redirects)
