library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

settings <- as.list(read.dcf("settings.dcf")[1L, ])
client <- oauth_db_microsoft_client(
  services = "sql",
  tenant_id = settings$tenant_id,
  client_id = settings$client_id,
  client_secret = if (settings$client_type == "confidential") {
    Sys.getenv("OAUTHDB_AZURE_SQL_CLIENT_SECRET")
  } else {
    NULL
  },
  redirect_uri = paste0("http://localhost:", settings$port)
)

demo_title <- "Azure SQL Shiny demo"
demo_details <- list(
  "SQL server" = settings$server,
  "Database" = settings$database,
  "Database port" = settings$database_port,
  "ODBC driver" = settings$driver
)
platform_note <- "An Entra user or group must exist in this database and hold the needed SQL grants. Successful Microsoft sign-in alone does not grant table access."
demo_guide <- "https://lukakoning.github.io/shinyOAuthDB/articles/azure-sql.html"
example_query <- "SELECT CURRENT_USER AS signed_in_user"
result_explanation <- "This first query checks your database identity. To try data access, replace it with SQL for a table you can read; the platform applies your existing permissions."
query_target <- "sql"
query_scopes <- character()
query_notice <- "SQL uses your Azure database. Stopping this app does not pause or delete the database."
query_help <- "Couldn't run the query. Check Entra authentication and the database user/group, the server/database, firewall or private-network access, then retry explicitly."

make_access <- function(authorization) {
  oauth_db_azure_sql(
    authorization,
    server = settings$server,
    database = settings$database,
    driver = settings$driver,
    port = as.integer(settings$database_port)
  )
}
run_query <- function(access, statement) DBI::dbGetQuery(access, statement)

source("demo-ui.R", local = TRUE)$value

# Open the printed app URL in your regular browser.
# (viewers in RStudio/Positron/etc. cannot perform necessary redirects)
