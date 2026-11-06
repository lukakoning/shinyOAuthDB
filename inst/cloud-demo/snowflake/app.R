library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

settings <- as.list(read.dcf("settings.dcf")[1L, ])
client <- oauth_db_snowflake_client(
  server = settings$server, role = settings$role,
  client_id = settings$client_id,
  client_secret = Sys.getenv("OAUTHDB_SNOWFLAKE_CLIENT_SECRET"),
  redirect_uri = paste0("http://localhost:", settings$port)
)

demo_title <- "Your Snowflake Shiny demo"
example_query <- "SELECT CURRENT_USER() AS signed_in_user, CURRENT_ROLE() AS database_role"
query_target <- NULL
query_scopes <- paste0("session:role:", settings$role)
query_notice <- "Queries can resume your selected warehouse and consume credits. Stopping this local app does not suspend the warehouse."
query_help <- "Couldn't run the query. Check that your OAuth integration allows the role, the user holds it, and the role has warehouse USAGE. Check network policies too, then retry explicitly."

make_access <- function(authorization) {
  oauth_db_snowflake(authorization, server = settings$server, role = settings$role,
    warehouse = settings$warehouse, database = settings$database, schema = settings$schema,
    driver = settings$driver)
}
run_query <- function(access) DBI::dbGetQuery(access(), example_query)

source("demo-ui.R", local = TRUE)$value
