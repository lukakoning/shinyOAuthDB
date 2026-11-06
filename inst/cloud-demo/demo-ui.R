# Shared app code; edit this file to try a different UI.
ui <- oauth_ui(fluidPage(
  h2(demo_title),
  p("Sign in with your own account. The platform applies your existing data permissions."),
  actionButton("login", "Sign in"), actionButton("logout", "Sign out"),
  textOutput("account"),
  h3("Run the example"), pre(example_query), p(query_notice),
  actionButton("run", "Run example query"),
  textOutput("query_status"), tableOutput("rows"),
  p("Edit app.R to change the SQL or connection code. Save and reload the browser to try it."),
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
    if (is.null(reference) || !isTRUE(reference$has_scopes(query_scopes, target = query_target))) NULL else reference
  })
  owner <- reactiveVal(NULL)
  access <- reactiveVal(NULL)
  result <- reactiveVal(NULL)
  query_status <- reactiveVal("")
  observe({
    reference <- current()
    id <- if (is.null(reference)) NULL else reference$id
    if (!identical(id, isolate(owner()))) {
      owner(id)
      access(NULL)
      result(NULL)
      query_status("")
    }
  }, priority = 100)
  output$account <- renderText({ req(current()); "Signed in. Click Run example query to check your database identity." })
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
      query_status(query_help)
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
    value <- req(result())
    req(identical(value$owner, reference$id))
    value$data
  })
}
shinyApp(ui, server, uiPattern = ".*")
