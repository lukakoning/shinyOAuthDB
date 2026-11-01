# Example apps

Run these apps to try the package or adapt one for your own database.
The [getting-started guide](../vignettes/getting-started.Rmd) explains the
common sign-in and connection pattern.

## Try it without a database

Install `RSQLite`, then run from the repository root:

```r
pkgload::load_all()
source("playground/example-offline.R")
```

Select simulated user A or B to see the table change. This demonstrates
connection reuse and sign-out with local data; it does not perform OAuth.

## Connect to your platform

Install the package and your platform's client and driver as described in
[Database connections](../vignettes/databases.Rmd). Configure the app
registration and database access before running an example.

The basic apps use these environment variables:

| Variable | Value |
| --- | --- |
| `OAUTHDB_TENANT_ID` | Entra tenant ID for Microsoft examples |
| `OAUTHDB_CLIENT_ID` | OAuth application client ID |
| `OAUTHDB_CLIENT_SECRET` | Client secret, if the registration uses one |
| `OAUTHDB_REDIRECT_URI` | Registered callback; defaults to `http://localhost:8100` |
| `OAUTHDB_PORT` | App port; defaults to `8100` |

Choose an app and set its connection details:

| App | Additional variables |
| --- | --- |
| [Azure SQL](example-azure-sql.R) | `OAUTHDB_SERVER`, `OAUTHDB_DATABASE` |
| [SQL Server with Entra](example-sql-server.R) | Same as Azure SQL |
| [Azure PostgreSQL](example-azure-postgres.R) | `OAUTHDB_POSTGRES_HOST`, `OAUTHDB_DATABASE`, `OAUTHDB_POSTGRES_USER`, `OAUTHDB_POSTGRES_SSLROOTCERT` |
| [Databricks API](example-databricks.R) | `OAUTHDB_DATABRICKS_HOST`, `OAUTHDB_DATABRICKS_WAREHOUSE` |
| [Snowflake](example-snowflake.R) | `OAUTHDB_SNOWFLAKE_SERVER`, `OAUTHDB_SNOWFLAKE_ROLE`; optionally `OAUTHDB_DATABASE`, `OAUTHDB_SNOWFLAKE_SCHEMA`, `OAUTHDB_SNOWFLAKE_WAREHOUSE` |
| [Fabric services](fabric/README.md) | See the app's separate setup |

For example:

```r
pkgload::load_all()
source("playground/example-azure-sql.R")
```

Open `http://localhost:8100` and sign in. If you change the port, update the
redirect URI in both the app and its registration.

## Other app patterns

[Queries on demand](example-query-button.R) uses the Azure SQL settings.
It runs a query on a button click and clears the stored result on sign-out,
authorization changes, or missing permissions.

[Multiple database authorizations](example-multiple-connections.R) lets a
visitor add grants and choose one. Use the Azure SQL settings and register
`http://localhost:8100/callback/database`. `OAUTHDB_APP_ORIGIN` changes the
origin. The example uses an in-memory store; follow shinyOAuth's deployment
guidance for persistent authorization storage.

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

This runs the apps with mocked cloud calls. On Windows,
`powershell -File tools/check-playground-http.ps1` also checks the offline
app's HTTP response. For real sign-in and database access, see the
[integration checks](../tests/integration/README.md).
