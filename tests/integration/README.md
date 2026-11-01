# Integration checks

Use these checks to test browser sign-in or queries against a real database.
The ordinary package tests use local data and mocked services.

## Local browser sign-in and PostgreSQL

The [PostgreSQL/Keycloak fixture](../../integration/postgres-keycloak/README.md)
runs in Docker. It checks real OAuth sign-in, database-enforced user permissions,
refresh, and sign-out. Its native PostgreSQL token helper is for this fixture
only. For Azure PostgreSQL, use the package's Entra connection helper.

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

`run-live.R` uses two existing user tokens to check queries, account
changes, sign-out, and connection reuse where applicable. It supports
Azure SQL, SQL Server, Fabric, Azure PostgreSQL, Databricks, and Snowflake
with Entra External OAuth. BigQuery, Redshift, and Trino can be tested
manually with their playground apps.

Browser sign-in, consent, and refresh need a separate browser test.

1. Install the database client and driver. Set the backend's connection
   variables listed in [source-config.R](source-config.R).
2. Give users A and B distinct access to fixture data. The same query should
   return each user's permitted rows.
3. Copy [fixture.example.R](fixture.example.R) outside Git. Edit `backend`,
   `configure()`, and `validate()` for your data. The runner executes this file
   as trusted R code.
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

## Check browser sign-in

Use separate browser profiles for A and B and check that the same query returns
the right data for each. Then replace A with B in one session, refresh an
expired token, and sign out. Check that outputs follow the selected account
and stored results clear when access ends.

Test each service the app uses: Fabric SQL access, for example, does not
establish OneLake or semantic-model permissions. Confirm the query identity
in the platform's audit records. Record the client, driver, and platform
versions with the results.
