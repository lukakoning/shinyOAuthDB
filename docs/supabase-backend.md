# Supabase backend decision

Investigated on 8 November 2026. Supabase's REST Data API uses PostgREST;
its project gateway requires an application API key alongside the user's
bearer token. Reuse the existing PostgREST client so filtering, schema
selection, RPCs and authorization lifetime follow one implementation.

`oauth_db_supabase_api()` accepts a project base URL and a publishable key
or legacy `anon` JWT. It appends `/rest/v1` and adds an `apikey` header to
the underlying request. The existing HTTP code supplies the current user
access token and enforces the same retry and authorization checks.
`OAuthSupabaseAPI` inherits the PostgREST client and changes its printed name.

Project key validation rejects elevated secret keys and legacy JWTs whose
decoded role differs from `anon`. Decoding checks the key's intended role;
Supabase verifies the signature and accepts or rejects the key. The key
never substitutes for an unavailable user authorization.

`oauth_db_supabase_client()` discovers the project's `/auth/v1` OIDC issuer.
PKCE, nonce validation and signed ID-token validation remain in shinyOAuth.
The preset chooses HTTP Basic authentication for a nonempty secret and
public-client authentication otherwise. It requests `openid`, `profile`
and `email`, without `offline_access`.

Native OAuth server support needs an enabled server, an existing sign-in
and consent frontend, a registered Shiny callback and asymmetric signing
keys. A third-party provider configured for Data API trust can supply the
authorization instead; a social-login integration alone is insufficient.

Database privileges and RLS enforce data access. OIDC scopes describe
identity information and do not grant table permissions. This backend
does not implement Storage, Realtime, the Management API, arbitrary SQL
or direct PostgreSQL authentication.

Sources:

- [OAuth server setup](https://supabase.com/docs/guides/auth/oauth-server/getting-started)
- [OAuth flows and client authentication](https://supabase.com/docs/guides/auth/oauth-server/oauth-flows)
- [OAuth tokens and RLS](https://supabase.com/docs/guides/auth/oauth-server/token-security)
- [Project API keys](https://supabase.com/docs/guides/getting-started/api-keys)
- [Third-party authentication](https://supabase.com/docs/guides/auth/third-party/overview)
- [Self-hosted API keys](https://supabase.com/docs/guides/self-hosting/self-hosted-auth-keys)

Live validation still needs a configured hosted or self-hosted project.
Check native browser sign-in and refresh, permissions for two users,
write denial, key rotation, custom domains and third-party JWT mapping
before claiming these deployment combinations have been tested.
