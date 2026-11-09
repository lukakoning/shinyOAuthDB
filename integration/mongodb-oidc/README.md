# MongoDB workforce OIDC fixture

This check starts MongoDB Enterprise 8.0.16 and an HTTPS discovery/JWKS
endpoint in disposable Docker containers. It creates temporary RSA signing
keys, a private CA, Alice/Bob database users and separate collection grants.
No production credentials or Atlas account are used.

Install the Python test requirements into a development environment:

```sh
python -m venv .validation/mongodb-python
# Windows: use .validation/mongodb-python/Scripts/python.exe
.validation/mongodb-python/bin/python -m pip install -r integration/mongodb-oidc/requirements.txt
```

Set `RETICULATE_PYTHON` to that interpreter's absolute path, start Docker,
then run from the repository root:

```sh
Rscript --vanilla tools/check-mongodb.R
```

The script installs the checkout into a temporary R library. It verifies
real MONGODB-OIDC authentication, separate user grants, exact BSON results,
queries and aggregations, denied reads/writes, token replacement, account
changes, sign-out, issuer/client/host restrictions and CA trust. Driver
retryable reads/writes are disabled. Fixture logs and generated credentials
stay under ignored `.validation/mongodb-oidc/`.

Set `OAUTHDB_MONGODB_TEST_IMAGE` to test another MongoDB Enterprise image.
The fixture requires Linux containers and uses the official
`mongodb/mongodb-enterprise-server` image. Containers and their Docker network
are removed on completion or failure.

The fixture supplies signed access tokens to synthetic shinyOAuth connection
references. It does not test browser sign-in, a real IdP's consent and token
renewal, Atlas, live signing-key rotation, transactions or streaming cursors.
