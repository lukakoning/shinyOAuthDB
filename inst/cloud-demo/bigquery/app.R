library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

settings <- as.list(read.dcf("settings.dcf")[1L, ])
client <- oauth_db_bigquery_client(
  client_id = settings$client_id,
  client_secret = Sys.getenv("OAUTHDB_BIGQUERY_CLIENT_SECRET"),
  redirect_uri = paste0("http://localhost:", settings$port)
)

demo_title <- "Your Google BigQuery Shiny demo"
example_query <- "SELECT SESSION_USER() AS signed_in_user"
query_target <- NULL
query_scopes <- "https://www.googleapis.com/auth/bigquery"
query_notice <- paste("Query project:", settings$project, "| Location:", settings$location,
  "| Maximum bytes billed:", settings$maximum_bytes_billed,
  "| Running SQL creates a query job. Stopping this app does not cancel a submitted job.")
query_help <- "Couldn't run the query. Check that the BigQuery API is enabled, the user has BigQuery Job User, and the project/location and byte limit fit the query. Retry explicitly when ready."

make_access <- function(authorization) {
  oauth_db_bigquery_api(authorization, project = settings$project,
    location = settings$location, required_scopes = query_scopes)
}
run_query <- function(access) access$query(example_query,
  maximum_bytes_billed = settings$maximum_bytes_billed)

source("demo-ui.R", local = TRUE)$value
