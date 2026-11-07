library(shiny)
library(bslib)
library(shinyOAuth)
library(shinyOAuthDB)

issuer <- "https://localhost:18443/realms/shinyoauthdb"
client <- oauth_client(
  oauth_provider_oidc_discover(issuer),
  client_id = "shiny-db", client_secret = "demo-client-secret",
  redirect_uri = "http://localhost:18100",
  scopes = c("openid", "profile", "database.read")
)

example_table <- "visible_rows"
example_order <- "row_id.asc"
example_request <- paste0("GET /", example_table, "?order=", example_order)

ui <- oauth_ui(page_sidebar(
  title = h2("PostgREST OAuth demo", class = "h3 mb-0"),
  theme = bs_theme(version = 5, primary = "#17646c", bg = "#f4f6f9", fg = "#23313d", base_font = "system-ui"), fillable = FALSE, lang = "en",
  sidebar = sidebar(width = 320, bg = "#fff", fg = "#23313d", open = list(desktop = "always", mobile = "always-above"),
    h3("1. Sign in", class = "h5"),
    p("Choose a demo account. Sign out before trying the other one."),
    tags$dl(class = "demo-details",
      tags$dt("alice"), tags$dd(code("alice-fixture-password")),
      tags$dt("bob"), tags$dd(code("bob-fixture-password"))
    ),
    div(class = "d-flex gap-2 flex-wrap",
      actionButton("login", "Sign in", class = "btn-primary"),
      actionButton("logout", "Sign out")),
    div(role = "status", textOutput("account"), textOutput("sign_in_status")),
    p("Sign-in opens Keycloak. Your browser may ask you to allow its local test certificate.", class = "demo-note"),
    hr(),
    p(a("Set up your own PostgREST data source", href = "https://lukakoning.github.io/shinyOAuthDB/articles/postgrest.html")),
    actionButton("stop", "Stop demo"),
    p("Stopping removes the demo services and sample data. Your copied app code is kept.", class = "demo-note")
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
  p("Read PostgreSQL data over an API using the signed-in account.", class = "lead"),
  card(fill = FALSE,
    card_header(h3("2. Query sample data")),
    pre(example_request),
    p("Sign in as alice, then sign out and try bob. The same request returns different rows because the data source applies their permissions."),
    conditionalPanel("!output.account", p("Sign in to load the sample data.", class = "demo-note")),
    div(class = "demo-results", tableOutput("rows"))
  ),
  card(fill = FALSE,
    card_header(h3("About this connection")),
    tags$dl(class = "demo-details",
      tags$dt("API endpoint"), tags$dd(code("https://localhost:18444")),
      tags$dt("Table"), tags$dd(code(example_table)),
      tags$dt("Connection"), tags$dd(code("HTTPS / PostgREST"))
    ),
    p("PostgREST passes the signed-in role to PostgreSQL. PostgreSQL row-level security decides which rows are returned."),
    p("The database connection verifies its server certificate using this demo's local test CA.", class = "demo-note")
  )
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
    if (is.null(reference)) "Not signed in. Choose one of the demo accounts above." else "Sign out before trying the other account."
  })
  output$account <- renderText({
    token <- req(auth$token)
    paste("Signed in as", req(token@userinfo$preferred_username))
  })

  postgrest <- oauth_db_postgrest_api(
    auth$connection, url = "https://localhost:18444",
    ca_bundle = "/fixtures/tls/ca-cert.pem"
  )
  output$rows <- renderTable({
    postgrest$select(example_table, order = example_order)
  })
}

shinyApp(ui, server, uiPattern = ".*")
