# Elasticsearch JWT integration check

Run from the repository root with Docker available:

```sh
Rscript --vanilla tools/check-elasticsearch-oauth.R
```

The fixture starts Elasticsearch 9.2.0 with a disposable trial license,
verified HTTPS and a native JWT realm configured for external access tokens.
It generates RSA signing keys, a local CA and short-lived tokens for Alice,
Bob and a writer. These are test identities; no Elastic Cloud or identity
provider account is needed. It does not exercise browser sign-in.

The public client queries real search, SQL and ES|QL endpoints. Native roles
filter documents per user, hide a field and reject writes by readers.
Checks cover user switching, token renewal on safe reads, rejected issuer,
audience, subject, signature and expiry, the realm shared secret, sign-out,
required scopes, CA trust and hostname verification.

Override the image or loopback port with `OAUTHDB_ELASTICSEARCH_TEST_IMAGE`
or `OAUTHDB_ELASTICSEARCH_TEST_PORT`. The runner removes its containers,
network and generated credentials on exit. Server logs remain in
`.validation/elasticsearch-oauth-server.log`.
