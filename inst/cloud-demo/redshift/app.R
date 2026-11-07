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

demo_title <- "Amazon Redshift Shiny demo"
demo_details <- list(
  "Endpoint" = settings$server,
  "Database" = settings$database,
  "Database port" = settings$database_port,
  "Accepted API resource" = settings$resource,
  "Delegated scope" = settings$scope,
  "ODBC driver" = settings$driver
)
platform_note <- "This connection uses IdpTokenAuthPlugin with an external JWT. IAM Identity Center must trust the issuer and audience and map the user to Redshift privileges."
demo_guide <- "https://lukakoning.github.io/shinyOAuthDB/articles/redshift.html"
example_query <- "SELECT current_user AS signed_in_user"
result_explanation <- "This first query checks your database identity. To try data access, replace it with SQL for a table you can read; the platform applies your existing permissions."
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
