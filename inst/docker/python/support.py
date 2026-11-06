"""HTTP and TLS helpers for the disposable local database demos."""
import http.client
import json
import ssl
import threading
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ISSUER = 'https://localhost:18443/realms/shinyoauthdb'
CA = '/fixtures/tls/ca-cert.pem'


def keycloak(path, form=None):
    data = None if form is None else urllib.parse.urlencode(form).encode()
    request = urllib.request.Request(ISSUER + path, data=data)
    with urllib.request.urlopen(request, context=ssl.create_default_context(cafile=CA), timeout=20) as response:
        return json.load(response)


def service_token(client_id, secret):
    return keycloak('/protocol/openid-connect/token', {
        'grant_type': 'client_credentials', 'client_id': client_id, 'client_secret': secret
    })['access_token']


class Proxy(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def json(self, value, status=200):
        body = json.dumps(value).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(body)

    def forward(self, port, path=None, extra_headers=None):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        headers = {k: v for k, v in self.headers.items()
                   if k.lower() not in ('connection', 'transfer-encoding', 'content-length')}
        headers.update(extra_headers or {})
        connection = http.client.HTTPConnection('127.0.0.1', port, timeout=30)
        try:
            connection.request(self.command, path or self.path, body, headers)
            response = connection.getresponse()
            payload = response.read()
            self.send_response(response.status)
            for key, value in response.getheaders():
                if key.lower() not in ('connection', 'transfer-encoding', 'content-length'):
                    self.send_header(key, value)
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            if self.command != 'HEAD':
                self.wfile.write(payload)
        finally:
            connection.close()

    def log_message(self, *args):
        pass

def serve(handler, port, background=False, host='127.0.0.1'):
    server = ThreadingHTTPServer((host, port), handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain('/fixtures/tls/server-cert.pem', '/fixtures/tls/server-key.pem')
    server.socket = context.wrap_socket(server.socket, server_side=True)
    if background:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    else:
        server.serve_forever()
    return server
