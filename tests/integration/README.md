# Integration checks

Use these checks to test browser sign-in or queries against a real database.
The ordinary package tests use local data and mocked services.

## Local browser sign-in and PostgreSQL

The [PostgreSQL/Keycloak fixture](../../integration/postgres-keycloak/README.md)
runs in Docker. It exercises `oauth_db_postgres()` with real OAuth sign-in,
database-enforced user permissions, refresh, and sign-out. For Azure PostgreSQL,
use `oauth_db_azure_postgres()` for Entra authentication.

## Local PostgREST and Keycloak

The [PostgREST fixture](../../integration/postgrest-keycloak/README.md) runs real
browser sign-in, HTTPS API calls, PostgreSQL row-level security and table grants.
Its [separate workflow](../../.github/workflows/postgrest-integration.yaml) runs
independently of PostgreSQL integration. From the repository root:

```sh
bash integration/local/run-integration.sh postgrest
```

On Windows, use `powershell -NoProfile -File integration/local/run-integration.ps1 -Backend postgrest`.

## Local Trino and Keycloak

The [Trino fixture](../../integration/trino-keycloak/README.md) runs real OAuth2
authentication, RTrino DBI queries and fetching, server-enforced row filters,
denied impersonation, refresh and cleanup. Its
[separate workflow](../../.github/workflows/trino-integration.yaml) runs
independently of the other integrations:

```sh
bash integration/local/run-integration.sh trino
```

On Windows, use `powershell -NoProfile -File integration/local/run-integration.ps1 -Backend trino`.

## Local StarRocks and Keycloak

The [StarRocks fixture](../../integration/starrocks-keycloak/README.md) exercises
native JWT authentication through MySQL Connector/ODBC, verified TLS, per-user
database grants and protected views, refresh, and connection cleanup. Its
[separate workflow](../../.github/workflows/starrocks-integration.yaml) runs
independently of the other integrations:

```sh
bash integration/local/run-integration.sh starrocks
```

On Windows, use `powershell -NoProfile -File integration/local/run-integration.ps1 -Backend starrocks`.

## Local Databricks client compatibility with MiniLake

The [MiniLake fixture](../../integration/minilake-keycloak/README.md) exercises
the public Databricks DBI and API helpers through real brickster calls and
DuckDB SQL, with Keycloak browser PKCE and trusted HTTPS:

```sh
bash integration/local/run-integration.sh minilake
```

On Windows, use `integration/local/run-integration.ps1 -Backend minilake`.
Its [independent workflow](../../.github/workflows/minilake-integration.yaml)
runs alongside the other local suites. MiniLake accepts all tokens, does not
enforce grants, uses DuckDB's dialect, and its pinned image ignores named SQL
parameters. This lane tests client compatibility and bridge lifecycle behavior;
it does not establish production Databricks security or parameter support.

## Fabric sandbox

Follow the [Fabric app instructions](../../playground/fabric/README.md) to
start the prepared sandbox, then run:

```sh
Rscript tools/check-fabric-sandbox.R
Rscript tools/check-fabric-browser.R
```

These check queries and app rendering with the shared sandbox account.
Test visitor sign-in separately.

## Your own cloud database

For real Google API, IAM, pagination and typed-value acceptance, use the
[BigQuery fixture](bigquery.md). It runs tiny capped queries against an
operator-prepared project and makes no cloud provisioning calls.
The [cloud CI setup](cloud-ci.md) provides an opt-in weekly/prerelease BigQuery
lane with fresh delegated credentials and manual acceptance for other routes.

`run-live.R` uses two existing user tokens to check queries, account
changes, sign-out, and connection reuse where applicable. It supports
Azure SQL, SQL Server, Fabric, Azure PostgreSQL, Databricks, and Snowflake
with native and Entra External OAuth, and Redshift. Databricks uses the actual
public DBI/API helpers; Fabric uses the public API client and can retain a
Lakehouse resource across account replacement.

| Route | Public path / authentication |
| --- | --- |
| `databricks-dbi`, `databricks-api` | DBI or API helper with Databricks OAuth |
| `databricks-dbi-entra`, `databricks-api-entra` | Same helpers with Entra |
| `fabric-api-discovery`, `fabric-api-kql`, `fabric-api-dax`, `fabric-api-graphql`, `fabric-api-onelake` | Fabric API client for each service/audience |
| `fabric-api-resource` | Fabric item lookup and retained Lakehouse table read; needs Fabric and storage tokens |
| `snowflake-native`, `snowflake-external` | Snowflake native OAuth or Entra External OAuth |
| `redshift`, `redshift-access-token` | Native ODBC EXT_JWT or ACCESS_TOKEN |

`databricks` selects the DBI route. Existing `fabric-<service>` names select
the corresponding API route. These are fixed-token acceptance routes, not
browser sign-in or refresh tests. For Redshift, set `OAUTHDB_OIDC_ISSUER` and
`OAUTHDB_SCOPES` for its provider as well as server/database/driver settings.

Browser sign-in, consent, and refresh need a separate browser test.

1. Install the database client and driver. Set the backend's connection
   variables listed in [source-config.R](source-config.R).
2. Give users A and B distinct access to fixture data. The same query should
   return each user's permitted rows.
3. Copy [fixture.example.R](fixture.example.R) outside Git. Edit `backend`,
   `configure()`, and `validate()` for your data. Supply distinct expected
   remote identities in `users = c(A = ..., B = ...)`, an `identify()` query,
   and a `denied()` check of a known forbidden resource. A/B results must
   differ. The runner executes this file as trusted R code.
4. Set these variables privately:

| Variable | Value |
| --- | --- |
| `OAUTHDB_LIVE_A_TOKEN`, `OAUTHDB_LIVE_B_TOKEN` | Delegated user access tokens for the backend |
| `OAUTHDB_LIVE_A_EXPIRES_AT`, `OAUTHDB_LIVE_B_EXPIRES_AT` | Token expiry as Unix seconds, at least five minutes ahead |
| `OAUTHDB_LIVE_A_SCOPES`, `OAUTHDB_LIVE_B_SCOPES` | Actual granted scopes, separated by spaces |
| `OAUTHDB_LIVE_FIXTURE` | Path to the fixture R file |
| `OAUTHDB_LIVE_TESTS` | `true` |

Run from the repository root:

```sh
Rscript tests/integration/run-live.R
```

The summary reports pass or fail without printing tokens or query results.
It writes helper, auth mode and named acceptance scenarios to
`results/live.json`. Stateless brickster handles retain copied tokens after
disconnect; the runner checks the owning accessor after logout and does not
claim that a copied bearer has been revoked remotely.

For multiple audiences, set `OAUTHDB_LIVE_A_TOKENS_JSON` and
`OAUTHDB_LIVE_B_TOKENS_JSON` instead of the scalar token variables. Each JSON
object must contain exactly the client's target names, such as `fabric` and
`storage`. Each target contains `access_token`, numeric Unix `expires_at`, and
a JSON array of `scopes`. All tokens must have at least five minutes left.
The runner never prints this object. Resource fixtures also need
`OAUTHDB_ONELAKE_TABLE`; the retained A resource must fail after switching to B.

## Check browser sign-in

Use separate browser profiles for A and B and check that the same query returns
the right data for each. Then replace A with B in one session, refresh an
expired token, and sign out. Check that outputs follow the selected account
and stored results clear when access ends.

Test each service the app uses: Fabric SQL access, for example, does not
establish OneLake or semantic-model permissions. Confirm the query identity
in the platform's audit records. Record the client, driver, and platform
versions with the results.
