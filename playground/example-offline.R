# A complete Shiny app you can run without credentials or a database server.
# The A/B authorizations and seeded SQLite rows are local demonstration fixtures.
# Real OAuth and database grants are exercised by the PostgreSQL/Keycloak fixture.
library(shiny)
library(shinyOAuthDB)
library(DBI)
library(RSQLite)

db_source <- shinyOAuthDB::oauth_db_custom(
  backend = "offline_sqlite", scopes = "demo.read", target = NULL,
  connect = function(config, token_provider) {
    user <- sub("^offline-fixture-", "", token_provider())
    connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
    DBI::dbWriteTable(connection, "demo_rows", data.frame(
      user = rep(user, 2L), visible_marker = paste0(user, c("-first", "-second"))
    ))
    connection
  }
)

ui <- shiny::fluidPage(
  shiny::titlePanel("shinyOAuthDB: local SQLite lifecycle"),
  shiny::p("Choose a simulated user, query twice to reuse the connection, then switch user or sign out."),
  shiny::actionButton("select_a", "Use simulated user A"),
  shiny::actionButton("select_b", "Use simulated user B"),
  shiny::actionButton("logout", "Sign out"),
  shiny::numericInput("value", "Bound example value", 7L, min = 0, max = 1000000, step = 1),
  shiny::actionButton("run_sync", "Run native call"),
  shiny::h4("Connection status"), shiny::verbatimTextOutput("status"),
  shiny::textOutput("sync_error"), shiny::tableOutput("sync_result")
)

server <- function(input, output, session) {
  authorization <- shiny::reactiveVal(NULL)
  login_number <- 0L

  # This public adapter also supports an application's own authorization object.
  # Its callbacks belong to one specific grant and stop working after replacement.
  select_user <- function(user) {
    login_number <<- login_number + 1L
    id <- paste("offline", user, login_number, sep = "-")
    expires_at <- as.numeric(Sys.time()) + 3600
    is_current <- function() {
      domain <- shiny::getDefaultReactiveDomain()
      !isTRUE(session$isClosed()) && !is.null(domain) &&
        identical(domain$rootScope(), session$rootScope()) && identical(authorization()$id, id)
    }
    authorization(shinyOAuthDB::oauth_db_authorization(
      id = id,
      access_token = function(required_scopes, min_valid_for, force_refresh, async) {
        if (!is_current() || !all(required_scopes %in% "demo.read") ||
            as.numeric(Sys.time()) + min_valid_for >= expires_at) {
          stop("The simulated authorization is unavailable.", call. = FALSE)
        }
        token <- paste0("offline-fixture-", user)
        if (async) promises::promise_resolve(token) else token
      },
      has_scopes = function(scopes) is_current() && all(scopes %in% "demo.read")
    ))
  }
  shiny::observeEvent(input$select_a, select_user("A"))
  shiny::observeEvent(input$select_b, select_user("B"))
  shiny::observeEvent(input$logout, authorization(NULL))

  db <- shinyOAuthDB::oauth_db_session(
    db_source, authorization = authorization, session = session,
    connection_policy = "session"
  )
  owner <- shiny::reactive({
    connection <- authorization()
    if (is.null(connection)) NULL else list(id = connection$id, generation = db$generation())
  })
  observed_owner <- shiny::reactiveVal(NULL)
  last_result <- shiny::reactiveVal(NULL)
  last_error <- shiny::reactiveVal(NULL)
  shiny::observeEvent(owner(), {
    if (!identical(observed_owner(), owner())) {
      observed_owner(owner())
      last_result(NULL)
      last_error(NULL)
    }
  }, ignoreNULL = FALSE, priority = 100)

  shiny::observeEvent(input$run_sync, {
    captured_owner <- owner()
    shiny::req(captured_owner)
    value <- input$value
    shiny::req(is.numeric(value), length(value) == 1L, is.finite(value),
               value >= 0, value <= 1000000, value == floor(value))
    last_result(NULL)
    last_error(NULL)
    tryCatch({
      rows <- DBI::dbGetQuery(db$connection(),
        "SELECT user, visible_marker, ? AS requested_value FROM demo_rows",
        params = list(as.integer(value)))
      if (identical(captured_owner, owner())) {
        last_result(list(owner = captured_owner, value = rows))
      }
    }, error = function(e) {
      if (identical(captured_owner, owner())) {
        last_error("The local database query failed.")
      }
    })
  })
  sync_result <- shiny::reactive({
    result <- last_result()
    shiny::req(result, identical(result$owner, owner()))
    result$value
  })
  output$status <- shiny::renderPrint(db$status())
  output$sync_error <- shiny::renderText(last_error())
  output$sync_result <- shiny::renderTable(sync_result())
}

app <- shiny::shinyApp(ui, server)
port <- suppressWarnings(as.integer(Sys.getenv("OAUTHDB_PORT", "8100")))
if (length(port) != 1L || is.na(port) || port < 1L || port > 65535L) {
  stop("OAUTHDB_PORT must be a valid TCP port.", call. = FALSE)
}
shiny::runApp(app, host = "127.0.0.1", port = port, launch.browser = FALSE)
