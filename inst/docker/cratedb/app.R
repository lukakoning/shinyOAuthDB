library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

issuer <- "https://localhost:18443/realms/shinyoauthdb"
client <- oauth_client(
  oauth_provider_oidc_discover(issuer),
  client_id = "shiny-cratedb", client_secret = "demo-client-secret",
  redirect_uri = "http://localhost:18100",
  scopes = c("openid", "profile", "database.read")
)

ui <- oauth_ui(fluidPage(
  tags$style(".container-fluid { max-width: 960px; }"),
  h2("CrateDB OAuth demo"),
  p("Run SQL over HTTPS using the signed-in CrateDB account."),
  p("Both demo accounts see the same rows and have read-only access. Check write permission below to try an insert."),
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
  h3("3. Check write permission"),
  p("This attempts an insert into the disposable sample data. The demo accounts should be refused by the database."),
  actionButton("probe", "Check write permission"),
  textOutput("permission"),
  p(a("Set up your own CrateDB data source", href = "https://lukakoning.github.io/shinyOAuthDB/articles/cratedb.html")),
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

  database <- oauth_db_cratedb_api(
    auth$connection, url = "https://localhost:18444/_sql",
    ca_bundle = "/fixtures/tls/ca-cert.pem"
  )
  output$account <- renderText({
    token <- req(auth$token)
    paste("Signed in as", req(token@userinfo$preferred_username))
  })
  output$rows <- renderTable({
    database$query("SELECT marker FROM visible_rows ORDER BY id")
  })
  check <- reactiveVal(NULL)
  observeEvent(input$probe, {
    reference <- req(auth$connection())
    blocked <- tryCatch({
      database$execute("INSERT INTO visible_rows VALUES (3, 'write-test')")
      FALSE
    }, error = function(error) {
      # CrateDB reports a missing DML privilege as HTTP 401. Confirm that
      # the same account can still read before treating this as a denial.
      if (inherits(error, "shinyOAuthDB_request_failed") && error$status == 401L) {
        tryCatch({
          database$query("SELECT marker FROM visible_rows ORDER BY id")
          TRUE
        }, error = function(error) NA)
      } else NA
    })
    check(list(id = reference$id, blocked = blocked))
  })
  output$permission <- renderText({
    reference <- req(auth$connection())
    result <- req(check())
    req(identical(result$id, reference$id))
    if (is.na(result$blocked)) "Could not check write access. Check the connection, then try again." else
      if (result$blocked) "Write rejected by database" else "Write was allowed"
  })
}

shinyApp(ui, server, uiPattern = ".*")
