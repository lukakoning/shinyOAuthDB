# Neo4j JWT integration check

Run from the repository root with Docker available:

```sh
Rscript --vanilla tools/check-neo4j-oauth.R
```

The runner starts Neo4j 5.26.32 Enterprise under its evaluation license,
a local HTTPS JWKS issuer and disposable certificates. It tests native
JWT verification and maps Alice and Bob to roles that can read different
node labels. The check also covers bound parameters, graph values, large
integers, update counters, denied writes, token replacement, sign-out,
incorrect issuer/audience/signature, expiry and TLS trust/hostname checks.

Tokens are locally signed fixtures. This does not test browser sign-in,
live provider key rotation, clustering or hosted Aura. No cloud account
is needed. Override the image or loopback port using
`OAUTHDB_NEO4J_TEST_IMAGE` or `OAUTHDB_NEO4J_TEST_PORT`.

The runner removes its containers, network, volumes and generated credentials
on exit. Server logs remain in `.validation/neo4j-oauth-server.log`.
