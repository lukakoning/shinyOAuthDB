Run `Rscript tools/check-clickhouse-http.R` from the checkout with Docker and
a sibling shinyOAuth source checkout. The runner owns its Compose project,
publishes no host ports, and removes containers and volumes on exit. Set
`OAUTHDB_SKIP_BASE_BUILD=1` when the shared runner and TLS images already exist.

The public ClickHouse API helper sends SQL and typed parameters through real
HTTPS to a real ClickHouse engine. Tests cover escaping, Unicode, NULL, exact
integers/decimals, dates/timestamps, arrays, empty results, real per-user row
policies, forbidden writes, account changes and logout. A controlled proxy drops
or delays a response only after the upstream write has completed; database
counters must show exactly one write.

The gateway accepts only predefined synthetic bearer strings and maps them to
restricted local database identities. This tests SQL/HTTP compatibility and
engine grants. It does not validate managed ClickHouse Cloud JWT authentication,
an external IdP, or production audience/issuer enforcement. Use an eligible real
service for those checks. Counts and scope are saved in `.generated/results.json`.
