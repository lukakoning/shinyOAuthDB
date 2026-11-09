library(shiny)
library(shinyOAuth)
library(shinyOAuthDB)

settings <- as.list(read.dcf("settings.dcf")[1L, ])
client <- oauth_db_snowflake_client(
  server = settings$server,
  role = settings$role,
  client_id = settings$client_id,
  client_secret = Sys.getenv("OAUTHDB_SNOWFLAKE_CLIENT_SECRET"),
  redirect_uri = paste0("http://localhost:", settings$port)
)

demo_title <- "Snowflake Shiny demo"
demo_details <- list(
  "Account server" = settings$server,
  "Role" = settings$role,
  "Warehouse" = settings$warehouse,
  "Database" = settings$database,
  "Schema" = settings$schema,
  "ODBC driver" = settings$driver
)
platform_note <- "The OAuth role and SQL role match. Table queries also need database/schema USAGE and SELECT; warehouse visibility alone does not grant those permissions."
demo_guide <- "https://lukakoning.github.io/shinyOAuthDB/articles/snowflake.html"
example_query <- "SELECT CURRENT_USER() AS signed_in_user, CURRENT_ROLE() AS database_role"
result_explanation <- "This first query checks your database identity. To try data access, replace it with SQL for a table you can read; the platform applies your existing permissions."
query_target <- NULL
query_scopes <- paste0("session:role:", settings$role)
query_notice <- "Queries can resume your selected warehouse and consume credits. Stopping this local app does not suspend the warehouse."
query_help <- "Couldn't run the query. Check that your OAuth integration allows the role, the user holds it, and the role has warehouse USAGE. Check network policies too, then retry explicitly."

make_access <- function(authorization) {
  oauth_db_snowflake(
    authorization,
    server = settings$server,
    role = settings$role,
    warehouse = settings$warehouse,
    database = settings$database,
    schema = settings$schema,
    driver = settings$driver
  )
}
run_query <- function(access, statement) DBI::dbGetQuery(access, statement)

source("demo-ui.R", local = TRUE)$value

# Open the printed app URL in your regular browser.
# (viewers in RStudio/Positron/etc. cannot perform necessary redirects)
