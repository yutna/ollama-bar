#!/usr/bin/env python3
"""Minimal fake Ollama API used by integration smoke tests.

Usage:
    fake_ollama.py <port> [healthy|impostor|big]

Modes:
    healthy   (default) answers /api/version, /api/ps, /api/tags and /api/generate
    impostor  answers 404 for every request, simulating a non-Ollama service
    big       like healthy, but /api/tags returns a payload larger than a typical
              pipe buffer (~64 KB)
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

MODE = sys.argv[2] if len(sys.argv) > 2 else "healthy"


class Handler(BaseHTTPRequestHandler):
    def _json(self, payload, status=200):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if MODE == "impostor":
            self.send_error(404)
            return
        if self.path == "/api/version":
            self._json({"version": "0.0.0-test"})
        elif self.path == "/api/ps":
            self._json({"models": [{"name": "fake:latest", "model": "fake:latest"}]})
        elif self.path == "/api/tags":
            if MODE == "big":
                models = [
                    {"name": f"fake-{i:04d}:latest", "model": f"fake-{i:04d}:latest"}
                    for i in range(3000)
                ]
                self._json({"models": models})
            else:
                self._json({"models": [{"name": "fake:latest", "model": "fake:latest"}]})
        else:
            self.send_error(404)

    def do_POST(self):
        if MODE == "impostor":
            self.send_error(404)
            return
        if self.path == "/api/generate":
            length = int(self.headers.get("Content-Length", 0))
            self.rfile.read(length)
            self._json({"response": "", "done": True})
        else:
            self.send_error(404)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
