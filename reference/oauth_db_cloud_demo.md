# Set up an editable Shiny demo for a cloud workspace

Try an editable Shiny app with your own cloud workspace and account. The
console guide helps you find the workspace and sign-in settings, then
runs the app in local R. Each visitor signs in with their own account
and data permissions. You need existing cloud resources; the guide
doesn't create them.

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

  Databricks workspace hostname or browser URL. For other SQL demos, an
  alias for `server`.

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

  Named settings for the selected platform, listed below under Platform
  settings. Interactive setup asks for missing values.

## Value

Invisibly, the demo directory, including after pausing incomplete
interactive setup. Noninteractive starts report missing settings as
errors.

## Details

Run this from an R console to get prompts for missing settings. Sign in
through the browser, then click **Run example query** in the app.
Queries use the platform's normal compute or query allowance. Stopping
the app doesn't stop shared cloud services or cancel submitted jobs.

All demos need mirai 2.5.1 or later, bslib and processx; install askpass
for masked secret input. Databricks also needs brickster 0.2.14 or later
and jsonlite. Fabric needs fabricQueryR, odbc and Microsoft ODBC Driver
18. BigQuery and ClickHouse use jsonlite without a database driver.
Snowflake, Azure SQL and Redshift need odbc and their native drivers;
Azure PostgreSQL needs RPostgres and a trusted CA bundle.

## Platform settings

Databricks uses the named arguments above. For other platforms, pass
these settings through `...`:

- Fabric:

  `server`, `database`, `tenant_id`; optional `driver`.

- BigQuery:

  `project`; optional `location`, `maximum_bytes_billed`.

- Snowflake:

  `server`, `role`, `warehouse`; optional `database`, `schema`,
  `driver`.

- Azure SQL:

  `server`, `database`, `tenant_id`; optional `driver`, `database_port`.

- Azure PostgreSQL:

  `server`, `database`, `user`, `sslrootcert`, `tenant_id`; optional
  `database_port`.

- Redshift:

  `identity_center_ready`, `server`, `database`, `tenant_id`,
  `resource`, `scope`; optional `driver`, `database_port`.

- ClickHouse:

  `jwt_ready`, `url`, `tenant_id`, `resource`, `scope`; optional
  `database`.

`database_port` is the database's port; `port` is the local Shiny port.
The Redshift and ClickHouse demos use Entra and need an existing
trusted-token integration. See the source guide for registration steps.

## Edit and resume

The launcher saves non-secret settings in `settings.dcf` and keeps your
`app.R` edits. Call it again with the same `path` to resume. Use
`action = "files"` for an offline draft, or a new empty path for fresh
templates. For scripts, supply the required settings and
`prompt = FALSE`.

Enter secrets through the masked prompt or the platform's client-secret
environment variable. Databricks uses
`OAUTHDB_DATABRICKS_CLIENT_SECRET`; other names are in the source
guides. Secrets pass through the app process environment and aren't
written to generated files.

## Databricks registration

Databricks needs an account-level custom OAuth registration with SQL
access and the exact callback URI. Public registrations use PKCE without
a secret; confidential registrations need a secret. Free Edition doesn't
provide this registration path. After sign-in, select a warehouse or
supply its ID manually. See the Databricks vignette for setup.

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
