library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

settings <- as.list(read.dcf("settings.dcf")[1L, ])
client <- oauth_db_bigquery_client(
  client_id = settings$client_id,
  client_secret = Sys.getenv("OAUTHDB_BIGQUERY_CLIENT_SECRET"),
  redirect_uri = paste0("http://localhost:", settings$port)
)

demo_title <- "Google BigQuery Shiny demo"
demo_details <- list(
  "Query project" = settings$project,
  "Location" = settings$location,
  "Maximum bytes billed per query" = settings$maximum_bytes_billed
)
platform_note <- "Query jobs belong to this project. Use the location of your dataset when reading tables; the byte limit caps billed bytes, while SQL LIMIT only limits returned rows."
demo_guide <- "https://lukakoning.github.io/shinyOAuthDB/articles/bigquery.html"
example_query <- "SELECT SESSION_USER() AS signed_in_user"
result_explanation <- "This first query checks your database identity. To try data access, replace it with SQL for a table you can read; the platform applies your existing permissions."
query_target <- NULL
query_scopes <- "https://www.googleapis.com/auth/bigquery"
query_notice <- paste0("Maximum bytes billed: ", settings$maximum_bytes_billed,
  ". Running SQL creates a query job. Stopping this app does not cancel a submitted job.")
query_help <- "Couldn't run the query. Check that the BigQuery API is enabled, the user has BigQuery Job User, and the project/location and byte limit fit the query. Retry explicitly when ready."

make_access <- function(authorization) {
  oauth_db_bigquery_api(authorization, project = settings$project,
    location = settings$location, required_scopes = query_scopes)
}
run_query <- function(access) access$query(example_query,
  maximum_bytes_billed = settings$maximum_bytes_billed)

source("demo-ui.R", local = TRUE)$value
