Run genuine Google OAuth acceptance against a small BigQuery project. This uses
the public API helper, page size one, regional jobs, exact A/B row expectations,
remote SESSION_USER(), a forbidden table, typed parameters/results, empty
results, and dataset/table listings. No cloud resource is created by the runner.

Start with a [BigQuery sandbox](https://docs.cloud.google.com/bigquery/docs/sandbox)
where its capabilities suffice. The sandbox excludes DML; the supplied
[fixture SQL](bigquery-fixture.sql) uses CREATE TABLE AS SELECT. An administrator
must configure [row access](https://docs.cloud.google.com/bigquery/docs/managing-row-level-security)
and IAM separately. Users need job creation in the query project, metadata
access to the fixture, and read access only to visible_rows. They must not have
an administrator role or permission to read forbidden_rows.

Register a Google Web OAuth client and obtain short-lived delegated tokens for
two Google users with the BigQuery scope. Do not substitute an administrator or
service-account token for either user. The runner uses these fixed credentials;
Google browser login, consent and refresh still need provider acceptance.

Set the common A/B token, expiry and scope variables from the
[live runner guide](README.md#your-own-cloud-database), plus:

| Variable | Value |
| --- | --- |
| `OAUTHDB_BIGQUERY_PROJECT` | Query/fixture project |
| `OAUTHDB_BIGQUERY_DATASET` | `oauthdb_fixture` |
| `OAUTHDB_BIGQUERY_TABLE` | `visible_rows` |
| `OAUTHDB_BIGQUERY_FORBIDDEN_TABLE` | `forbidden_rows` |
| `OAUTHDB_BIGQUERY_LOCATION` | Fixture region, e.g. `EU` |
| `OAUTHDB_LIVE_A_IDENTITY`, `OAUTHDB_LIVE_B_IDENTITY` | Actual SESSION_USER() email addresses |
| `OAUTHDB_LIVE_FIXTURE` | Absolute path to `tests/integration/bigquery.fixture.R` |
| `OAUTHDB_LIVE_TESTS` | `true` |

Run `Rscript --vanilla tests/integration/run-live.R` from the checkout after
installing the package and its imports. Each query uses a
[maximumBytesBilled](https://docs.cloud.google.com/bigquery/docs/reference/rest/v2/jobs/query)
limit of 10 MiB. Fixtures contain four rows; parameter/type queries use literals.
The runner does not cancel submitted jobs on timeout. Keep project quotas and
fixture expiration configured; recreate expired sandbox tables when needed.
