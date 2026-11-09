# CockroachDB backend

Implementation research and validation from 9 November 2026.

`oauth_db_cockroachdb()` uses RPostgres and CockroachDB's documented
[cluster SSO JWT protocol](https://www.cockroachlabs.com/docs/stable/sso-sql).
The connection passes `options = "--crdb:jwt_auth_enabled=true"` and the
visitor's JWT access token as the SQL password. The cluster verifies the
signature, issuer, audience, expiry and principal mapping. SQL grants
determine the visitor's data access.

CockroachDB's newer
[SASL OAUTHBEARER protocol](https://www.cockroachlabs.com/docs/stable/oauth-authentication)
needs a fully upgraded 26.4 cluster and compatible clients. It uses separate
cluster settings. JWT-as-password works with the package's existing
RPostgres lifecycle across Windows, macOS and Linux. The helper requires
libpq 16 or later so `require_auth = "password"` prevents a server from
accepting trust or certificate-only authentication. It also sets verified
TLS and disables GSS encryption, rejects ambiguous endpoints and native
authentication overrides, and refuses ambient libpq service configurations.

The helper accepts an explicit or reactive SQL username. There is no
universal OAuth provider preset: deployments choose their issuer, token
audience, scopes and username mapping. It supplies access tokens only;
providers that issue opaque access tokens need a different configuration.

RPostgres stores the password used at connection opening. The accessor
therefore compares a SHA-256 digest of the current access token before
reusing a connection and replaces it after rotation. Renewal alone doesn't
invalidate a completed reactive query. Identity or username changes, lost
required permissions, sign-out and session end close the connection.

## Validation

Unit tests cover input and driver requirements, fixed JWT/TLS connection
options, rejection of opaque tokens and ambient service files, token
rotation without query replay, SQL username and account changes, lost
permissions, reconnection, sign-out and session cleanup. The guide's complete
app also participates in the signed-out vignette checks.

`Rscript --vanilla tools/check-cockroachdb.R` starts a disposable CockroachDB
25.4.0 container with its own TLS CA and static RSA JWKS. A Windows R 4.5.1
client with RPostgres 1.4.10 and libpq 16.10 passed 27 live assertions:

- Alice and Bob authenticated as distinct SQL users and could read only
  their granted tables; writes were denied.
- Bound DBI parameters and a filtered dbplyr query returned the expected data.
- Wrong audiences, issuers, signing keys, expired tokens and mismatched SQL
  usernames were rejected. A deliberately wrong TLS hostname failed.
- A password-only user whose password equalled a wrongly targeted JWT
  could not bypass JWT validation.
- The public accessor replaced a connection after token rotation, reopened
  a disconnected connection, followed a SQL username change, and closed
  handles on sign-out and session end.

These checks used real CockroachDB JWT validation and SQL authorization with
signed fixture tokens. Browser login, live provider JWKS rotation,
CockroachDB Cloud and SASL OAUTHBEARER were not tested. See the
[fixture instructions](../integration/cockroachdb-jwt/README.md).
