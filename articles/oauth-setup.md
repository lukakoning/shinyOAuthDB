# OAuth setup for your app

OAuth lets your Shiny app query data on behalf of the person who signed
in. The database still decides what that person may read. Start with
your [database
guide](https://lukakoning.github.io/shinyOAuthDB/articles/getting-started.html#choose-your-source)
for a complete app; use this page to understand the settings it asks you
to collect.

## What the settings mean

| Setting | Meaning |
|----|----|
| Client ID | The sign-in service’s identifier for your Shiny app |
| Client secret | The app’s credential, stored on the Shiny server |
| Redirect URI | The exact address where the browser returns after sign-in |
| Issuer | The sign-in service’s URL, identifying who issues tokens |
| Scope | A permission the app asks the person to approve |
| Audience | The database or API the access token is intended for |
| Database role | The permissions the database applies after checking the token |

The guides use `http://localhost:8100` as the callback for apps you run
in R. The packaged Docker demos use `http://localhost:18100`. Register
the exact value, including any path and trailing slash. Use your app’s
HTTPS address when deploying.

## Save credentials in R

Open the environment file for your app project:

``` r

file.edit(".Renviron")
```

Add the values from the registration, as shown in the backend guide:

``` text
OAUTHDB_CLIENT_ID=your-client-id
OAUTHDB_CLIENT_SECRET=your-client-secret
```

Restart R, then `Sys.getenv("OAUTHDB_CLIENT_ID")` should return the ID.
Keep `.Renviron` out of Git. On a hosting service, set the same
environment variables in the app’s settings. The secret belongs on the
server.

## Register a Microsoft Entra app

Azure SQL, Fabric and Azure PostgreSQL use Microsoft Entra. Start in the
[Entra admin center](https://entra.microsoft.com/), under **App
registrations**. Create a registration in your organization’s tenant,
then copy **Application (client) ID** and **Directory (tenant) ID** from
its overview. Under **Authentication**, add a **Web** platform with
`http://localhost:8100`. Under **Certificates & secrets**, create a
client secret and copy its **Value** before leaving. Save the tenant ID
as `OAUTHDB_TENANT_ID`. Microsoft’s [registration
instructions](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app)
describe the available account types.

Under **API permissions**, add the backend’s delegated permission: the
app acts as the signed-in person. SQL uses Azure SQL Database’s
`user_impersonation`; Azure PostgreSQL uses Azure OSSRDBMS Database
access. Fabric API calls need the permissions listed in the [Fabric
guide](https://lukakoning.github.io/shinyOAuthDB/articles/fabric.md). An
administrator may need to grant consent or allow the application.

Database access is a separate step: the administrator must also create
or grant the person’s database identity. A successful Microsoft login
doesn’t give a user access to a table.

## Use Keycloak with a self-hosted database

Keycloak is an open-source sign-in service you can host beside your
database. The [local
demos](https://lukakoning.github.io/shinyOAuthDB/articles/local-demos.md)
already register an app, create accounts and configure database
audiences. Copy their files with `oauth_db_demo(action = "files")` to
inspect an example.

For your own realm, create an **OpenID Connect** client in Keycloak’s
**Clients** screen. Enable the authorization-code (**Standard**) flow
and PKCE S256; enter your exact Shiny callback under valid redirect
URIs. For a server app with client authentication enabled, copy its
secret from the credentials tab. The demos use a confidential client
with a public demo secret. Use a secret belonging to your own
registration when deploying.

Find the issuer in the realm’s OpenID configuration. It normally looks
like `https://login.example.org/realms/reporting`. The discovery
document also lists `jwks_uri`, where the database can fetch public
signing keys. Use client scopes and protocol mappers to include the
database audience and the claims required by its guide. Configure the
database to trust those keys and map verified identities to database
permissions. See Keycloak’s [administration
guide](https://www.keycloak.org/docs/latest/server_admin/index.html).

## Check the database accepts the token

Browser sign-in alone isn’t enough. The database must trust the token’s
issuer and signing keys, accept its audience, and recognize its identity
or role claim. The app sends an **access token** to the database; an ID
token describes the login and serves a different purpose.

If login works but queries fail, compare the registration’s audience,
scopes and claim mapping with the database configuration. Check database
grants and network access next. Keep tokens and secrets out of logs.

For a client that needs several APIs, token targets obtain a separate
token for each resource. See [Authentication and
sessions](https://lukakoning.github.io/shinyOAuthDB/articles/authorization.md)
after your first query works.
