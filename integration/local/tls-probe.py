"""Count HTTP requests after TLS handshakes without recording credentials."""
import http.server
import json
import ssl
import threading

counts = {"untrusted_ca": 0, "wrong_hostname": 0}
lock = threading.Lock()


class Probe(http.server.BaseHTTPRequestHandler):
    def respond(self):
        with lock:
            if self.server.label in counts:
                counts[self.server.label] += 1
            payload = json.dumps(counts).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_GET = do_POST = do_HEAD = respond

    def log_message(self, *args):
        pass


servers = []
for label, port, cert, key in (
    ("untrusted_ca", 18445, "untrusted-server.pem", "server-key.pem"),
    ("wrong_hostname", 18446, "wrong-hostname-cert.pem", "wrong-hostname-key.pem"),
    ("control", 18447, "server-cert.pem", "server-key.pem"),
):
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), Probe)
    server.label = label
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(f"/fixtures/tls/{cert}", f"/fixtures/tls/{key}")
    server.socket = context.wrap_socket(server.socket, server_side=True)
    servers.append(server)
for server in servers[:-1]:
    threading.Thread(target=server.serve_forever, daemon=True).start()
servers[-1].serve_forever()
