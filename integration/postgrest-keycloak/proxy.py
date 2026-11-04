"""Fixture-only HTTPS termination; JWT validation remains in real PostgREST."""
import http.client
import http.server
import ssl


class Proxy(http.server.BaseHTTPRequestHandler):
    def forward(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        upstream = http.client.HTTPConnection("127.0.0.1", 13000, timeout=20)
        headers = {key: value for key, value in self.headers.items()
                   if key.lower() not in {"host", "connection", "transfer-encoding"}}
        try:
            upstream.request(self.command, self.path, body=body, headers=headers)
            response = upstream.getresponse()
            payload = response.read()
            status = response.status
            # The real database has committed before this deliberately failed response.
            if self.command == "POST" and self.path == "/rpc/record_then_fail" and 200 <= status < 300:
                status = 503
                payload = b'{"message":"fixture response failure after commit"}'
            self.send_response(status)
            for key, value in response.getheaders():
                if key.lower() not in {"connection", "transfer-encoding", "content-length"}:
                    self.send_header(key, value)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(payload)
        finally:
            upstream.close()

    do_GET = do_HEAD = do_POST = do_PATCH = do_PUT = do_DELETE = forward

    def log_message(self, *args):
        pass


server = http.server.ThreadingHTTPServer(("127.0.0.1", 18444), Proxy)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain("/fixtures/tls/server-cert.pem", "/fixtures/tls/server-key.pem")
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
