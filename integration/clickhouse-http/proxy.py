"""Local HTTP compatibility fixture. Synthetic bearer mapping is not Cloud JWT."""
import http.client
import http.server
import socket
import ssl
import time
import urllib.parse


class Proxy(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Length", "0")
            self.end_headers()
        else:
            self.send_error(404)

    def do_POST(self):
        user = {"Bearer fixture-alice": "alice", "Bearer fixture-bob": "bob"}.get(self.headers.get("Authorization"))
        if user is None:
            self.send_error(401)
            return
        address = urllib.parse.urlsplit(self.path)
        payload = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        upstream = http.client.HTTPConnection("engine", 8123, timeout=20)
        try:
            upstream.request("POST", "/?" + address.query, body=payload,
                             headers={"X-ClickHouse-User": user, "Content-Type": "text/plain; charset=utf-8"})
            response = upstream.getresponse()
            body = response.read()
            if response.status == 200 and address.path.startswith("/drop"):
                self.close_connection = True
                self.connection.shutdown(socket.SHUT_RDWR)
                return
            if response.status == 200 and address.path.startswith("/delay"):
                time.sleep(5)
            self.send_response(response.status)
            for name, value in response.getheaders():
                if name.lower() not in {"connection", "transfer-encoding", "content-length"}:
                    self.send_header(name, value)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass
        finally:
            upstream.close()

    def log_message(self, *args):
        pass


server = http.server.ThreadingHTTPServer(("0.0.0.0", 18444), Proxy)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain("/fixtures/tls/server-cert.pem", "/fixtures/tls/server-key.pem")
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
