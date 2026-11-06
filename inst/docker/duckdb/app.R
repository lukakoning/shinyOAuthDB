library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

issuer <- "https://localhost:18443/realms/shinyoauthdb"
client <- oauth_client(
  oauth_provider_oidc_discover(issuer),
  client_id = "shiny-duckdb", client_secret = "demo-client-secret",
  redirect_uri = "http://localhost:18100",
  scopes = c("openid", "profile", "quack:read")
)

ui <- oauth_ui(fluidPage(
  h2("duckdb demo"),
  actionButton("login", "Sign in"),
  actionButton("logout", "Sign out"),
  textOutput("account"),
  tableOutput("rows"),
  actionButton("probe", "Try a write"),
  textOutput("permission"),
  actionButton("stop", "Stop demo")
), id = "auth", client = client)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())
  observeEvent(input$stop, stopApp())

  con <- oauth_db_duckdb(
    auth$connection, host = "localhost", port = 18444,
    ca_bundle = "/fixtures/tls/ca-cert.pem", required_scopes = "quack:read"
  )
  output$account <- renderText({
    token <- req(auth$token)
    paste("Signed in as", req(token@userinfo$preferred_username))
  })
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, "SELECT marker FROM visible_rows ORDER BY id")
  })
  check <- reactiveVal(NULL)
  observeEvent(input$probe, {
    reference <- req(auth$connection())
    blocked <- tryCatch({
      DBI::dbExecute(con(), "INSERT INTO visible_rows VALUES (3, 'write-test')")
      FALSE
    }, error = function(error) {
      if (grepl("authorization failed|denied|not authorized|not allowed|permission",
        conditionMessage(error), ignore.case = TRUE)) TRUE else stop(error)
    })
    check(list(id = reference$id, blocked = blocked))
  })
  output$permission <- renderText({
    reference <- req(auth$connection())
    result <- req(check())
    req(identical(result$id, reference$id))
    if (result$blocked) "Write rejected by database" else "Write was allowed"
  })
}

shinyApp(ui, server, uiPattern = ".*")
