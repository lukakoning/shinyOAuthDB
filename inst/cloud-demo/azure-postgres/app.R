library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

settings <- as.list(read.dcf("settings.dcf")[1L, ])
client <- oauth_db_microsoft_client(
  services = "postgres", tenant_id = settings$tenant_id,
  client_id = settings$client_id,
  client_secret = if (settings$client_type == "confidential") Sys.getenv("OAUTHDB_AZURE_POSTGRES_CLIENT_SECRET") else NULL,
  redirect_uri = paste0("http://localhost:", settings$port)
)

demo_title <- "Your Azure PostgreSQL Shiny demo"
example_query <- "SELECT current_user AS database_role, current_database() AS database_name"
query_target <- "postgres"
query_scopes <- character()
query_notice <- "Your Microsoft token must match the database role, or its mapped group membership. Stopping this app does not stop the Azure server."
query_help <- "Couldn't run the query. Check Entra authentication, the mapped user/group role, database and network access, and the trusted CA bundle. Retry explicitly when ready."

make_access <- function(authorization) {
  oauth_db_azure_postgres(authorization, host = settings$server,
    dbname = settings$database, user = settings$user,
    sslrootcert = settings$sslrootcert, port = as.integer(settings$database_port))
}
run_query <- function(access) DBI::dbGetQuery(access(), example_query)

source("demo-ui.R", local = TRUE)$value
