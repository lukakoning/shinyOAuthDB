# Query data with a Shiny user's own account

Build Shiny apps that query databases using each visitor's own
permissions. Use DBI or dbplyr for SQL, or call fabricQueryR and
brickster functions with the user's sign-in.

## Details

Supports commercial and cloud-hosted data platforms, as well as
self-hosted PostgreSQL, Trino and DuckDB configured for OAuth. Users
sign in through a provider the database or query engine trusts; that
server enforces their permissions.

## Try a self-hosted database locally

With Docker running, use
[`oauth_db_demo()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_demo.md)
to start PostgreSQL 18, Keycloak and a Shiny app with demo accounts and
sample data. The installed package includes the configuration; Docker
provides R and native libraries. PostgREST, Trino, StarRocks, DuckDB
Quack, libSQL, CrateDB and OpenSearch demos use the same launcher. See
[Getting
started](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#build-a-small-app)
for demo accounts and cleanup, and
[`oauth_db_demo()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_demo.md)
for editing options.

## Start with your source

[`vignette("getting-started", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.md)
links to a guide for each source. Each includes sign-in setup and a
complete Shiny app. Read the guides on the [documentation
website](https://lukakoning.github.io/shinyOAuthDB/articles/index.html),
or install with `build_vignettes = TRUE` for local
[`vignette()`](https://rdrr.io/r/utils/vignette.html) help. For example,
use
[`vignette("snowflake", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/snowflake.md)
for Snowflake or
[`vignette("fabric", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/fabric.md)
for Fabric.

## Database queries

Inside `server()`, pass shinyOAuth's `auth$connection` to a helper such
as
[`oauth_db_azure_sql()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_azure_sql.md).
It returns a connection function, `con`. Get `connection <- con()`
inside a render or reactive expression, then query with DBI or dbplyr.

## Platform functions

[`oauth_db_fabric_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_fabric_api.md)
and
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md)
call functions from their platforms' R packages with the visitor's
credentials.
[`oauth_db_bigquery_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_api.md)
runs GoogleSQL and returns data frames.

## Cleanup diagnostics

A failed native disconnect emits a message while local authorization
retirement continues. To send these failures to your application's
logger, set
`options(shinyOAuthDB.on_cleanup_error = function(error) { ... })`. The
handler receives a `shinyOAuthDB_cleanup_failed` condition containing a
fixed message and reason, without the original driver error, connection,
or credential. If the handler errors, the default message is emitted.

## HTTP request failures

BigQuery, PostgREST and ClickHouse HTTP failures raise
`shinyOAuthDB_request_failed`. Catch this condition inside the Shiny
operation to inspect its `status`. Recognized service codes and UUID
request identifiers appear as `service_code` and `request_id`;
unavailable values are `NULL`. The condition excludes server messages,
response bodies and credentials.

## Sign-in settings

The source guides create clients with
[`oauth_db_microsoft_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_microsoft_client.md),
[`oauth_db_bigquery_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_bigquery_client.md),
[`oauth_db_databricks_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_client.md),
or
[`oauth_db_snowflake_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_snowflake_client.md).
You can also use an existing shinyOAuth client.

See
[`vignette("getting-started", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.md)
for custom permissions, multiple accounts, and saved query results.

## See also

Useful links:

- <https://lukakoning.github.io/shinyOAuthDB/>

- <https://github.com/lukakoning/shinyOAuthDB>

- Report bugs at <https://github.com/lukakoning/shinyOAuthDB/issues>

## Author

**Maintainer**: Luka Koning <koningluka@gmail.com> \[copyright holder\]

Authors:

- Luka Koning <koningluka@gmail.com> \[copyright holder\]
