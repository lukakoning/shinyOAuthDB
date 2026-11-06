library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

issuer <- "https://localhost:18443/realms/shinyoauthdb"
client <- oauth_client(
  oauth_provider_oidc_discover(issuer),
  client_id = "shiny-opensearch", client_secret = "demo-client-secret",
  redirect_uri = "http://localhost:18100",
  scopes = c("openid", "profile", "search.read")
)

ui <- oauth_ui(fluidPage(
  h2("opensearch demo"),
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

  database <- oauth_db_opensearch_api(
    auth$connection, url = "https://localhost:9200", required_scopes = "search.read",
    ca_bundle = "/fixtures/tls/ca-cert.pem"
  )
  output$account <- renderText({
    token <- req(auth$token)
    paste("Signed in as", req(token@userinfo$preferred_username))
  })
  output$rows <- renderTable({
    result <- database$search("orders", body = list(size = 20L, sort = list("id")))
    data.frame(marker = vapply(result$hits$hits, function(hit) hit$`_source`$marker, ""))
  })
  check <- reactiveVal(NULL)
  observeEvent(input$probe, {
    reference <- req(auth$connection())
    blocked <- tryCatch({
      database$request(c("orders", "_doc", "write-test"), method = "PUT", body = list(marker = "write-test"))
      FALSE
    }, error = function(error) {
      if (inherits(error, "shinyOAuthDB_request_failed") && error$status == 403L) TRUE else stop(error)
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
