# Manual cloud acceptance

Cloud acceptance runs locally through `tools/check-live.R`. CI uses disposable
local fixtures and does not receive cloud credentials. Set
`OAUTHDB_LIVE_TESTS=true` to enable the local runner.

Start with [BigQuery](bigquery.md): prepare the tiny A/B row-policy fixture and
known forbidden table. Set the environment variable `OAUTHDB_LIVE_CONFIG_JSON`:

```json
{
  "OAUTHDB_LIVE_FIXTURE": "tests/integration/bigquery.fixture.R",
  "OAUTHDB_CLIENT_ID": "your-google-client-id",
  "OAUTHDB_BIGQUERY_PROJECT": "your-fixture-project",
  "OAUTHDB_BIGQUERY_DATASET": "reporting",
  "OAUTHDB_BIGQUERY_TABLE": "visible_rows",
  "OAUTHDB_BIGQUERY_LOCATION": "EU",
  "OAUTHDB_BIGQUERY_FORBIDDEN_TABLE": "your-fixture-project.private.denied_rows",
  "OAUTHDB_LIVE_A_IDENTITY": "user-a@example.org",
  "OAUTHDB_LIVE_B_IDENTITY": "user-b@example.org",
  "OAUTHDB_LIVE_A_SCOPES": "https://www.googleapis.com/auth/bigquery",
  "OAUTHDB_LIVE_B_SCOPES": "https://www.googleapis.com/auth/bigquery"
}
```

Set environment variables `OAUTHDB_CLIENT_SECRET`, `OAUTHDB_LIVE_A_REFRESH_TOKEN`
and `OAUTHDB_LIVE_B_REFRESH_TOKEN`. Obtain each refresh token through an initial
delegated sign-in with the same client and recorded granted scopes. Google's
[offline access instructions](https://developers.google.com/identity/protocols/oauth2/web-server#offline)
describe obtaining and renewing those credentials. The runner exchanges them
at Google's fixed token endpoint, with a 30-second deadline, no redirects and
no automatic retries. It keeps resulting tokens in the R process and rejects
credentials with less than five minutes left. Revoked/expired refresh tokens
fail the lane and require operator sign-in again. An absent scope in Google's
renewal response uses the recorded original consent; never invent that value.

Set `OAUTHDB_LIVE_CREDENTIAL_MODE=google-refresh` for BigQuery and review the
identity, denied-operation, typed-value, pagination and cleanup results.
Each query has a 10 MiB billing limit; fixtures
contain four rows. This read suite does not require DML. The operator owns
provider spending limits, table expiry/recreation and fixture cleanup.

For another public cloud route, set `OAUTHDB_LIVE_CREDENTIAL_MODE=fixed-token`.
Use a reviewed fixture, the connection variables in
[source-config.R](source-config.R), and A/B token variables described
in [README.md](README.md). Record scalar expiry/scopes in the
configuration, or supply the multi-audience token JSON secrets. This mode is
manual because short-lived tokens expire. Install the required R packages and
native drivers, then run:

```sh
Rscript --vanilla tools/check-live.R
```

Both paths install the current source in a temporary library and write only a
sanitized report with source fingerprints, dependency versions, auth mode and
named scenarios. Reports contain no access/refresh tokens, query results or
driver errors. Fixed-token replacement/cleanup acceptance and the Google setup
exchange do not establish browser sign-in or the package's refresh lifecycle
against a cloud provider. Keep that qualification separate.
