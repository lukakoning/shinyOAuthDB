# Try account changes and sign-out with simulated users and SQLite; no OAuth requests.
library(shiny)
library(shinyOAuthDB)

ui <- fluidPage(
  titlePanel("shinyOAuthDB: local SQLite demo"),
  actionButton("select_a", "Use simulated user A"),
  actionButton("select_b", "Use simulated user B"),
  actionButton("logout", "Sign out"),
  tableOutput("rows")
)

server <- function(input, output, session) {
  authorization <- reactiveVal(NULL)
  login_number <- 0L
  select_user <- function(user) {
    login_number <<- login_number + 1L
    id <- paste(user, login_number, sep = "-")
    # This list is a test fixture for the shinyOAuth connection methods.
    authorization(list(
      id = id,
      access_token = function(...) {
        stopifnot(identical(authorization()$id, id))
        paste0("fixture-", user)
      },
      has_scopes = function(...) identical(authorization()$id, id)
    ))
  }
  observeEvent(input$select_a, select_user("A"))
  observeEvent(input$select_b, select_user("B"))
  observeEvent(input$logout, authorization(NULL))

  con <- oauth_db_connect(authorization, connect = function(token) {
    user <- sub("^fixture-", "", token)
    con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    DBI::dbWriteTable(con, "example", data.frame(
      user = user, message = c("First row", "Second row")
    ))
    con
  })
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, "SELECT * FROM example")
  })
}

app <- shinyApp(ui, server)
if (interactive()) runApp(app, port = as.integer(Sys.getenv("OAUTHDB_PORT", "8100")),
                          launch.browser = FALSE)
