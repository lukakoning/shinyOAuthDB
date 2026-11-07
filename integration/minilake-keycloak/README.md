# Local Databricks client compatibility

Run from the repository root, with a sibling shinyOAuth checkout:

```sh
bash integration/local/run-integration.sh minilake
```

On Windows, use `integration/local/run-integration.ps1 -Backend minilake`.
Docker starts a pinned MiniLake image, HTTPS with a generated trusted CA,
Keycloak and Chromium. Each run owns its Compose project and removes its
containers and volumes afterward. It publishes no host ports and uses no
workspace credentials, Docker socket, Spark jobs or cloud resources.

The tests sign in through real browser PKCE and exercise both
`oauth_db_databricks()` and `oauth_db_databricks_api()` with the installed
brickster package. They check SQL quoting, Unicode, NULL, empty results,
large integer text, timestamps, results spanning MiniLake's 100,000-row chunk
boundary, native connection reuse, replacement after token rotation, account
replacement and missing local scopes. Refresh must not replay a completed
query. Large integers are explicitly selected as text to preserve every digit.

The pinned emulator ignores Statement Execution API named parameters. The
suite records that gap by requiring the specific HTTP 400 SQL parser error
from both helpers; it does not count that as working parameter binding.
Quoted values round-trip through real SQL instead. Arrow results exercise
typed NULLs and timestamps; INLINE JSON is also exercised during connection
validation. Parameter binding still needs validation against Databricks.

The dbplyr check executes `tbl()` over a SQL subquery, then `filter()` and
`collect()`, including an empty result. brickster's bare-table field-discovery
query wraps the table name in parentheses; the pinned DuckDB emulator rejects
that form. Quoted table identifiers are checked on PostgreSQL, Trino and
StarRocks. Databricks table discovery still needs the real workspace lane.

MiniLake runs SQL on DuckDB. It accepts any bearer token and stores grants
without enforcing them. Selecting Alice's or Bob's fixture rows is data
selection, **not** evidence of Databricks isolation or permissions. This lane
does not test Databricks OAuth, Entra, Spark SQL, workspace grants, ODBC or
production warehouse behavior. Those still need a real workspace.
See the upstream [known gaps](https://github.com/dmux/minilake#known-gaps).

Its matrix job in the [integration workflow](../../.github/workflows/integration.yaml)
runs alongside the other local integration jobs. Sanitized assertion
counts and the emulator/brickster versions are retained in
`.generated/results.json`. Errors, warnings, skips or zero assertions fail it.
