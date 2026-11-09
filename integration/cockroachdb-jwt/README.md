# CockroachDB JWT validation

Run from the repository root with Docker and RPostgres linked to libpq 16
or later, plus the package's development dependencies:

```sh
Rscript --vanilla tools/check-cockroachdb.R
```

Pass an extra dependency-library directory as a positional argument if
needed. The runner builds a disposable CockroachDB 25.4.0 single-node
server, generates a private TLS CA and RSA signing key, and configures
native JWT SQL authentication. The SQL port binds only to host loopback.
The runner removes its container and generated credentials when it exits.

Checks cover Alice/Bob SQL identities and separate table grants, denied
writes, bound DBI parameters, a dbplyr query, wrong issuer/audience/signature,
expired tokens, username mismatch,
TLS hostname validation, and refusal to fall back to a password-only user.
The public helper is exercised with token renewal, reconnection, SQL user
changes, sign-out and session cleanup.

The tokens are signed fixtures. This check doesn't run browser sign-in,
fetch external JWKS keys or connect to CockroachDB Cloud.
