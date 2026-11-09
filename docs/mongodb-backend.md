# MongoDB backend decision

Investigated on 9 November 2026.

## Driver choice

MongoDB's MONGODB-OIDC authentication is a SASL conversation, not an HTTP
bearer header or token-as-password login. Workforce federation is available
in eligible Atlas clusters and Linux MongoDB Enterprise deployments.

The reviewed mongolite 4.1.0 interface exposes TLS options and a URI, but no
public OIDC callback. Using its pooled native clients without an explicit
per-client token hook would not establish visitor isolation. The adapter
therefore uses optional reticulate with MongoDB's official PyMongo driver.
It doesn't modify mongolite internals, store tokens in files, or implement
the MongoDB wire protocol itself.

PyMongo 4.10 is the supported minimum. A Python OIDCCallback subclass returns
one visitor token. No R function is called from a driver thread. The human
callback checks the challenge's issuer and optional client ID; PyMongo's
ALLOWED_HOSTS restriction limits which servers may receive that token.
shinyOAuth alone handles browser sign-in and refresh credentials.

## Lifetime and query boundary

Each helper uses the existing Shiny authorization lifecycle. Token hashes
and usernames identify cached clients. Renewal replaces the client on its
next use without replaying completed reactive queries. Account changes,
permission loss, sign-out and session end close it. A post-operation check
rejects responses from a retired authorization.

The public client materializes find and aggregation cursors and closes them
in the same call. JSON inputs use PyMongo's Extended JSON parser; outputs use
its Extended JSON serializer and R's precision-preserving JSON decoder.
There is no DBI abstraction or exported Python connection handle.

Retryable reads and writes are disabled. PyMongo still implements required
protocol reauthentication. Native command responses preserve writeErrors;
the caller must inspect batch write results. Driver failures cross into R
as a generic error and numeric server code, without server-controlled
messages, Python tracebacks or a token-bearing parent condition.

## Sources

- [MongoDB workforce and workload federation](https://www.mongodb.com/docs/manual/core/oidc/security-oidc/)
- [Self-managed workforce configuration](https://www.mongodb.com/docs/manual/core/oidc/workforce/configure-oidc/)
- [PyMongo OIDC authentication](https://www.mongodb.com/docs/languages/python/pymongo-driver/current/security/authentication/oidc/)
- [PyMongo OIDC callback implementation](https://github.com/mongodb/mongo-python-driver/blob/4.10.1/pymongo/auth_oidc_shared.py)
- [mongolite public connection constructor](https://github.com/jeroen/mongolite/blob/master/R/mongo.R)
- [mongolite native client constructor](https://github.com/jeroen/mongolite/blob/master/src/client.c)
