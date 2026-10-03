# Configure playground/README.md's separate app-login and database profiles.
# The actual shinyOAuth manager retains both grants through OAuth redirects.
source("playground/shared.R", local = TRUE)
source("playground/multiple-connections.R", local = TRUE)
run_oauth_db_multiple_playground()
