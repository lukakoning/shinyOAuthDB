# Set up an editable Shiny demo for a cloud workspace

A console guide helps you find your workspace and OAuth app settings,
then runs a local Shiny app with your installed R packages. Visitors
sign in through shinyOAuth and use their own cloud data permissions.

## Usage

``` r
oauth_db_cloud_demo(
  platform = "databricks",
  host = NULL,
  client_id = NULL,
  client_type = NULL,
  warehouse_id = NULL,
  http_path = NULL,
  path = NULL,
  port = NULL,
  edition = NULL,
  action = c("start", "files"),
  prompt = interactive(),
  launch_browser = interactive(),
  ...
)
```

## Arguments

- platform:

  Cloud platform: `"databricks"`, `"fabric"`, `"bigquery"`,
  `"snowflake"`, `"azure-sql"`, `"azure-postgres"`, `"redshift"` or
  `"clickhouse"`.

- host:

  Databricks workspace hostname or browser URL. Paths, queries and
  fragments are removed. For other SQL demos, an alias for `server`.

- client_id:

  Client ID from your custom OAuth app registration.

- client_type:

  `"public"` for PKCE without a secret, or `"confidential"`. The guide
  asks when needed; noninteractive calls default to `"public"` where
  supported. BigQuery and Snowflake demos use confidential
  registrations.

- warehouse_id:

  Optional default Databricks SQL warehouse ID.

- http_path:

  Optional Databricks warehouse HTTP path, instead of `warehouse_id`.

- path:

  Empty or existing cloud-demo directory. The default is a
  platform-specific directory in R's user cache, so drafts survive
  restarting R. Existing settings and app edits are preserved. Use a new
  empty path for a separate setup or fresh templates.

- port:

  Local Shiny port, default 8100 or the saved setting. Register
  `http://localhost:<port>` exactly as the OAuth callback.

- edition:

  Databricks only: `"workspace"`, `"trial"`, `"free"`, or `"unknown"`.
  Free Edition lacks the account-level custom registration this example
  needs.

- action:

  `"start"` guides setup and runs the app; `"files"` writes an editable
  draft without network calls or asking for a secret.

- prompt:

  Ask interactively for missing settings. Use `FALSE` in scripts.

- launch_browser:

  Open the local app in a regular browser.

- ...:

  Named platform settings. Fabric uses `server`, `database`, `tenant_id`
  and optionally `driver`. Missing required values are explained and
  requested interactively. BigQuery uses `project` and optionally
  `location` and `maximum_bytes_billed`. Snowflake uses `server`,
  `role`, `warehouse` and optionally `database`, `schema`, `driver`.
  Azure SQL uses `server`, `database`, `tenant_id` and optionally
  `driver`, `database_port` (the SQL port, distinct from the local Shiny
  `port`). Azure PostgreSQL uses `server`, `database`, `user`,
  `sslrootcert`, `tenant_id` and optionally `database_port`. Redshift
  uses `identity_center_ready`, `server`, `database`, `tenant_id`,
  `resource`, `scope` and optionally `driver`, `database_port`.
  ClickHouse uses `jwt_ready`, `url`, `tenant_id`, `resource`, `scope`
  and optionally `database`. The Redshift and ClickHouse examples use
  Entra and require an existing trusted-token integration. See the
  platform's source guide, linked from
  [`vignette("getting-started", package = "shinyOAuthDB")`](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.md).

## Value

Invisibly, the demo directory, including after pausing incomplete
interactive setup. Noninteractive starts report missing settings as
errors.

## Details

All demos use local R, bslib and processx. Install askpass for masked
input. BigQuery and ClickHouse use jsonlite without a native database
driver. Snowflake, Azure SQL and Redshift use odbc and their native ODBC
drivers; Azure PostgreSQL uses RPostgres and a trusted CA bundle. Each
copied app waits for an explicit query-button click. Stopping the local
process does not stop shared cloud compute or cancel submitted jobs.

Fabric asks for its SQL server/database and an Entra tenant and app
registration. Install fabricQueryR, odbc and Microsoft ODBC Driver 18.
Its confidential secret uses `OAUTHDB_FABRIC_CLIENT_SECRET`. The copied
`app.R` contains the connection and query code; `demo-ui.R` contains the
UI.

Databricks needs an account-level custom OAuth app registration with the
exact callback and SQL access. Public PKCE registrations need no secret.
For confidential apps, set `OAUTHDB_DATABRICKS_CLIENT_SECRET` or use the
masked prompt. Secrets and tokens are not written to the generated files
or serialized R arguments. The app's child process receives the secret
through its environment. Normal cloud TLS verification stays enabled.

Settings can also come from `OAUTHDB_DATABRICKS_HOST` and
`OAUTHDB_DATABRICKS_CLIENT_ID`. The guide can pause for registration and
resume from `path`. The generated `settings.dcf` contains only
non-secret configuration; `app.R` stays editable.

Databricks additionally needs brickster 0.2.14 or later and jsonlite. No
Docker is needed. Its app discovers SQL warehouses after sign-in, with a
manual-ID fallback. Listing doesn't run SQL. Clicking **Run example
query** opens the DBI connection and runs `SELECT current_user()`.
Queries can start a stopped warehouse and consume compute credits.
Stopping the app doesn't stop or change a shared cloud warehouse.

Databricks Free Edition has no account-console or account-level API
access, so it doesn't offer the custom OAuth registration path used
here. A full workspace or eligible full-platform trial needs access to
that registration. This is distinct from connecting a local R client
using a personal token.

## See also

[`oauth_db_demo()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_demo.md),
[`oauth_db_databricks_client()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_client.md),
[`oauth_db_databricks()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks.md),
[`oauth_db_databricks_api()`](https://lukakoning.github.io/shinyOAuthDB/reference/oauth_db_databricks_api.md).

## Examples

``` r
if (FALSE) { # \dontrun{
oauth_db_cloud_demo("databricks")
oauth_db_cloud_demo("fabric")
oauth_db_cloud_demo("bigquery", action = "files", path = "my-bigquery-demo")
path <- oauth_db_cloud_demo("databricks", action = "files", prompt = FALSE)
file.edit(file.path(path, "app.R"))
oauth_db_cloud_demo("databricks", path = path)
} # }
```
