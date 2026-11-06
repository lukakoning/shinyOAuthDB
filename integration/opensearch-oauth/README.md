# Native OpenSearch OAuth fixture

With Docker running and the repository's R test dependencies installed:

```sh
Rscript --vanilla tools/check-opensearch-oauth.R
```

The runner starts OpenSearch 3.9.0 with its Security and SQL plugins enabled.
It generates a temporary CA, node and administrator certificates, an RSA JWT
signing key, and access tokens for Alice, Bob, a writer and denied identities.
The JWT authenticator validates the signature, issuer, audience and expiry.
Shiny authorization references are synthetic; browser login and OIDC discovery
are not exercised by this fixture.

The `orders_reader` role permits reads of the `orders` index. A native
document-level rule matches `owner` against `${user.name}`, and field-level
security excludes `secret`. The same Query DSL and SQL queries return only
Alice's document or Bob's document. An independent writer role can index a
document, while readers cannot write or access `private-orders`.

All application requests use the public `oauth_db_opensearch_api()` helper
and signed user tokens over verified HTTPS. The administrator certificate
is used only by the setup container to seed indexes. Tests also cover native
SQL parameters, large integers, GET renewal, POST non-replay, bad tokens,
permission loss, sign-out, session ownership and certificate trust/hostname
failures.

The runner publishes a randomly selected TLS port on loopback and uses an
isolated Docker network. `OAUTHDB_OPENSEARCH_TEST_PORT` selects a port;
`OAUTHDB_OPENSEARCH_TEST_IMAGE` changes the pinned server image. Generated
files, the containers and the network are removed after the run. Images
are retained. No production credentials or host trust-store changes are used.

On Windows the test runner defaults curl to OpenSSL before loading R packages
so its disposable CA can be passed as a PEM bundle without changing the
Windows trust store. It does not disable certificate verification.
