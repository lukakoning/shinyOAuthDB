library(shiny)
library(bslib)
library(shinyOAuth)
library(shinyOAuthDB)

issuer <- "https://localhost:18443/realms/shinyoauthdb"
client <- oauth_client(
  oauth_provider_oidc_discover(issuer),
  client_id = "shiny-db",
  client_secret = "demo-client-secret",
  redirect_uri = "http://localhost:18100",
  scopes = c("openid", "profile", "database.read")
)

example_query <- "SELECT marker FROM visible_rows ORDER BY row_id"

ui <- oauth_ui(
  page_sidebar(
    title = h2("PostgreSQL OAuth demo", class = "h3 mb-0"),
    theme = bs_theme(
      version = 5,
      primary = "#17646c",
      bg = "#f4f6f9",
      fg = "#23313d",
      base_font = "system-ui"
    ),
    fillable = FALSE,
    lang = "en",
    sidebar = sidebar(
      width = 320,
      bg = "#fff",
      fg = "#23313d",
      open = list(desktop = "always", mobile = "always-above"),
      h3("1. Sign in", class = "h5"),
      p("Choose a demo account. Sign out before trying the other one."),
      tags$table(
        id = "demo-accounts",
        class = "table table-sm",
        tags$thead(tags$tr(tags$th("Username"), tags$th("Password"))),
        tags$tbody(
          tags$tr(tags$td(code("alice")), tags$td(code("alice"))),
          tags$tr(tags$td(code("bob")), tags$td(code("bob")))
        )
      ),
      div(
        class = "d-flex gap-2 flex-wrap",
        actionButton("login", "Sign in", class = "btn-primary"),
        actionButton("logout", "Sign out")
      ),
      div(role = "status", textOutput("account"), textOutput("sign_in_status")),
      p(
        "Sign-in opens Keycloak. Your browser may ask you to allow its local test certificate.",
        class = "demo-note"
      ),
      hr(),
      p(a(
        "Set up your own PostgreSQL data source",
        href = "https://lukakoning.github.io/shinyOAuthDB/articles/postgres.html"
      )),
      actionButton("stop", "Stop demo"),
      p(
        "Stopping removes the demo services and sample data. Your copied app code is kept.",
        class = "demo-note"
      )
    ),
    tags$style(
      ".demo-details { display: grid; grid-template-columns: minmax(7rem, 1fr) minmax(0, 3fr); gap: .6rem 1rem; }
    .demo-details dt { font-size: .9rem; color: #485867; }
    .demo-details dd { margin: 0; overflow-wrap: anywhere; }
    .sidebar .demo-details { grid-template-columns: 1fr; gap: .25rem; }
    .sidebar .demo-details dd { margin-bottom: .5rem; }
    @media (max-width: 575px) { .main .demo-details { grid-template-columns: 1fr; gap: .25rem; } .main .demo-details dd { margin-bottom: .6rem; } }
    .demo-details code, #demo-accounts code { color: inherit; white-space: normal; overflow-wrap: anywhere; }
    .demo-results { overflow-x: auto; }
    .demo-note { color: #485867; font-size: .95rem; }
    .btn { min-height: 44px; }
    pre { white-space: pre-wrap; overflow-wrap: anywhere; }
    .card-header h3 { font-size: 1.1rem; margin: 0; }
    .card, .sidebar { background: #fff; }
    .bslib-card { margin-top: 1rem; }
    .card-body > p { margin-bottom: 0; }"
    ),
    p(
      "Query PostgreSQL with the account of the person who signs in.",
      class = "lead"
    ),
    card(
      fill = FALSE,
      card_header(h3("2. Query sample data")),
      pre(example_query),
      p(
        "Sign in as alice, then sign out and try bob. The same request returns different rows because the data source applies their permissions."
      ),
      conditionalPanel(
        "!output.account",
        p("Sign in to load the sample data.", class = "demo-note")
      ),
      div(class = "demo-results", tableOutput("rows"))
    ),
    card(
      fill = FALSE,
      card_header(h3("About this connection")),
      tags$dl(
        class = "demo-details",
        tags$dt("Database"),
        tags$dd(code("oauthdb_fixture")),
        tags$dt("Server"),
        tags$dd(code("localhost:5432")),
        tags$dt("Table"),
        tags$dd(code("visible_rows")),
        tags$dt("Connection"),
        tags$dd(code("DBI / RPostgres with native PostgreSQL OAuth"))
      ),
      p(
        "PostgreSQL checks the OAuth token, maps the person to a database role and applies row-level security."
      ),
      p(
        "The database connection verifies its server certificate using this demo's local test CA.",
        class = "demo-note"
      )
    )
  ),
  id = "auth",
  client = client
)

server <- function(input, output, session) {
  auth <- oauth_module_server("auth", client, auto_redirect = FALSE)
  observeEvent(input$login, auth$request_login())
  observeEvent(input$logout, auth$logout())
  observeEvent(input$stop, stopApp())

  output$sign_in_status <- renderText({
    if (
      !is.null(auth$error) && !auth$error %in% c("logged_out", "access_denied")
    ) {
      return(
        "Sign-in didn't finish. Check the local test certificate in your browser, then try Sign in again."
      )
    }
    reference <- tryCatch(auth$connection(), error = function(error) NULL)
    if (is.null(reference)) {
      "Not signed in. Choose one of the demo accounts above."
    } else {
      "Sign out before trying the other account."
    }
  })
  output$account <- renderText({
    token <- req(auth$token)
    paste("Signed in as", req(token@userinfo$preferred_username))
  })

  con <- oauth_db_postgres(
    auth$connection,
    host = "localhost",
    dbname = "oauthdb_fixture",
    user = function() req(auth$token@userinfo$preferred_username),
    issuer = issuer,
    scope = "database.read",
    sslrootcert = "/fixtures/tls/ca-cert.pem"
  )
  output$rows <- renderTable({
    connection <- con()
    DBI::dbGetQuery(connection, example_query)
  })
}

shinyApp(ui, server, uiPattern = ".*")

# Open the printed app URL in your regular browser.
# (viewers in RStudio/Positron/etc. cannot perform necessary redirects)
