# Neo4j backend decision

Research from 9 November 2026.

## Use HTTPS Query API v2

Neo4j's [Query API](https://neo4j.com/docs/query-api/current/) targets
languages without an official driver and works with self-managed servers
and Aura. Its [bearer authentication](https://neo4j.com/docs/query-api/current/authentication-authorization/)
accepts a token obtained by the application from the database's configured
SSO provider. This fits the existing session-bound HTTP transport without
adding Python, Java or a Bolt implementation.
Neo4j itself still needs its Bolt connector enabled for the internal
Query API driver; the Shiny client only connects over HTTPS.

An official Python Bolt driver through reticulate could supply bearer
authentication, but would add Python lifecycle and dependency management.
JDBC would require a JVM. Neither is needed for single-statement Cypher
queries, so those routes remain outside this backend's scope. Query API v2
starts with Neo4j 5.19; versions before 5.25 require explicit endpoint
enablement. The older transactional HTTP API is deprecated and unavailable
on Aura.

## Public API and result contract

`oauth_db_neo4j_api()` binds the visitor's current access token to an HTTPS
database endpoint. `$query()` sends one parameterized Cypher statement and
returns a data frame; `$execute()` asks for and returns update counters.
`raw = TRUE` returns the parsed native envelope, including graph objects,
notifications and bookmarks. It still validates the result and query errors.

The initial implementation uses [plain JSON](https://neo4j.com/docs/query-api/current/plain-json/).
It keeps nested graph values as lists and preserves large JSON integers as
strings, while inferring ordinary scalar columns from the returned values.
Empty/all-null columns have no server schema and remain logical.
[Typed JSON](https://neo4j.com/docs/query-api/current/typed-json/) preserves
Cypher type distinctions, but would require a separate mapping for graph,
spatial and temporal objects. That is not part of this initial API.

The shared HTTP layer pins each request to its starting authorization,
checks access after the response, verifies HTTPS and refuses redirects.
All operations are POST and never replay automatically, even after 401.
Neo4j can report statement errors with HTTP 202; any nonempty `errors`
array raises a sanitized query failure and discards partial results.

Each request uses the server's implicit transaction. There are no saved
bookmarks, explicit transaction handles, impersonation settings or shared
driver token caches. Long-running work can outlive the client timeout.

## Authentication boundary

Self-managed deployments need Enterprise SSO configured for JWT access
tokens, trusted issuer/audience/signing keys and database role mappings.
The [SSO guide](https://neo4j.com/docs/operations-manual/current/tutorial/tutorial-sso-configuration/)
contains both access-token and ID-token examples; the backend supports the
access-token path. shinyOAuth handles browser sign-in and token renewal.

Aura console OAuth credentials authorize management operations, not Cypher
queries. Aura database SSO depends on the tier and configuration; a hosted
deployment needs its own end-to-end acceptance check. There is no universal
Neo4j OAuth client preset because the deployment chooses its provider and
audience. See the [source guide](../vignettes/neo4j.Rmd).

## Native validation

The [Docker fixture](../integration/neo4j-oauth/README.md) passes 30 assertions
against Neo4j 5.26.32 Enterprise on Windows with R 4.5.1. The database
validates locally signed JWTs through a verified HTTPS JWKS endpoint.
Alice and Bob have different node-label privileges; a writer can create
nodes and receive counters. Incorrect issuer, audience, signature and
expiry are rejected. Bound parameters, graph paths, exact large integers,
token replacement, sign-out and client TLS trust/hostname checks pass.

The integration workflow runs this fixture sequentially with the other
database checks. Tests use fixture tokens rather than browser sign-in;
live key rotation, clustering and Aura remain separate acceptance checks.
