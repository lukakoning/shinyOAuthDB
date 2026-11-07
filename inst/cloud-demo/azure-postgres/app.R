library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

settings <- as.list(read.dcf("settings.dcf")[1L, ])
client <- oauth_db_microsoft_client(
  services = "postgres",
  tenant_id = settings$tenant_id,
  client_id = settings$client_id,
  client_secret = if (settings$client_type == "confidential") {
    Sys.getenv("OAUTHDB_AZURE_POSTGRES_CLIENT_SECRET")
  } else {
    NULL
  },
  redirect_uri = paste0("http://localhost:", settings$port)
)

demo_title <- "Azure PostgreSQL Shiny demo"
demo_details <- list(
  "PostgreSQL server" = settings$server,
  "Database" = settings$database,
  "Requested role" = settings$user,
  "Database port" = settings$database_port,
  "Trusted CA bundle" = settings$sslrootcert
)
platform_note <- "Each person signs in individually. PostgreSQL checks that their token matches the requested database user or its mapped group membership."
demo_guide <- "https://lukakoning.github.io/shinyOAuthDB/articles/azure-postgres.html"
example_query <- "SELECT current_user AS database_role, current_database() AS database_name"
result_explanation <- "The result shows the PostgreSQL role. With a group role, several people can share that role while PostgreSQL checks each signed-in user's membership."
query_target <- "postgres"
query_scopes <- character()
query_notice <- "Your Microsoft token must match the database role, or its mapped group membership. Stopping this app does not stop the Azure server."
query_help <- "Couldn't run the query. Check Entra authentication, the mapped user/group role, database and network access, and the trusted CA bundle. Retry explicitly when ready."

make_access <- function(authorization) {
  oauth_db_azure_postgres(
    authorization,
    host = settings$server,
    dbname = settings$database,
    user = settings$user,
    sslrootcert = settings$sslrootcert,
    port = as.integer(settings$database_port)
  )
}
run_query <- function(access) DBI::dbGetQuery(access(), example_query)

source("demo-ui.R", local = TRUE)$value
