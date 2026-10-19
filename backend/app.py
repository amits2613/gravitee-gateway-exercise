"""Minimal backend. GET /ping returns "pong"; GET /healthz is for probes."""
import os
import signal
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "8080"))
ROUTES = {"/ping": b"pong", "/healthz": b"ok"}


class Handler(BaseHTTPRequestHandler):
    def version_string(self):
        return "pong"

    def do_GET(self):
        body = ROUTES.get(self.path.split("?", 1)[0])
        if body is None:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        # Keep probe traffic out of the logs.
        if not self.path.startswith("/healthz"):
            super().log_message(fmt, *args)


def main():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.daemon_threads = True

    # As PID 1 in a container, Python ignores SIGTERM unless a handler is set,
    # which delays every pod shutdown by the full grace period.
    def stop(signum, frame):
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    server.serve_forever()
    server.server_close()


if __name__ == "__main__":
    main()
