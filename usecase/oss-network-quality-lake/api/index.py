"""Vercel function: the demo's read-only endpoints, against the lake on ClickHouse Cloud.

GET /api/layers, /api/q/<1-4>, /api/map, /api/usecases — the same fixed queries as
ui/server.py, run as the read-only user. No writes: on Cloud the data feeds itself
(cloud/feed.sql), so there is no /api/tick here. Env: CH_URL, CH_READ_USER, CH_READ_PASSWORD.
Responses are cached at the edge for 20 s, so many viewers cost one query per 20 s. The cache
key is the full URL, so only the exact paths are served: a query string is refused (400) and a
trailing slash is redirected (308) without touching ClickHouse. Errors return a fixed body; the
detail goes to the function log. The read-only user also has an hourly quota (cloud/load.py).
"""
import json, os, pathlib, sys, urllib.parse
from http.server import BaseHTTPRequestHandler

os.environ.setdefault("FEED", "auto")
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "ui"))
import server  # noqa: E402


class handler(BaseHTTPRequestHandler):
    def reply(self, code, body):
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "public, s-maxage=20, stale-while-revalidate=40" if code == 200 else "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        if url.query:
            return self.reply(400, {"error": "no query parameters"})
        if url.path != "/" and url.path.endswith("/"):
            self.send_response(308)
            self.send_header("Location", url.path.rstrip("/"))
            self.send_header("Cache-Control", "public, s-maxage=86400")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        path = url.path
        routes = {"/api/layers": lambda: {**server.counts(), "story": server.story()},
                  "/api/map": server.map_data, "/api/usecases": server.usecases}
        for n in ("1", "2", "3", "4"):
            routes["/api/q/" + n] = (lambda n=int(n): server.noc(n))
        fn = routes.get(path)
        if fn is None:
            return self.reply(404, {"error": "not found"})
        try:
            self.reply(200, fn())
        except Exception as e:  # ClickHouse unreachable or quota spent: the page falls back to its recording
            print("ClickHouse error on %s: %s" % (path, e), file=sys.stderr)
            self.reply(503, {"error": "unavailable"})

    def do_POST(self):
        self.reply(405, {"error": "read-only"})
