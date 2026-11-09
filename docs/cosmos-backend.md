# Azure Cosmos DB for NoSQL backend

Research and implementation: 9 November 2026.

`oauth_db_cosmos_api()` reads Cosmos DB for NoSQL using the visitor's
Microsoft Entra access token. It supports parameterized SQL queries,
automatic or explicit pagination and point reads with partition keys.
It uses the package's session-bound HTTP provider and httr2. No new runtime
dependencies are needed beyond the existing optional jsonlite package.

## Client choice

AzureCosmosR's public `cosmos_endpoint()` accepts master or resource keys.
Its request signer and retries are built around those credentials; its
Azure Resource Manager OAuth token is for account administration.
The inspected [source](https://github.com/Azure/AzureCosmosR/blob/58e0461af1b561e817aef0b97a06e82cfc437c08/R/endpoint.R)
doesn't provide a public per-request Entra token callback for document
queries. Replacing its internal signer would couple this package to private
internals and retain different retry and credential-lifetime behavior.

The HTTPS gateway therefore fits the existing HTTP backends better than
ODBC, an SDK bridge or changes to AzureCosmosR. Scope is NoSQL data reads,
not account administration, writes or the MongoDB, Cassandra, Table and
Gremlin protocols. Cosmos DB in Fabric is unvalidated.

## Authentication

Microsoft's [REST authorization specification](https://learn.microsoft.com/en-us/rest/api/cosmos-db/access-control-on-cosmosdb-resources)
defines the encoded authorization string with type `aad`, version `1.0`
and the user's OAuth token as `sig`. This differs from the ordinary HTTP
bearer header used by other backends. The shared HTTP transport now accepts
an internal authentication function; its existing default remains the
httr2 bearer-token helper. Cosmos supplies its own encoded header and a
locale-independent UTC HTTP date for each attempt.

The [RBAC guide](https://learn.microsoft.com/en-us/azure/cosmos-db/how-to-connect-role-based-access-control)
describes data-plane roles for users, groups and applications. Subscription
roles and account-management access don't replace these roles. RBAC
enforces container/database permissions; a query filter isn't document-level
authorization.

`oauth_db_cosmos_client()` requests the public-cloud
`https://cosmos.azure.com/.default` resource scope with OIDC sign-in and
refresh scopes. It uses a dedicated `cosmos` target. Microsoft's
[API-permission inventory](https://github.com/microsoft/mcp/blob/main/servers/Azure.Mcp.Server/azd-templates/api-permissions.md)
lists Cosmos DB among APIs without exposed API permissions. The preset
doesn't invent a delegated permission or mix `.default` with the dynamic
permissions of the general Microsoft client. Tenant approval and user-token
issuance for a custom Web registration remain live acceptance requirements.
The preset doesn't promise that assigning a Cosmos DB role alone enables
third-party app consent. A custom provider and resource can be supplied.

## Query protocol and results

The [query specification](https://learn.microsoft.com/en-us/rest/api/cosmos-db/query-documents)
defines POST queries, `application/query+json`, separate parameter
descriptors and continuation headers. The client follows empty result
pages when a continuation exists, rejects repeated cursors and keeps one
deadline and authorization across an automatic query. It forwards opaque
continuations only in headers to the same configured endpoint. It carries
session tokens within that operation and doesn't retain them between
accounts or independent queries.

Partition headers contain JSON arrays, including null and hierarchical
key components. Cross-partition execution is enabled only when no key was
supplied. The gateway isn't a replacement for SDK query-plan execution;
cross-partition plans that need client merging are outside this backend.

The response parser checks document arrays and page counts before exposing
results. Raw results retain JSON lists, including explicit nulls. Object
projections become data frames with list columns for nested or mixed values;
large JSON integers remain strings. Scalar and mixed projections get a
`value` list column. Request charges are accumulated across pages, with
`NA_real_` when a page omits that header.

Queries and point reads can renew and retry once after HTTP 401. Other
errors, including throttling, stop without automatic retry. No writes,
stored procedures, master-key discovery, environment credential chain or
service-principal fallback are exposed.

## Acceptance checks

The offline suite covers wire headers and JSON bodies, parameter encoding,
partition routing, point reads, empty and multiple pages, token renewal,
single 401 refresh, error redaction, invalid responses, timeouts and account
lifecycle. The source guide constructs a complete app that waits for
sign-in. These checks use synthetic access tokens and mocked Cosmos DB
responses, not a cloud database.

A real deployment still needs to establish:

1. Browser authorization and refresh for the chosen tenant, custom app
   registration and Cosmos DB audience.
2. Two users with different container-level data-plane roles, including
   denied reads and account switching.
3. Partition and cross-partition queries, continuation tokens, point reads,
   JSON types, session tokens and request-charge headers against that account.
4. Expiry, permission removal, sign-out, network restrictions and throttling
   without use of host credentials.
