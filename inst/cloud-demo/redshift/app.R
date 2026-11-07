library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

settings <- as.list(read.dcf("settings.dcf")[1L, ])
client <- oauth_db_microsoft_client(
  tenant_id = settings$tenant_id, client_id = settings$client_id,
  client_secret = if (settings$client_type == "confidential") Sys.getenv("OAUTHDB_REDSHIFT_CLIENT_SECRET") else NULL,
  redirect_uri = paste0("http://localhost:", settings$port),
  token_targets = list(redshift = list(resource = settings$resource, scopes = settings$scope))
)

demo_title <- "Your Amazon Redshift Shiny demo"
example_query <- "SELECT current_user AS signed_in_user"
query_target <- "redshift"
query_scopes <- character()
query_notice <- "This demo needs Redshift/IAM Identity Center trusted identity propagation for Entra JWTs. Queries use normal Redshift compute; stopping this app does not pause a cluster."
query_help <- "Couldn't run the query. Check the Identity Center trusted issuer, accepted JWT audience and user mapping, database grants, network access and ODBC driver. Retry explicitly when ready."

make_access <- function(authorization) {
  oauth_db_redshift(authorization, server = settings$server,
    database = settings$database, driver = settings$driver,
    port = as.integer(settings$database_port), token_type = "EXT_JWT",
    target = "redshift", required_scopes = settings$scope)
}
run_query <- function(access) DBI::dbGetQuery(access(), example_query)

source("demo-ui.R", local = TRUE)$value
