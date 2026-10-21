#!/usr/bin/env python3
"""Fake captive portal / connectivity endpoints for testing wifimenu probe.
Paths:
  /gen204      -> 204 (real internet)
  /success.txt -> 200 "success\n" (real internet, Mozilla style)
  /redir       -> 302 Location: http://portal.test/login?token=abc
  /html        -> 200 HTML with a meta refresh to http://portal.test/meta
  /js          -> 200 HTML with window.location = "http://portal.test/js"
  /blank       -> 200 HTML with no hint at all
  /511         -> 511 Network Authentication Required with a link
  /hang        -> never answers
"""
import sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, code, body=b"", headers=()):
        self.send_response(code)
        for k, v in headers: self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        p = self.path
        if p == "/gen204": self._send(204)
        elif p == "/success.txt": self._send(200, b"success\n")
        elif p == "/redir": self._send(302, b"", [("Location", "http://portal.test/login?token=abc")])
        elif p == "/html": self._send(200, b"<html><head>\n<meta http-equiv=\"refresh\" content=\"0; url=http://portal.test/meta\">\n</head><body>hi</body></html>\n")
        elif p == "/js": self._send(200, b"<html><script>\nwindow.location.href = 'http://portal.test/js';\n</script></html>")
        elif p == "/blank": self._send(200, b"<html><body>Welcome to the lobby</body></html>")
        elif p == "/511": self._send(511, b"<html><body><a href=\"http://portal.test/511\">Log in</a></body></html>")
        elif p == "/hang": time.sleep(30); self._send(204)
        else: self._send(404)

ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
