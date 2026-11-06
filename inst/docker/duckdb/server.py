"""Run a real Quack server with Keycloak JWT validation and read-only access."""
import sys
sys.path.insert(0, '/demo/python')
import duckdb
from support import ISSUER, Proxy, serve

connection = duckdb.connect()
for extension in ['quack', 'httpfs', 'quack_oauth']:
    connection.execute('LOAD ' + extension)
connection.execute('SET quack_oauth_telemetry_enabled = false')
connection.execute(f"""CREATE SECRET demo (
    TYPE quack_oauth_server, issuer '{ISSUER}', audience 'quack-demo',
    jwks_uri 'http://localhost:18080/realms/shinyoauthdb/protocol/openid-connect/certs'
)""")
connection.execute("SET quack_oauth_server_secret_name = 'demo'")
connection.execute('SET quack_oauth_trust_plaintext = true')
connection.execute("SET quack_authentication_function = 'quack_oauth_check_token'")
connection.execute("SET quack_authorization_function = 'quack_oauth_check_authorization'")
connection.execute('CREATE TABLE visible_rows (id INTEGER, marker VARCHAR)')
connection.execute("INSERT INTO visible_rows VALUES (1, 'shared-visible-1'), (2, 'shared-visible-2')")
connection.execute("CALL quack_serve('quack:127.0.0.1:19495', allow_other_hostname=true, disable_ssl=true, token='unused-demo')")


class QuackProxy(Proxy):
    def do_GET(self):
        if self.path == '/health':
            self.json({'ready': True})
        else:
            self.json({'error': 'not found'}, 404)

    def do_POST(self):
        self.forward(19495)


print('DuckDB Quack with Keycloak validation is ready.')
serve(QuackProxy, 18444)
