# A local lifecycle demonstration; this deliberately is NOT an OAuth provider
# or proof that a database has enforced permissions. No credentials or network.

playground_offline_app <- function() {
  for (package in c("shiny", "shinyOAuth", "shinyOAuthDB", "RSQLite", "DBI")) playground_require(package)
  client <- shinyOAuth::oauth_client(
    provider = shinyOAuth::oauth_provider(
      name = "offline-fixture", auth_url = "https://offline.invalid/authorize",
      token_url = "https://offline.invalid/token", token_auth_style = "public"
    ),
    client_id = "offline-fixture", client_secret = "", redirect_uri = "http://localhost:8100",
    scopes = "demo.read"
  )
  source <- shinyOAuthDB::oauth_db_custom(
    backend = "offline_sqlite", scopes = "demo.read", target = NULL,
    connect = function(config, token_provider) {
      user <- sub("^offline-fixture-", "", token_provider())
      con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
      DBI::dbWriteTable(con, "demo_rows", data.frame(
        user = rep(user, 2L), visible_marker = paste0(user, c("-first", "-second"))
      ))
      con
    }
  )
  auth_factory <- function(input, output, session) {
    current <- shiny::reactiveVal(NULL)
    selected_user <- shiny::reactiveVal(NULL)
    generation <- 0L
    select_user <- function(user) {
      generation <<- generation + 1L
      selected_user(user)
      id <- paste("offline", user, generation, sep = "-")
      token <- shinyOAuth::OAuthToken(
        access_token = paste0("offline-fixture-", user), token_type = "Bearer",
        expires_at = as.numeric(Sys.time()) + 3600,
        granted_scopes = "demo.read", granted_scopes_verified = TRUE
      )
      # The internal constructor is used only for this deterministic fixture.
      # Real playgrounds use the module's session-bound auth$connection().
      connection <- getFromNamespace("OAuthConnection", "shinyOAuth")$new(
        id = id, client = client,
        resolve = function() {
          domain <- shiny::getDefaultReactiveDomain()
          if (isTRUE(session$isClosed()) || is.null(domain) ||
              !identical(domain$rootScope(), session$rootScope()) ||
              !identical(current()$id, id)) {
            stop("Offline authorization ended.", call. = FALSE)
          }
          list(client = client, token = token, status = "active")
        },
        acquire = function(async = FALSE, ...) TRUE,
        is_current = function() identical(current()$id, id)
      )
      current(connection)
    }
    shiny::observeEvent(input$select_a, select_user("A"))
    shiny::observeEvent(input$select_b, select_user("B"))
    list(
      connection = function() current(), request_login = function() select_user("A"),
      logout = function() { selected_user(NULL); current(NULL) }
    )
  }
  spec <- list(
    title = "offline SQLite lifecycle", source = source,
    package = "DBI", fun = "dbGetQuery",
    native_args = function(value) list(statement = "SELECT user, visible_marker, ? AS requested_value FROM demo_rows", params = list(value)),
    sync = function(db, args) do.call(DBI::dbGetQuery, c(list(conn = db$connection()), args)),
    note = "Synthetic A/B authorizations and local SQLite rows demonstrate session reuse and clearing on authorization changes. No real OAuth or database permission policy is tested. The custom connector is synchronous."
  )
  ui <- shiny::tagList(playground_ui(spec), shiny::div(
    shiny::actionButton("select_a", "Use simulated user A"),
    shiny::actionButton("select_b", "Use simulated user B")
  ))
  shiny::shinyApp(ui, playground_server(spec, auth_factory = auth_factory))
}
