# Shared app code; edit this file to try a different UI.
library(bslib)

details <- if (exists("demo_details")) Filter(length, demo_details) else list()
ui <- oauth_ui(page_sidebar(
  title = h2(demo_title, class = "h3 mb-0"),
  theme = bs_theme(version = 5, primary = "#17646c", bg = "#f4f6f9", fg = "#23313d", base_font = "system-ui"),
  fillable = FALSE, lang = "en",
  sidebar = sidebar(width = 320, bg = "#fff", fg = "#23313d", open = list(desktop = "always", mobile = "always-above"),
    h3("1. Sign in", class = "h5"),
    p("Use your own platform account. Your existing data permissions apply."),
    div(class = "d-flex gap-2 flex-wrap",
      actionButton("login", "Sign in", class = "btn-primary"), actionButton("logout", "Sign out")),
    div(role = "status", textOutput("account")),
    hr(),
    p(a("Setup and query guide", href = if (exists("demo_guide")) demo_guide else "https://lukakoning.github.io/shinyOAuthDB/articles/cloud-demos.html")),
    actionButton("setup", "Back to setup"),
    p("Return to the R console to review or change settings.", class = "demo-note"),
    actionButton("stop", "Stop demo"),
    p("Ends this local app. Cloud compute and submitted jobs keep their own settings.", class = "demo-note")
  ),
  tags$style(".demo-details { display: grid; grid-template-columns: minmax(7rem, 1fr) minmax(0, 3fr); gap: .6rem 1rem; }
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
    .card-body > p { margin-bottom: 0; }"),
  p("Query your data platform from Shiny, using the account of the person who signs in.", class = "lead"),
  card(fill = FALSE,
    card_header(h3("2. Check your database identity")),
    pre(example_query),
    p(query_notice, class = "demo-note"),
    uiOutput("query_actions"),
    div(role = "status", textOutput("query_status")),
    div(class = "demo-results", tableOutput("rows")),
    if (exists("result_explanation")) p(result_explanation)
  ),
  card(fill = FALSE,
    card_header(h3("About this connection")),
    tags$dl(class = "demo-details", Map(function(label, value) tagList(
      tags$dt(label), tags$dd(code(value))), names(details), details)),
    if (exists("demo_context")) p(demo_context),
    if (exists("platform_note")) p(platform_note)
  ),
  tags$details(
    tags$summary("3. Try your own query"),
    p("Edit example_query in app.R to read one of your tables. Use SQL syntax and table names for your platform. Save and reload the browser to try it."),
    p("You can also change the app layout in demo-ui.R. Your edits are kept when you restart this demo.")
  )
), id = "auth", client = client)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())
  observeEvent(input$setup, stopApp("setup"))
  observeEvent(input$stop, stopApp())
  current <- reactive({
    reference <- tryCatch(auth$connection(), shiny.silent.error = function(error) NULL)
    if (is.null(reference)) return(NULL)
    # Named API tokens can be acquired lazily when the query button is clicked.
    if (!is.null(query_target)) {
      status <- tryCatch(reference$summary(target = query_target)$status, error = function(error) NULL)
      if (is.null(status)) return(NULL)
      if (identical(status, "not_acquired")) return(reference)
    }
    if (isTRUE(reference$has_scopes(query_scopes, target = query_target))) reference else NULL
  })
  owner <- reactiveVal(NULL)
  access <- reactiveVal(NULL)
  result <- reactiveVal(NULL)
  query_status <- reactiveVal("")
  observe({
    reference <- current()
    id <- if (is.null(reference)) NULL else reference$id
    allowed <- !is.null(reference) && isTRUE(reference$has_scopes(query_scopes, target = query_target))
    if (!identical(id, isolate(owner())) || !allowed && !is.null(isolate(result()))) {
      owner(id)
      access(NULL)
      result(NULL)
      query_status("")
    }
  }, priority = 100)
  output$account <- renderText({
    if (!is.null(auth$error) && !auth$error %in% c("logged_out", "access_denied")) {
      return("Sign-in didn't finish. Check the registered return address and app registration using the setup guide below, then try again.")
    }
    reference <- tryCatch(auth$connection(), error = function(error) NULL)
    if (is.null(reference)) return("Not signed in. Click Sign in to use your own platform account.")
    if (is.null(current())) return("Your sign-in needs query access. Check the app's requested permissions, or use Back to setup to correct the registration.")
    "Signed in. Click Run example query to check your database identity."
  })
  output$query_actions <- renderUI(actionButton("run", "Run example query", class = "btn-primary",
    disabled = if (is.null(current())) TRUE else NULL))
  observeEvent(input$run, {
    reference <- req(current())
    id <- reference$id
    result(NULL)
    rows <- tryCatch({
      selected <- access()
      if (is.null(selected) || !identical(selected$owner, id)) {
        selected <- list(owner = id, value = make_access(auth$connection))
        access(selected)
      }
      run_query(selected$value)
    }, error = function(error) {
      query_status(paste(query_help, "If you edited the SQL, check its syntax and table names too."))
      NULL
    })
    now <- current()
    if (is.null(rows) || is.null(now) || !identical(now$id, id)) return()
    result(list(owner = id, data = rows))
    query_status("Query completed using the signed-in person's database permissions.")
  })
  output$query_status <- renderText({ req(current()); query_status() })
  output$rows <- renderTable({
    reference <- req(current())
    req(reference$has_scopes(query_scopes, target = query_target))
    value <- req(result())
    req(identical(value$owner, reference$id))
    value$data
  })
}
shinyApp(ui, server, uiPattern = ".*")
