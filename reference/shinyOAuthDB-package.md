# Query data with a Shiny user's own account

Build Shiny apps that query data with each visitor's own account and
existing data permissions. shinyOAuth handles browser sign-in and token
renewal; shinyOAuthDB supplies those credentials to database connections
and web API calls. The data source checks the token and applies the
user's permissions.

## Start with an app

[`vignette("getting-started", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.md)
explains the package and walks through a complete app. The [source
guides](https://lukakoning.github.io/shinyOAuthDB/articles/index.html)
cover each database or platform. Use `build_vignettes = TRUE` when
installing from GitHub to read the guides locally.

Try
[`oauth_db_demo()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_demo.md)
for a local database and sign-in service in Docker, or
[`oauth_db_cloud_demo()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_cloud_demo.md)
for an editable app using your cloud workspace.

## Query data

DBI is R's common interface for SQL databases. dbplyr translates dplyr
commands into SQL for the database to run.

For SQL databases, a helper such as
[`oauth_db_azure_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_sql.md)
returns a function, usually named `con`. Create it inside `server()`,
passing `auth$connection` from shinyOAuth. Inside a render or reactive
expression, call `connection <- con()` before querying with DBI or
dbplyr.

For web APIs, helpers such as
[`oauth_db_bigquery_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_api.md)
return a client object with query methods.
[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md)
and
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md)
call functions from their supporting R packages with the visitor's
credentials.

## Sign-in and sessions

The source's `*_client()` helper supplies sign-in settings for
shinyOAuth. You can also use an existing client that obtains suitable
access tokens. Keep data helpers inside `server()` so each visitor has
their own access.

Clear saved query results when the visitor signs out or changes
accounts. The getting-started vignette covers session behavior and
multiple accounts.

## Diagnostics

HTTP failures can raise `shinyOAuthDB_request_failed` with a `status`
and, when available, `service_code` and `request_id`. These diagnostics
exclude server messages, response bodies and credentials.

To log connection-cleanup failures, set
`options(shinyOAuthDB.on_cleanup_error = function(error) { ... })`. The
callback receives a `shinyOAuthDB_cleanup_failed` condition with a fixed
message and reason. If it fails, the package emits its default message
and continues local cleanup.

## See also

Useful links:

- <https://lukakoning.github.io/shinyOAuthDB/>

- <https://github.com/lukakoning/shinyOAuthDB>

- Report bugs at <https://github.com/lukakoning/shinyOAuthDB/issues>

## Author

**Maintainer**: Luka Koning <koningluka@gmail.com> \[copyright holder\]

Authors:

- Luka Koning <koningluka@gmail.com> \[copyright holder\]
