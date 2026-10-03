# Playground

These are simple apps for exercising the same session handle with existing
database packages. Run them from the repository root. Start with the offline
app, then configure one live backend at a time.

```r
pkgload::load_all()
source("playground/example-offline.R")
```

Install `RSQLite` for the offline app. Click **Use simulated user A**, run a native
call twice, then switch to B or sign out. Results disappear on authorization
changes, and native SQLite connections are reused only within their authorization
and session. This app uses deterministic authorization fixtures and separately
seeded local rows; it does not test an OAuth exchange or real database grants.
Its custom connector runs synchronously.

Live apps require an installed, current shinyOAuthDB package for background
workers, plus the development versions of shinyOAuth and any sibling package
whose token hooks are used. Install those packages before running the example.
For example, run `R CMD INSTALL .` from a terminal at the repository root after
installing dependencies. The apps do not install packages, read credential files,
configure a provider registration, or obtain a service identity automatically.

## Shared configuration

Supply configuration through your deployment environment or a local R session.
The scripts never print these values. Keep secrets and test token fixtures out of
Git. Examples use a registration you control, rather than another application's
client ID.

| Environment variable | Meaning |
|---|---|
| `OAUTHDB_TENANT_ID` | Microsoft Entra tenant ID for Microsoft examples |
| `OAUTHDB_CLIENT_ID` | Registered delegated OAuth application ID |
| `OAUTHDB_CLIENT_SECRET` | Registered secret; blank for an appropriately configured public client |
| `OAUTHDB_REDIRECT_URI` | Exact registered callback, default `http://localhost:8100` |
| `OAUTHDB_PORT` | Local listening port, default `8100` |
| `OAUTHDB_EXECUTOR` | `mirai` by default, or `future` |

The helper configures two mirai daemons or two future multisession workers once
outside `server()`, and restores/stops them when the app ends. OAuth network
operations remain owned by shinyOAuth. Each Shiny session creates its own source
handle and task. Workers create their own database connection rather than sharing
the session's DBI handle.

Open the exact `OAUTHDB_REDIRECT_URI` in a regular browser, then click **Sign in**.
There is no automatic browser launch or sign-in. The default callback uses
`localhost`, so open that hostname rather than the terminal's `127.0.0.1` URL.
For a different port, update both the URI and `OAUTHDB_PORT` and the registration.

**Run native call** uses ordinary DBI, FabricQueryR, or brickster APIs.
**Run in background** passes that same exported function to `oauth_db_task()`;
the adapter injects the configured endpoint and credential. Fabric calls require
the upstream package's public `fabric_token_provider()` hook, which preserves
endpoint policy for both session and worker credentials. The adapter reports a
missing hook rather than falling back to another sign-in. **Discard background result** invalidates the
local outcome; it does not promise to stop a remote statement.

## Backend examples

All endpoints, roles, database names and query documents come from trusted server
configuration. Browser input only supplies a bound integer for compatible SQL/KQL
examples. The fixed metadata/constant queries verify basic connectivity; replace
them in trusted app code with a read query against your authorization fixture to
test actual grants and row-level security.

| Script | Additional configuration | Existing client used |
|---|---|---|
| `example-azure-sql.R` | `OAUTHDB_SERVER`, `OAUTHDB_DATABASE`; optional `OAUTHDB_SQL_DRIVER` | DBI + odbc |
| `example-sql-server.R` | Above plus `OAUTHDB_SQL_SERVER_ENTRA_ENABLED=true` after native Entra setup | DBI + odbc |
| `example-azure-postgres.R` | `OAUTHDB_POSTGRES_HOST`, `OAUTHDB_DATABASE`, `OAUTHDB_POSTGRES_USER`, `OAUTHDB_POSTGRES_SSLROOTCERT` | DBI + RPostgres |
| `example-fabric-sql.R` | `OAUTHDB_SERVER` (Fabric SQL endpoint), `OAUTHDB_DATABASE`; optional SQL driver | FabricQueryR connector + native DBI |
| `example-fabric-kql.R` | `OAUTHDB_KQL_CLUSTER` (HTTPS query origin), `OAUTHDB_KQL_DATABASE` | `fabric_kql_query()` |
| `example-fabric-dax.R` | `OAUTHDB_FABRIC_WORKSPACE`, `OAUTHDB_FABRIC_MODEL` (semantic-model/dataset ID) | `fabric_pbi_dax_query()` |
| `example-fabric-graphql.R` | `OAUTHDB_GRAPHQL_API`; workspace ID if using an API ID; optional static `OAUTHDB_GRAPHQL_QUERY` and `OAUTHDB_GRAPHQL_ENDPOINT_HOSTS` | `fabric_graphql_query()` |
| `example-fabric-onelake.R` | `OAUTHDB_FABRIC_WORKSPACE`, `OAUTHDB_ONELAKE_ITEM`; optional `OAUTHDB_ONELAKE_PATH`, default `Files` | `fabric_onelake_list()` |
| `example-fabric-discovery.R` | Shared Microsoft configuration only | `fabric_workspaces(output = "list")` |
| `example-databricks.R` | `OAUTHDB_DATABRICKS_HOST`, `OAUTHDB_DATABRICKS_WAREHOUSE` | brickster OAuth provider + `db_sql_query()` |
| `example-snowflake.R` | Snowflake variables below | DBI + odbc, Microsoft External OAuth |

Start any configured example in R:

```r
source("playground/example-azure-sql.R")
```

To repeat these source-checkout offline checks, run
`Rscript tools/check-playground.R --test` from the repository root. Playground
scripts are omitted from the installed package; their smoke scenarios skip in
installed-package checks, whose core tests cover the session and task runtime.
On Windows, `rtk proxy powershell -File tools/check-playground-http.ps1` starts
a hidden temporary local server, verifies HTTP 200 and the offline controls,
then shuts down that server. Both checks require no cloud configuration.

SQL Server uses `ODBC Driver 18 for SQL Server` by default; its native driver must
be installed and support explicit access-token injection. The on-premises example
requires an Entra-enabled server and provisioned users/groups; ordinary SQL or
Windows login cannot reuse a Shiny visitor's OAuth identity.

Azure PostgreSQL requires Entra authentication enabled and the configured
individual/group role provisioned. `OAUTHDB_POSTGRES_USER` is trusted application
configuration, not a browser-provided email. TLS verifies the configured server
against `OAUTHDB_POSTGRES_SSLROOTCERT`. This example uses Azure's Entra token-as-
password path, not native PostgreSQL OAUTHBEARER.

For Snowflake set `OAUTHDB_SNOWFLAKE_SERVER`, `OAUTHDB_DATABASE`,
`OAUTHDB_SNOWFLAKE_SCHEMA`, `OAUTHDB_SNOWFLAKE_WAREHOUSE`, `OAUTHDB_SNOWFLAKE_ROLE`,
`OAUTHDB_SNOWFLAKE_RESOURCE`, and `OAUTHDB_SNOWFLAKE_SCOPES` (space-separated,
fully qualified scopes matching the security integration). Optionally set
`OAUTHDB_SNOWFLAKE_DRIVER`, default `SnowflakeDSIIDriver`. The configured role,
resource, issuer, subject claim and scope mapping must match the account's
Microsoft External OAuth integration. The package also describes native
Snowflake OAuth; this example specifically demonstrates Microsoft External OAuth.

Fabric apps require appropriate delegated scopes, tenant switches and actual
workspace/item/data permissions. A successful DAX constant or GraphQL `__typename`
query does not establish row-level access semantics. Grant requirements and
result formats remain those of the existing native service functions.

For GraphQL, prefer the complete portal-provided HTTPS endpoint on
`*.graphql.fabric.microsoft.com`. The native client's API-ID/GUID route instead
constructs an endpoint at `api.fabric.microsoft.com`, outside its default GraphQL
host policy. Using that route requires an explicit operator setting
`OAUTHDB_GRAPHQL_ENDPOINT_HOSTS=api.fabric.microsoft.com`; the source passes it
through `endpoint_hosts`. The variable accepts space-separated exact trusted
hostnames, with no schemes or wildcards. Hosts are never trusted automatically
from browser input or API IDs. A custom portal gateway needs its own explicit
trusted hostname as well.

Databricks uses a custom native OAuth application and brickster's public
`db_oauth_provider()`. Provider discovery makes a request to the trusted configured
workspace. Its selected user needs warehouse and Unity Catalog privileges.
The source and client explicitly request the `sql` permission profile.

## Separate app login and multiple database authorizations

`example-multiple-connections.R` uses the actual `shinyOAuth::oauth_connections()`
manager with two independent profiles: an OIDC-only application login and a
database client whose delegated targets come from its source. Both grants are
browser-retained by shinyOAuth, so database OAuth navigation preserves the app
login grant. The app has separate explicit selectors for application login and
database authorization. Neither selector chooses the first available grant,
even if only one exists. App-login credentials never substitute for the selected
database credentials.

Configure the chosen Microsoft backend using the earlier table, then set:

| Variable | Meaning |
|---|---|
| `OAUTHDB_MULTIPLE_BACKEND` | Microsoft backend example, default `azure-sql` |
| `OAUTHDB_APP_ORIGIN` | Browser application origin, default `http://localhost:8100` |
| `OAUTHDB_LOGIN_CLIENT_ID` | Registered application-login client ID |
| `OAUTHDB_LOGIN_CLIENT_SECRET` | Its server-side secret; blank for a registered public client |
| `OAUTHDB_LOGIN_TENANT_ID` | Login tenant; defaults to the database's `OAUTHDB_TENANT_ID` |
| `OAUTHDB_LOGIN_REDIRECT_URI` | Login callback, default `${OAUTHDB_APP_ORIGIN}/callback/login` |
| `OAUTHDB_DB_REDIRECT_URI` | Database callback, default `${OAUTHDB_APP_ORIGIN}/callback/database` |

The database registration still uses `OAUTHDB_CLIENT_ID`,
`OAUTHDB_CLIENT_SECRET` and `OAUTHDB_TENANT_ID`. Register the login callback on
its login registration and the database callback on its database registration.
Both clients declare the complete local callback set with shinyOAuth's
`multi_redirect_uri` mode. The example uses only one
`oauth_connections_ui()` wrapper and one `oauth_connections_server()`;
shinyOAuth performs callback routing, consent, retention and refresh.

```r
source("playground/example-multiple-connections.R")
```

Open `OAUTHDB_APP_ORIGIN`, click **Authorize app login**, then select that login
grant. Click **Add database authorization**, then after its callback select your
retained app login and the database grant separately. Repeat database
authorization to create another independently selectable grant. Changing the
selected app login clears the active database selection and saved results.
Switching the database authorization retires its previous native connection.
**Disconnect selected database authorization** removes that local grant.
**Clear all local authorizations** ends the browser owner and reloads the app;
these actions do not request upstream token revocation.

This development example uses an encrypted process-local memory store and
private ephemeral keys generated once at app startup. A restart discards the
demo store. Its browser owner identifies this browser session, independently
of the external OIDC identity. Production apps that bind retained database
grants to a trusted local application account should use shinyOAuth's
`oauth_account_owner()` with their existing verified app-session resolver and
deployment-held keys. The package does not infer an account owner from an email
or a browser input.

An existing `oauth_module_server()` app login can also coexist with a database
manager: use `oauth_connections_ui(..., additional_clients =
list(app_login = login_client))` for the single callback wrapper, and keep the
ordinary login module and database manager separate in `server()`. A standalone
module's ordinary session token is not retained across full database OAuth
navigation. Use the application's existing persistent app-account session when
that pattern needs continuous app login; this example retains both profiles in
the native manager instead. No second login/storage controller is added.

Source-checkout tests use the genuine manager and its public session-bound
references with synthetic grant fixtures. They cover ambiguous selections,
app-only authorization, wrong-profile/foreign IDs, database A/B replacement,
app-login replacement, disconnect, logout and restoration into a new Shiny
session. Those fixtures test lifecycle behavior rather than real OAuth exchange
or platform policy. Run them with `Rscript tools/check-playground.R --test`.

## Acceptance work

See [the integration scenarios](../tests/integration/README.md) for an opt-in A/B
transport test and a real-browser checklist covering consent, refresh,
authorization replacement, row-level grants, blocked destinations and pending
task outcomes. An example being present does not mean its cloud backend has been
tested live. Record package/driver/platform versions and observed results for
each actual deployment.
