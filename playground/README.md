# Playground

The basic scripts contain sign-in plus a native database read in roughly 35–40 lines. The [integrated Fabric app](fabric/README.md) covers multiple services in one app. All use ordinary Shiny code and the backend package's existing API.

Start with the local demo:

```r
pkgload::load_all()
source("playground/example-offline.R")
```

Install `RSQLite` and select simulated user A or B. The table follows the selection. Signing out closes the native connection. The simulated grants and seeded rows demonstrate local lifecycle behavior, not OAuth or database grants.

## Run a live app

Install shinyOAuthDB and the target-enabled development shinyOAuth package. Fabric uses fabricQueryR's existing token callback API; Databricks uses unmodified upstream brickster. Install the client package and native driver for your backend.

Configure the environment before sourcing the app:

| Variable | Meaning |
|---|---|
| `OAUTHDB_TENANT_ID` | Microsoft Entra tenant for Microsoft examples |
| `OAUTHDB_CLIENT_ID` | Your registered delegated OAuth application |
| `OAUTHDB_CLIENT_SECRET` | Client secret; blank for a configured public client |
| `OAUTHDB_REDIRECT_URI` | Registered callback, default `http://localhost:8100` |
| `OAUTHDB_PORT` | Listening port, default `8100` |

```r
source("playground/example-azure-sql.R")
```

Open the exact callback origin in a regular browser and click **Sign in**. With the default configuration use `http://localhost:8100`. Changing the port also requires changing the registered callback. The examples do not configure your OAuth registration or database grants.

## Choose a backend

| Script | Additional environment settings |
|---|---|
| [Azure SQL](example-azure-sql.R) | `OAUTHDB_SERVER`, `OAUTHDB_DATABASE` |
| [SQL Server](example-sql-server.R) | Same as Azure SQL; server must already support Entra authentication |
| [Azure PostgreSQL](example-azure-postgres.R) | `OAUTHDB_POSTGRES_HOST`, `OAUTHDB_DATABASE`, `OAUTHDB_POSTGRES_USER`, `OAUTHDB_POSTGRES_SSLROOTCERT` |
| [Fabric: all services](fabric/README.md) | Discovers `fabricqueryr-shiny-dhrkoning`; reuses `ENTRA_*` or shared `FABRICQUERYR_*` sandbox settings |
| [Databricks](example-databricks.R) | `OAUTHDB_DATABRICKS_HOST`, `OAUTHDB_DATABRICKS_WAREHOUSE` |
| [Snowflake](example-snowflake.R) | `OAUTHDB_SNOWFLAKE_SERVER`, `OAUTHDB_DATABASE`, `OAUTHDB_SNOWFLAKE_SCHEMA`, `OAUTHDB_SNOWFLAKE_WAREHOUSE`, `OAUTHDB_SNOWFLAKE_ROLE` |

Azure SQL and SQL Server use ODBC Driver 18 by default. The server must accept delegated Entra tokens and provision the selected user or group. Azure PostgreSQL needs its Entra role mapping and CA certificate; this uses Azure's token-as-password protocol.

The Snowflake example uses native Snowflake OAuth and its role scope, with a registered client secret. External OAuth can use another native shinyOAuth client with matching `scopes` and role settings.

Fabric uses a regular audience-aware callback; configure trusted endpoints in the app or obtain them through native discovery. No private fabricQueryR endpoint-policy attributes are attached.

All query endpoints and roles come from server configuration. Metadata and constant queries establish connectivity; replace them with queries against your own tables to verify user-specific grants and row policies. Use native bound parameters when incorporating browser input.

## Multiple authorizations

[example-multiple-connections.R](example-multiple-connections.R) uses shinyOAuth's retained connection manager. Set the Azure SQL variables and optionally `OAUTHDB_APP_ORIGIN` (default `http://localhost:8100`). Register `http://localhost:8100/callback/database` as its callback.

Add multiple grants and select one explicitly. The table reads through the selected database authorization. The example uses one process, a memory store, and temporary private keys. Persistent deployments need the store, owner policy, and key management described by shinyOAuth.

For an app with separate login and database grants, keep login policy in the app and return the selected database connection from the accessor. App login alone does not supply database credentials.

These examples read directly in render functions. If your app adds event-based result caching or background work, use the usual Shiny tools and decide how those app-owned results should behave when authorization changes.

## Checks

```sh
Rscript tools/check-playground.R --test
```

The checks parse examples, construct their actual UI and OAuth configuration, mock cloud transports, and exercise A/B native connection isolation using SQLite. On Windows, `powershell -File tools/check-playground-http.ps1` also checks the offline app's HTTP response. These checks do not claim live cloud acceptance.

For deployment-specific verification, see the [opt-in integration checks](../tests/integration/README.md) and [PostgreSQL/Keycloak fixture](../integration/postgres-keycloak/README.md).
