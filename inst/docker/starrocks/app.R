library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

issuer <- "https://localhost:18443/realms/shinyoauthdb"
client <- oauth_client(
  oauth_provider_oidc_discover(issuer),
  client_id = "shiny-db", client_secret = "demo-client-secret",
  redirect_uri = "http://localhost:18100",
  scopes = c("openid", "profile", "database.read")
)

ui <- oauth_ui(fluidPage(
  tags$style(".container-fluid { max-width: 960px; }"),
  h2("StarRocks OAuth demo"),
  p("Query StarRocks using the signed-in account and its database permissions."),
  p("Sign in as alice, then sign out and try bob. The same request returns different rows because the data source applies their permissions."),
  h3("1. Sign in"),
  p("Demo accounts: ", code("alice / alice-fixture-password"),
    " or ", code("bob / bob-fixture-password"), "."),
  p("Sign-in opens Keycloak, the local sign-in service. Your browser may ask you to allow its local test certificate."),
  actionButton("login", "Sign in", class = "btn-primary"),
  actionButton("logout", "Sign out"),
  textOutput("sign_in_status"),
  textOutput("account"),
  h3("2. See your data"),
  tableOutput("rows"),
  p(a("Set up your own StarRocks data source", href = "https://lukakoning.github.io/shinyOAuthDB/articles/starrocks.html")),
  p("Stop demo removes the local demo services and sample data. Your copied app code is kept."),
  actionButton("stop", "Stop demo")
), id = "auth", client = client)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())
  observeEvent(input$stop, stopApp())

  output$sign_in_status <- renderText({
    if (!is.null(auth$error) && !auth$error %in% c("logged_out", "access_denied")) {
      return("Sign-in didn't finish. Check the local test certificate in your browser, then try Sign in again.")
    }
    reference <- tryCatch(auth$connection(), error = function(error) NULL)
    if (is.null(reference)) "Not signed in. Choose one of the demo accounts above." else "Signed in. Sign out before trying the other account."
  })
  output$account <- renderText({
    token <- req(auth$token)
    paste("Signed in as", req(token@userinfo$preferred_username))
  })

  con <- oauth_db_starrocks(
    auth$connection, server = "localhost", database = "reporting",
    user = function() req(auth$token@userinfo$preferred_username),
    driver = "/usr/lib/x86_64-linux-gnu/odbc/libmyodbc9w.so",
    plugin_dir = "/usr/lib/x86_64-linux-gnu/mysql/libmyodbc9/plugin",
    ssl_ca = "/fixtures/tls/ca-cert.pem"
  )
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, "SELECT marker FROM visible_rows ORDER BY id")
  })
}

shinyApp(ui, server, uiPattern = ".*")
