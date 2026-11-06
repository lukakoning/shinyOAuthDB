"""Terminate local HTTPS; PostgREST validates the JWT and PostgreSQL applies RLS."""
import http.client
import ssl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class Proxy(BaseHTTPRequestHandler):
    def do_GET(self):
        upstream = http.client.HTTPConnection('localhost', 13000, timeout=20)
        try:
            headers = {k: v for k, v in self.headers.items() if k.lower() not in ('host', 'connection')}
            upstream.request('GET', self.path, headers=headers)
            response = upstream.getresponse()
            payload = response.read()
            self.send_response(response.status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        finally:
            upstream.close()

server = ThreadingHTTPServer(('127.0.0.1', 18444), Proxy)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain('/fixtures/tls/server-cert.pem', '/fixtures/tls/server-key.pem')
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
