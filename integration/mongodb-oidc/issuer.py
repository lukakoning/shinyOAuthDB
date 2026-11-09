"""Disposable HTTPS discovery/JWKS endpoint; never issues browser credentials."""

import http.server
import json
import pathlib
import ssl

root = pathlib.Path("/fixture")


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        name = {"/.well-known/openid-configuration": "discovery.json", "/jwks": "jwks.json"}.get(self.path)
        if name is None:
            self.send_error(404)
            return
        data = (root / name).read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


server = http.server.ThreadingHTTPServer(("0.0.0.0", 8443), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(root / "server.pem")
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
