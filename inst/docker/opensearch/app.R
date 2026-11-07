library(shiny)
library(bslib)
library(shinyOAuth)
library(shinyOAuthDB)

issuer <- "https://localhost:18443/realms/shinyoauthdb"
client <- oauth_client(
  oauth_provider_oidc_discover(issuer),
  client_id = "shiny-opensearch", client_secret = "demo-client-secret",
  redirect_uri = "http://localhost:18100",
  scopes = c("openid", "profile", "search.read")
)

example_index <- "orders"
example_search <- list(size = 20L, sort = list("id"))
example_request <- paste0("POST /", example_index, "/_search\n",
  jsonlite::toJSON(example_search, auto_unbox = TRUE, pretty = TRUE))

ui <- oauth_ui(page_sidebar(
  title = h2("OpenSearch OAuth demo", class = "h3 mb-0"),
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
    p(a("Set up your own OpenSearch data source", href = "https://lukakoning.github.io/shinyOAuthDB/articles/opensearch.html")),
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
  p("Search documents using the signed-in account and its document permissions.", class = "lead"),
  card(fill = FALSE,
    card_header(h3("2. Search your documents")),
    pre(example_request),
    p("Sign in as alice, then sign out and try bob. The same request returns different rows because the data source applies their permissions."),
    conditionalPanel("!output.account", p("Sign in to load the sample data.", class = "demo-note")),
    div(class = "demo-results", tableOutput("rows"))
  ),
  card(fill = FALSE,
    card_header(h3("3. Check write permission")),
    p("This attempts to add a document to the disposable orders index. OpenSearch should reject it for both demo accounts."),
    actionButton("probe", "Check write permission"),
    div(role = "status", textOutput("permission"))
  ),
  card(fill = FALSE,
    card_header(h3("About this connection")),
    tags$dl(class = "demo-details",
      tags$dt("Search endpoint"), tags$dd(code("https://localhost:9200")),
      tags$dt("Index"), tags$dd(code(example_index)),
      tags$dt("Connection"), tags$dd(code("HTTPS / OpenSearch Query DSL")),
      tags$dt("Access"), tags$dd(code("Document-level security and read-only roles"))
    ),
    p("OpenSearch applies document-level security to the orders index. The app shows each returned document's marker as a table row."),
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

  database <- oauth_db_opensearch_api(
    auth$connection, url = "https://localhost:9200", required_scopes = "search.read",
    ca_bundle = "/fixtures/tls/ca-cert.pem"
  )
  output$account <- renderText({
    token <- req(auth$token)
    paste("Signed in as", req(token@userinfo$preferred_username))
  })
  output$rows <- renderTable({
    result <- database$search(example_index, body = example_search)
    data.frame(marker = vapply(result$hits$hits, function(hit) hit$`_source`$marker, ""))
  })
  check <- reactiveVal(NULL)
  observeEvent(input$probe, {
    reference <- req(auth$connection())
    blocked <- tryCatch({
      database$request(c("orders", "_doc", "write-test"), method = "PUT", body = list(marker = "write-test"))
      FALSE
    }, error = function(error) {
      if (inherits(error, "shinyOAuthDB_request_failed") && error$status == 403L) TRUE else NA
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
