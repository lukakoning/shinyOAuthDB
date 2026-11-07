# Shared app code; edit this file to try a different UI.
ui <- oauth_ui(fluidPage(
  tags$style(".container-fluid { max-width: 960px; }"),
  h2(demo_title),
  p("Sign in with your own account. The platform applies your existing data permissions."),
  if (exists("demo_context")) p(demo_context),
  h3("1. Sign in"),
  actionButton("login", "Sign in", class = "btn-primary"), actionButton("logout", "Sign out"),
  textOutput("account"),
  h3("2. Check your database identity"), pre(example_query), p(query_notice),
  uiOutput("query_actions"),
  textOutput("query_status"), tableOutput("rows"),
  if (exists("result_explanation")) p(result_explanation),
  h3("3. Try your own query"),
  p("Edit app.R to read one of your tables, or change the UI in demo-ui.R. Save and reload the browser to try it. SQL syntax and table names must match your platform."),
  p(a("Setup and query guide", href = if (exists("demo_guide")) demo_guide else "https://lukakoning.github.io/shinyOAuthDB/articles/cloud-demos.html")),
  p("Back to setup stops the app and returns to the R console to review or change settings. Stop demo ends the local app; cloud services keep their own settings."),
  actionButton("setup", "Back to setup"), actionButton("stop", "Stop demo")
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
