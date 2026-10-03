# Cloud warehouse research for shinyOAuthDB

Research date: 2026-10-02. This is a design evidence report. “Documented” means an official vendor or package source supports the mechanism; it does not mean a live connection was tested. No production credentials or database instances were available for this investigation. Recommendations and proposed APIs below are design judgments.

## Main conclusion

The package should bridge a session-owned shinyOAuth authorization to an existing database/API client. It should represent **which principal the backend actually sees**, **how a credential is transformed**, and **when a client can accept refreshed credentials**. A token string alone is insufficient to describe these differences.

The agreed core is delegated-user access. Service principals, app service accounts, PATs, CLI profiles and ambient cloud credentials are not fallbacks. A configured but unavailable user authorization must stop the operation. Plain assumed-role federation is included below only to explain its different semantics; it is outside the delegated-user core unless a separate, explicit user-preserving policy mechanism is proven.

Snowflake and Databricks are strong near-term targets. BigQuery has a good delegated-user authorization model but the obvious R client has a shared authentication state problem. AWS also has genuine user-preserving integrations; plain STS role assumption must be distinguished from them.

## Capability matrix

| Target and method | Backend principal and authorization | Existing R transport | Evidence and remaining gate | Suggested priority |
| --- | --- | --- | --- | --- |
| Databricks native OAuth U2M | Databricks user; workspace/warehouse permissions and data privileges | Local brickster fork for REST and SQL DBI; ODBC alternative | Vendor flow documented; local token-provider hook inspected; upstream-release and live two-user tests required | First release with migration |
| Azure Databricks Entra delegated token | Provisioned Databricks user associated with Entra identity | brickster bearer token/provider; driver-specific ODBC pass-through | Microsoft documents Databricks audience; workspace grants required; test intended tenant and workspace | First release, explicit legacy/Entra mode |
| Databricks account-wide token federation | Existing Databricks user after IdP JWT exchange | Transform credential, then brickster token provider | Official account-wide policy and exchange documented; issuer/audience/username mapping must be configured | Follow core Databricks adapter |
| Snowflake External OAuth | Mapped Snowflake user plus permitted Snowflake roles | DBI + odbc + official Snowflake ODBC driver | Official external-token and driver input documented; role mapping, ambient auth suppression, driver lifecycle tests required | First expansion after existing integrations |
| Snowflake OAuth | Snowflake user after Snowflake authorization flow | Same ODBC adapter; separate shinyOAuth provider configuration | Custom-client flow documented; no assumption of OIDC discovery; refresh/client-auth compatibility to prove | Same transport, second auth recipe |
| BigQuery Google user OAuth | Google user with IAM and row/column policies | bigrquery/gargle, subject to isolation issue; token-capable ODBC candidate | Vendor documented; bigrquery global .auth makes ordinary shared-process Shiny use unsuitable | Research/upstream gate before advertising |
| BigQuery Workforce Identity Federation | External workforce-pool principal with direct IAM grants | Explicit token exchange + credential-aware client; R support provisional | Google documents direct federated API access; current R auth-object/isolation support unproven | Later, alongside safe BigQuery transport |
| Redshift native Entra IdP federation | Namespace-prefixed database user/roles derived from Entra | DBI + odbc + Redshift ODBC BasicJwtCredentialsProvider | Vendor documents native IdP and JWT parameters; test scope, mapping and driver version | Advanced expansion |
| Redshift IAM Identity Center propagation | IAM Identity Center user and group-derived Redshift grants | DBI + odbc + Redshift IdpTokenAuthPlugin | Vendor documents external-JWT input; integration, mapping and driver lifecycle required | Advanced expansion |
| Athena trusted identity propagation | Identity-enhanced role session preserving Identity Center user; Lake Formation permissions | DBI + odbc + Athena ODBC JWT_TIP | Official driver and setup documented; region, credential caches and JWT exchange replay behavior require tests | Advanced expansion |
| AWS plain AssumeRoleWithWebIdentity | Assumed IAM role session; permissions from role/session policy | paws; existing AWS DBI clients if explicit credentials supported | STS documented; does **not** automatically reproduce a human user's existing warehouse grants | Outside delegated-user core |

Matrix entries are expanded and linked below. “First release” remains conditional on the existing fabricQueryR/brickster hook contracts and package versions, addressed in the local-code report.

## Snowflake

### External OAuth and Snowflake OAuth need different authorization recipes

External OAuth accepts tokens from an organization-managed authorization server, including Entra ID, Okta, PingFederate or a configured custom provider. A Snowflake security integration establishes issuer, signature keys, audience validation, a token claim mapped to LOGIN_NAME or EMAIL_ADDRESS, and role restrictions. Logging into the Shiny app with the same IdP is insufficient until these database-side mappings exist. [External OAuth integration definition](https://docs.snowflake.com/en/sql-reference/sql/create-security-integration-oauth-external).

The external token constrains session roles alongside the user's Snowflake grants. Common scopes include `session:role:<role>` and `session:role-any`; the latter is governed by the integration's ANY-role policy. The documented privileged roles are blocked by default. OAuth scope should never be described as a replacement for database grants. [External OAuth overview](https://docs.snowflake.com/en/user-guide/oauth-ext-overview).

For Entra, define a Snowflake resource application and expose delegated permissions for the intended role. Request a fully qualified resource scope; configure the matching audience in Snowflake. The vendor Entra walkthrough currently uses `session:scope:analyst` when defining a delegated scope, while its surrounding role/ANY examples use `session:role:`. Treat the exact scope list as deployment configuration and resolve that vendor-documentation inconsistency against a real integration instead of generating a guessed scope from a role name. Do not copy the walkthrough's password-grant test into the Shiny implementation: use shinyOAuth's browser authorization flow. [Entra External OAuth setup](https://docs.snowflake.com/en/user-guide/oauth-azure).

Snowflake OAuth instead uses Snowflake as the authorization server. Custom clients use `/oauth/authorize` and `/oauth/token-request`, with registered redirects and an OAuth security integration. A role scope can constrain the consented role; `refresh_token` requests renewable access when permitted by integration and consent. PKCE is documented. Configure this as OAuth explicitly; generic OIDC discovery and an ID token are not prerequisites of that flow. [Snowflake custom OAuth clients](https://docs.snowflake.com/en/user-guide/oauth-custom).

### Reuse ODBC rather than implement a Snowflake SQL client

The official Snowflake ODBC driver accepts `authenticator = "oauth"` and `token = <access token>`. It also has driver-managed browser/client-credentials modes, but those introduce separate credential owners. For shinyOAuthDB the browser callback and refresh credentials should remain with shinyOAuth. A supplied access token should be the only permitted identity source. Driver versions also expose `TOKEN_FILE_PATH`; current documentation says that file wins when both token and token-file input are configured, so an inherited DSN/file credential can defeat an otherwise explicit token. Reject that combination in the adapter. [Snowflake ODBC parameters](https://docs.snowflake.com/en/developer-guide/odbc/odbc-parameters).

`odbc::snowflake()` returns an ordinary ODBC DBI connection and resolves settings through snowflakeauth, configuration files and supported hosting-platform credentials. Its documented helper supports `...` for additional arguments. The current source overlays explicit arguments on resolved values, and an explicit authenticator skips its snowflakeauth discovery branch. However, connectcreds viewer discovery occurs earlier. Require explicit account/host, authenticator and token; audit unwanted token-file/DSN inputs and verify final principal rather than relying on helper defaults. Generic `odbc::odbc()` with a complete explicit parameter set is a viable fallback when helper discovery cannot be controlled. [odbc Snowflake helper](https://odbc.r-dbi.org/reference/snowflake.html), [helper implementation](https://github.com/r-dbi/odbc/blob/main/R/driver-snowflake.R).

Illustrative transport construction, not a tested package function:

```r
DBI::dbConnect(
  odbc::snowflake(),
  account = target$account,
  authenticator = "oauth",
  token = credential$access_token,
  warehouse = target$warehouse,
  database = target$database,
  schema = target$schema,
  role = target$role
)
```

Keep role in the immutable target configuration and include effective role in diagnostics/cache partitioning. Supply username only when the selected driver requires it and its compatibility with OAuth has been demonstrated; never infer it from a display name. The odbc helper's present username/password validation is another reason to test the exact supported argument set.

Design implication: initially model Snowflake as **token supplied when connecting**. Do not claim that changing an R token callback refreshes an already-open native ODBC connection. Disconnect on logout/account change; refresh before a new connection; establish documented behavior for long-lived sessions through integration tests. Database sessions may outlive the access token used to establish them.

## Databricks

### Three user-preserving methods

1. **Native Databricks OAuth U2M.** For a custom Shiny application register/enable its OAuth integration and redirect URI. The documented code flow uses PKCE and `all-apis offline_access`; workspace authorization/token endpoints live under `/oidc/v1/`. Account endpoints have a separate account host/path. Do not ship `databricks-cli` as the application client ID. Keep account and workspace targets distinct. [Databricks OAuth U2M](https://docs.databricks.com/aws/en/dev-tools/auth/oauth-u2m).

2. **Entra access token for Azure Databricks.** The Microsoft-documented resource/audience is `2ff814a6-3304-4ab8-85cb-cd0e6f879c1d`, with the example v2 scope `<resource-id>/.default`. The user must exist in the intended workspace and have access. Current Microsoft documentation prefers automated management/federation over manual token handling. shinyOAuth can own browser authorization and refresh, so use this as an explicit credential recipe, never a CLI/environment fallback. [Microsoft Entra tokens for Azure Databricks](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/user-aad-token).

3. **Account-wide token federation.** An administrator registers trusted issuer, accepted audiences and the claim containing the Databricks username. This matches an existing account user and is different from workload federation tied to a service principal. Policy configuration is not user provisioning. The default claim is `sub`, but an organization's `sub` may be an opaque ID rather than its Databricks username; configure the actual mapping. [Federation policy](https://docs.databricks.com/aws/en/dev-tools/auth/oauth-federation-policy).

Federation exchanges the IdP JWT at the target workspace `/oidc/v1/token` using RFC 8693 and `scope = "all-apis"`. For account-wide user federation omit the service-principal `client_id`. The resulting Databricks token retains the supplied token's expiration, so reacquire a valid subject token and exchange it again when necessary; do not invent a refresh token. This transform should be an explicit credential adapter between shinyOAuth and brickster, cached only inside its owning login generation. [Federated token exchange](https://docs.databricks.com/aws/en/dev-tools/auth/oauth-federation-exchange).

The database/platform still decides warehouse access and data privileges. A token cannot grant missing warehouse query permission or Unity Catalog `USE CATALOG`, `USE SCHEMA` and `SELECT` privilege. These rights are evaluated for the actual authenticated identity. `CAN USE` is the usual warehouse grant; current ACLs also grant query execution to `CAN MONITOR`. [Unity Catalog query requirements](https://docs.databricks.com/gcp/en/ldp/dbsql/compute), [SQL warehouse access](https://docs.databricks.com/aws/en/security/auth/access-control/#sql-warehouse-acls).

### Existing brickster fork is an excellent seam

Read-only inspection found:

- `../brickster/R/package-auth.R`: exported `db_token_provider(host, token)` expects a callback accepting `force_refresh`; binds it to a normalized workspace; avoids credential substitution and HTTP redirects; uses httr2 OAuth retry behavior on a rejected token.
- `../brickster/R/databricks-dbi.R`: `DatabricksSQL()` DBI connections retain a provider in their credential slot. Subsequent SQL requests can obtain a current token.
- `../brickster/R/shiny-auth.R`: Shiny login/module/provider wiring, captured login generation and parent-process/worker boundary are the bridge responsibility to migrate.

Recommendation: move high-level Shiny integration into shinyOAuthDB while retaining a small, general external-token/provider hook in brickster. Reuse brickster's SQL execution, polling, chunk download, Arrow parsing and DBI methods. Do not move or duplicate these engines. Published/upstream brickster versions must be checked independently: these are local fork findings.

Provide two routes through a shared credential contract: a provider object for brickster's in-process REST/DBI operations, and a resolved short-lived access token for an isolated worker. A provider closure that touches Shiny reactives must remain in its owning R process. Worker completion needs a parent-side check that the login generation is still current before returning data to the app.

### ODBC is an alternate Databricks transport

The Databricks ODBC driver documents `AuthMech = 11`, `Auth_Flow = 0` and `Auth_AccessToken` for OAuth token pass-through, along with host/HTTP path and TLS settings. Reuse DBI/odbc for deployments that already install this driver. Driver token-update APIs do not automatically imply that R odbc exposes them, so declare refresh-at-connect until that specific capability is implemented and tested. [Databricks ODBC authentication](https://docs.databricks.com/aws/en/integrations/odbc/authentication).

The new Databricks JDBC driver explicitly documents external-JWT federation during token pass-through. This is evidence for that JDBC driver, not proof that every Simba ODBC version has the same behavior. Prefer exchange-before-transport for the initial generic design. [Current JDBC token pass-through](https://docs.databricks.com/aws/en/integrations/jdbc-oss/authentication).

## BigQuery

Google-issued user OAuth tokens authorize API requests as the user, with IAM grants and applicable row-level policies. Data access and job/billing-project access are separate: a user might read a dataset but lack permission to submit jobs in the chosen billing project. Specify billing project as target configuration. Use a Google web OAuth client with matching hosted redirect, deliberate BigQuery scope consent and shinyOAuth-controlled refresh. [BigQuery authentication](https://docs.cloud.google.com/bigquery/docs/authentication), [BigQuery row policies](https://docs.cloud.google.com/bigquery/docs/managing-row-level-security).

### The R package isolation problem is substantial

`bigrquery::bq_auth()` accepts an `httr::Token2.0` or configured httr request and defaults to BigQuery plus cloud-platform scopes. `gargle::credentials_byo_oauth2()` can accept externally obtained credentials, but it does not add scopes to an existing token. shinyOAuth's token object cannot simply be assumed to inherit Token2.0. Any adaptation should delegate refresh to the single shinyOAuth owner rather than maintain a second refresh-token cache. [bq_auth](https://bigrquery.r-dbi.org/reference/bq_auth.html), [gargle token input](https://gargle.r-lib.org/reference/credentials_byo_oauth2.html).

Current bigrquery source has a package `.auth` object; `bq_auth()` installs a token there and `bq_token()` reads it. Its DBI driver takes project/dataset/billing settings, and unused `...` is ignored; no documented per-connection credential slot exists. Therefore two DBI connections do not constitute two isolated user identities. Changing bq_auth around a synchronous call is insufficient once requests, refreshes, futures or lazy dbplyr operations outlive the temporary state. [bigrquery authentication source](https://github.com/r-dbi/bigrquery/blob/main/R/bq-auth.R), [DBI driver documentation](https://bigrquery.r-dbi.org/reference/bigquery.html).

Viable design options:

- Preferred: collaborate upstream on an explicit token/provider per client, connection or request and reuse the existing engine.
- Alternative: dedicated worker processes partitioned by identity/login generation; initialize each with that user's short-lived credential and discard after logout. Prove where refresh and all result downloads occur, including optional BigQuery Storage integration. This adds operational complexity and should be an explicit backend mode.
- Alternative: documented token pass-through with a supported BigQuery ODBC driver. Verify the exact installed driver and token refresh behavior before advertising it.

Do not silently use the app's service account to make BigQuery “work”. Its permissions are a different authorization model.

### External human identities use Workforce federation

Google Workforce Identity Federation supports BigQuery API access and direct workforce-pool IAM principal grants. It is distinct from Workload Identity Federation for applications and from service-account impersonation. Google lists BigQuery as generally available for Workforce federation, with exclusions for several integration features. [Federated product support](https://docs.cloud.google.com/iam/docs/federated-identity-supported-services).

A configured workforce pool/provider exchanges a trusted external credential at Google STS. Its audience is a workforce-provider resource such as `//iam.googleapis.com/locations/global/workforcePools/<pool>/providers/<provider>`; the original IdP token must satisfy the configured provider's issuer/audience and mapping. A workforce user project requires `serviceusage.services.use`. Keep IdP audience and STS target audience as separate fields. Google documents both STS and Cloud OAuth routes; R gargle support for the exact workforce recipe and session isolation remains to be proven. [Workforce short-lived credentials](https://docs.cloud.google.com/iam/docs/workforce-obtaining-short-lived-credentials).

## AWS Redshift and Athena

### Plain STS is federation into an IAM role

`AssumeRoleWithWebIdentity` exchanges a trusted OIDC token for temporary access key, secret and session token. Trust policy checks issuer/audience/subject, and effective permissions derive from the assumed role intersected with session policy. This alone does not carry a human's Redshift SQL grants or Lake Formation user grants. Avoid labeling every STS-based connection “use the user's existing database permissions”. [AWS STS web identity API](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html).

If needed, reuse paws for that exchange and supply credentials to client instances explicitly. Paws documents per-service temporary credentials and expiry, plus anonymous credentials before web-identity exchange. This supports multiple identities without `Sys.setenv()` mutations. Existing Athena R clients such as noctua/RAthena are transport candidates for IAM-role access, but user-preserving Identity Center/TIP compatibility is a separate feature gate. [Paws instance credentials](https://github.com/paws-r/paws/blob/main/docs/credentials.md).

### Redshift offers two genuinely different delegated-user routes

Native identity-provider federation currently documents Entra as its supported third-party provider. Administrators register issuer/application/audiences in `CREATE IDENTITY PROVIDER` and map namespace-prefixed roles to Entra groups. There is therefore a real path from an Entra login to Redshift-managed data permissions. Do not copy the Power BI example's resource audience into an unrelated Shiny app: align it with the configured accepted audience and exposed scope. [Redshift native IdP setup](https://docs.aws.amazon.com/redshift/latest/mgmt/redshift-iam-access-control-native-idp-setup.html).

The Redshift ODBC JWT plugin accepts `plugin_name = "BasicJwtCredentialsProvider"` with `web_identity_token`. Reuse that driver rather than a PostgreSQL password connection for this particular native-JWT recipe. Parameter names and user/group mapping must be validated against the configured ODBC release. [Redshift ODBC options](https://docs.aws.amazon.com/redshift/latest/mgmt/odbc20-configuration-options.html).

IAM Identity Center is a separate supported route, with users/groups configured in Identity Center and corresponding Redshift database roles. A trusted token issuer and client application establish how an external JWT maps to that user. Redshift can then use namespace-prefixed Identity Center identities for database access. [Identity Center Redshift integration](https://docs.aws.amazon.com/redshift/latest/mgmt/redshift-iam-access-control-idp-connect.html), [integration setup](https://docs.aws.amazon.com/redshift/latest/mgmt/redshift-iam-access-control-idp-connect-console.html).

The documented ODBC `IdpTokenAuthPlugin` accepts `token` and `token_type`: `EXT_JWT` for an external issuer's JWT or `ACCESS_TOKEN` for an IAM Identity Center access token. It exists for clients that manage authentication themselves, which fits shinyOAuthDB. Prefer it over a driver that opens a local browser on the app server. [Redshift OAuth client integration](https://docs.aws.amazon.com/redshift/latest/mgmt/redshift-iam-access-control-idp-connect-oauth.html).

### Athena trusted identity propagation is also a real user-preserving path

Athena now documents Identity Center trusted identity propagation through JDBC/ODBC. Users/groups must exist in Identity Center and receive relevant Lake Formation permissions; compatible workgroup, region and roles are required. This transfers the user identity across service boundaries rather than stopping at a generic role. [Athena trusted identity propagation](https://docs.aws.amazon.com/athena/latest/ug/using-trusted-identity-propagation.html).

For ODBC the documented input is `AuthenticationType = "JWT_TIP"`, `web_identity_token`, `WorkGroupArn`, `ApplicationRoleArn` and `role_session_name`, with optional AccessRoleArn/CustomerIdcApplicationArn when tagging cannot resolve them. Preserve ODBC names: JDBC examples use `CredentialsProvider` and `JwtWebIdentityToken`, which should not be copied mechanically. `JwtTipFileCache` defaults to disabled; keep it disabled for shared-process Shiny unless a demonstrably user-partitioned cache is required. [Athena ODBC JWT_TIP parameters](https://docs.aws.amazon.com/athena/latest/ug/odbc-v2-driver-jwt-tip.html).

The setup documents minimum supported driver generations and a JWT `jti` replay consideration: a test connection can consume a JWT intended for exchange. It also defines Identity Center application permissions/scopes, including Lake Formation query scope. Model the IdP JWT, its exchange and the resulting identity-enhanced temporary credentials separately. Live tests must include two users, reconnection, revocation and the driver's cache behavior. [Athena Identity Center setup](https://docs.aws.amazon.com/athena/latest/ug/using-trusted-identity-propagation-setup.html).

## Adapter metadata and package boundaries

Recommended capability fields, stored as declarative backend metadata:

| Field | Purpose | Example |
| --- | --- | --- |
| `principal_kind` | Backend sees human user, service principal, workload or assumed role | `user`, `assumed_role` |
| `authorization_model` | Identify platform policy source | `snowflake_roles`, `unity_catalog`, `google_iam`, `lake_formation_tip` |
| `credential_type` | Prevent accidental cross-protocol substitution | `oauth_access_token`, `oidc_subject_token`, `aws_session_credentials` |
| `credential_transform` | Make exchange/mapping explicit | `none`, `databricks_rfc8693`, `google_workforce_sts` |
| `credential_delivery` | Where the existing transport consumes it | `per_request_provider`, `connect_token`, `password`, `aws_client_config` |
| `refresh_strategy` | What can actually change safely | `callback`, `reconnect`, `driver_update_verified` |
| `identity_isolation` | Scope in which credentials are stored | `connection`, `request`, `dedicated_process` |
| `target_binding` | Restrict token use to configured endpoint/account/resource | workspace origin, account, tenant, audience |
| `dbi_available` | Permit DBI/dbplyr reuse without promising all DBI features | `TRUE`, verified backend limitations |
| `status` | Separate ideas from supported release capability | `documented`, `prototype`, `integration_tested` |

An adapter should describe provider-specific required scopes and expected resource/audience separately from the application's login scopes. Explicitly validated exchanges may consume an OIDC ID token when the target's federation protocol requires one; ordinary SQL/API bearer access uses its access token. Do not turn arbitrary login ID tokens into general database bearer tokens.

Core functions should accept an existing shinyOAuth session authorization and create a session-owned credential provider. Target constructors contain non-secret endpoint/warehouse/database/role configuration. Transport adapters consume the provider using documented inputs. Engine functions, result decoding, DBI generics and SQL translation remain in DBI/odbc/brickster/fabricQueryR/bigrquery/dbplyr.

Keep connection/result cache partitioning at least by backend target, effective principal, login generation and authorization context (including role). A shared pool keyed only by connection parameters is unsuitable for these delegated-user connections. Logout invalidates the bridge and prevents new queries even when a native session still exists. Background results are checked before presentation to the current session.

## Proposed roadmap and release gates

1. Migrate existing Fabric and Databricks Shiny integration while preserving narrow, general credential hooks in the engine packages. Establish end-to-end identity and lifecycle tests using two users with visibly different grants.
2. Add Azure SQL and Azure PostgreSQL through established DBI drivers, and Snowflake External OAuth through ODBC. Keep managed-service auth modes distinct from generic engines.
3. Add Snowflake-native OAuth provider recipe and Databricks account-wide federation as explicit credential transforms over the same transports.
4. Resolve BigQuery credential isolation upstream or select a tested isolated/token-capable transport before advertising multi-user support.
5. Add Redshift native Entra/Identity Center and Athena JWT_TIP as advanced recipes after driver-based proof. Do not include plain AWS STS in the delegated-user capability set.

Every “supported” adapter needs evidence for its actual backend principal, denied data access, refresh behavior, logout/account-change handling, simultaneous users, failed-refresh behavior and no ambient identity substitution. Driver-dependent adapters should publish tested package/driver/OS combinations. Do not promise global logout revokes data already downloaded, or that access-token expiry immediately terminates established database sessions.

Open decisions for the owner: whether first release should prioritize driver-free REST deployments versus installed ODBC; whether multi-provider/federation use is a first-release requirement; whether BigQuery should wait for upstream hooks or carry an explicit process-isolation mode; whether API/DBI write access is in scope initially. All options can use the same credential/target boundaries.
