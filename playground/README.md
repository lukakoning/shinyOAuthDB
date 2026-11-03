# Example apps

Run an example to try sign-in and queries, or copy it as the starting point
for your app. Each [source guide](../vignettes/getting-started.Rmd) explains
the setup for that platform.

## Try it without a database

Install `RSQLite`, then run from the repository root:

```r
pkgload::load_all()
source("playground/example-offline.R")
```

Choose simulated user A or B to see different rows, then sign out to clear
the table. This uses local SQLite data and makes no OAuth requests.

## Connect to your platform

For a local PostgreSQL server with real Keycloak sign-in, run
`source("playground/postgres/run.R")` from the checkout root. Docker supplies
the database and app; see the [PostgreSQL playground](postgres/README.md).

Follow [your source guide](../vignettes/getting-started.Rmd#choose-your-source)
to install the client and driver and register the OAuth app. Users need
access to the data before these examples can query it.

Save the app settings in a local `.Renviron` file and restart R:

| Variable | Value |
| --- | --- |
| `OAUTHDB_TENANT_ID` | Entra tenant ID for Microsoft examples |
| `OAUTHDB_CLIENT_ID` | OAuth application client ID |
| `OAUTHDB_CLIENT_SECRET` | Client secret, if the registration uses one |
| `OAUTHDB_REDIRECT_URI` | Registered callback; defaults to `http://localhost:8100` |
| `OAUTHDB_PORT` | App port; defaults to `8100` |

Add the settings for your chosen example:

| App | Additional variables |
| --- | --- |
| [BigQuery](example-bigquery.R) | `OAUTHDB_BIGQUERY_PROJECT`; optional `OAUTHDB_BIGQUERY_LOCATION` (default `EU`) |
| [Redshift with Entra](example-redshift.R) | `OAUTHDB_REDSHIFT_SERVER`, `OAUTHDB_DATABASE`, `OAUTHDB_REDSHIFT_RESOURCE`, `OAUTHDB_REDSHIFT_SCOPE`; optional `OAUTHDB_REDSHIFT_DRIVER` |
| [Trino](example-trino.R) | `OAUTHDB_TRINO_ISSUER`, `OAUTHDB_TRINO_HOST`, `OAUTHDB_TRINO_CATALOG`, `OAUTHDB_TRINO_SCHEMA` |
| [Azure SQL](example-azure-sql.R) | `OAUTHDB_SERVER`, `OAUTHDB_DATABASE` |
| [SQL Server with Entra](example-sql-server.R) | Same as Azure SQL |
| [Azure PostgreSQL](example-azure-postgres.R) | `OAUTHDB_POSTGRES_HOST`, `OAUTHDB_DATABASE`, `OAUTHDB_POSTGRES_USER`, `OAUTHDB_POSTGRES_SSLROOTCERT` |
| [Self-hosted PostgreSQL](example-postgres.R) | `OAUTHDB_POSTGRES_HOST`, `OAUTHDB_DATABASE`, `OAUTHDB_POSTGRES_SSLROOTCERT`, `OAUTHDB_POSTGRES_ISSUER`; optional `OAUTHDB_POSTGRES_SCOPE` (default `database.read`). Requires the Linux/libpq 18 native adapter. |
| [Databricks API](example-databricks.R) | `OAUTHDB_DATABRICKS_HOST`, `OAUTHDB_DATABRICKS_WAREHOUSE` |
| [Snowflake](example-snowflake.R) | `OAUTHDB_SNOWFLAKE_SERVER`, `OAUTHDB_SNOWFLAKE_ROLE`; optionally `OAUTHDB_DATABASE`, `OAUTHDB_SNOWFLAKE_SCHEMA`, `OAUTHDB_SNOWFLAKE_WAREHOUSE` |
| [Fabric services](fabric/README.md) | See the app's separate setup |

The self-hosted PostgreSQL example derives the requested database role from
the signed-in account's validated `preferred_username` claim. Configure the
provider's profile claim and the matching PostgreSQL identity-to-role
mapping as described in the [PostgreSQL guide](../vignettes/postgres.Rmd).

For example:

```r
pkgload::load_all()
source("playground/example-azure-sql.R")
```

Open `http://localhost:8100` and sign in. If you change the port, update the
redirect URI in both the app and its registration.

## Other app patterns

[Queries on demand](example-query-button.R) uses the Azure SQL settings.
It runs SQL on a button click and clears saved results when the account
changes or loses access.

[Multiple database authorizations](example-multiple-connections.R) lets one
visitor save several sign-ins and choose which to query. Use the Azure SQL
settings and register
`http://localhost:8100/callback/database`. `OAUTHDB_APP_ORIGIN` changes the
origin. Sign-ins are stored in memory for this example. Follow shinyOAuth's
deployment guidance to keep them in persistent storage.

[Two providers at once](example-two-authorizations.R) queries Azure SQL and
Databricks independently. Set both platforms' connection variables, plus
`OAUTHDB_SQL_CLIENT_ID`, `OAUTHDB_SQL_CLIENT_SECRET`,
`OAUTHDB_DATABRICKS_CLIENT_ID`, and `OAUTHDB_DATABRICKS_CLIENT_SECRET`.
Register `/callback/sql` and `/callback/databricks` under `OAUTHDB_APP_ORIGIN`
(default `http://localhost:8100`) with their respective providers.

## Check the examples

```sh
Rscript tools/check-playground.R --test
```

The checks construct the apps and run queries against mocked services.
On Windows, `powershell -File tools/check-playground-http.ps1` also checks
the offline app's HTTP response. Use the
[integration checks](../tests/integration/README.md) for browser sign-in
or a real database.
