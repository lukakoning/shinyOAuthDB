library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

settings <- as.list(read.dcf("settings.dcf")[1L, ])
client <- oauth_db_microsoft_client(
  services = "sql", tenant_id = settings$tenant_id,
  client_id = settings$client_id,
  client_secret = if (settings$client_type == "confidential") Sys.getenv("OAUTHDB_AZURE_SQL_CLIENT_SECRET") else NULL,
  redirect_uri = paste0("http://localhost:", settings$port)
)

demo_title <- "Your Azure SQL Shiny demo"
example_query <- "SELECT CURRENT_USER AS signed_in_user"
query_target <- "sql"
query_scopes <- character()
query_notice <- "SQL uses your Azure database. Stopping this app does not pause or delete the database."
query_help <- "Couldn't run the query. Check Entra authentication and the database user/group, the server/database, firewall or private-network access, then retry explicitly."

make_access <- function(authorization) {
  oauth_db_azure_sql(authorization, server = settings$server,
    database = settings$database, driver = settings$driver,
    port = as.integer(settings$database_port))
}
run_query <- function(access) DBI::dbGetQuery(access(), example_query)

source("demo-ui.R", local = TRUE)$value
