# Dremio backend decision

Investigated on 9 November 2026. `oauth_db_dremio()` uses Apache Arrow's
ADBC Flight SQL shared library through adbi's DBI interface.

## Authentication and driver choice

Dremio Enterprise's
[authentication guide](https://docs.dremio.com/current/security/authentication/)
supports direct external JWTs for Flight SQL clients. Its administrator
configures the token provider, accepted audience and Dremio user mapping.
shinyOAuth owns browser sign-in and renewal; shinyOAuthDB supplies the
current access token to the driver.

The [ADBC Flight SQL driver](https://arrow.apache.org/adbc/current/driver/flight_sql.html)
has an explicit authorization-header option, verified TLS, per-RPC
timeouts, prepared statements and Arrow results. Its shared libraries can
be loaded with adbcdrivermanager, independently of a driver-specific R
package. adbi provides the DBI connection; the package's existing cleanup
already force-closes its outstanding results.

Dremio's [ODBC guide](https://docs.dremio.com/current/client-applications/drivers/arrow-flight-sql-odbc-driver/)
also supports OAuth bearer tokens, but lists no parameterized-query support
and excludes Apple Silicon. ADBC avoids adding a second transport solely
for the first Dremio helper. The driver is installed separately, normally
with `dbc install flightsql`; adbcdrivermanager 0.25.0 supports driver
manager names and manifests.

The helper pins the TLS URI and authorization header, disables cookie
middleware and refuses native authentication, routing, header and TLS
overrides. An access-token hash keys connection reuse. On next access,
token changes close the old connection and open one with the current
token. This also handles transparent native reconnects which could
otherwise keep using an expired token. There is no automatic SQL replay.

## Exchange and Cloud boundary

Dremio recommends external JWT exchange for smaller credentials and faster
verification. The first helper uses the documented direct path to keep a
single owner for visitor credentials. ADBC has token-exchange options,
but enabling them would require checking its lifetime handling against
Dremio, refresh behavior and authorization retirement. No additional token
cache or automatic exchange is implemented here.

The [Cloud Classic external-provider guide](https://docs.dremio.com/cloud/security/authentication/app-authentication/external-token/)
uses an empty username, the JWT as the password and `token_type=jwt`.
That is a separate authentication recipe. The initial helper's scope is
a TLS Flight SQL endpoint configured to accept bearer access tokens;
Cloud editions need separate acceptance tests.

## Validation

Unit tests cover driver options, verified TLS, named token targets,
permission loss, parallel visitor credentials, token renewal without
reactive query replay, broken connections, logout and session cleanup.
They also check that native error calls contain argument references rather
than expanded bearer strings.

The native transport fixture uses the actual ADBC driver and adbi against
a local TLS Flight SQL server with synthetic bearer tokens. It checks
authentication on RPCs, user-specific results, TLS rejection and renewed
tokens. It does not emulate Dremio's issuer validation or permissions.

Native transport checks ran on Windows with R 4.5.1, adbi 0.1.2 and 0.1.3,
adbcdrivermanager 0.25.0 and the ADBC Flight SQL driver 1.13.0.

Live acceptance still requires Dremio Enterprise with a configured external
token provider, two users with different permissions, expiry and reconnect
checks, prepared statements, Arrow result types and a Cloud deployment if
Cloud support is claimed. See the [setup guide](../vignettes/dremio.Rmd).
