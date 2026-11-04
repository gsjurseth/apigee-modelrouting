#!/usr/bin/env python3
import http.server
import socketserver
import urllib.request
import urllib.error
import json
import os

PORT = int(os.environ.get("PORT", "8080"))
DIRECTORY = os.path.dirname(os.path.abspath(__file__))
GATEWAY_URL = os.environ.get(
    "GATEWAY_URL",
    "https://api.endpoints.apigee-product-demo.cloud.goog/v1/chat/simple-stage5",
)

class CustomHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.end_headers()

    def do_POST(self):
        if self.path == "/api/proxy":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            client_id = self.headers.get("x-demo-client-id", "demo-default")

            req = urllib.request.Request(
                GATEWAY_URL,
                data=body,
                headers={
                    "Content-Type": "application/json",
                    "x-demo-client-id": client_id
                },
                method="POST"
            )

            try:
                with urllib.request.urlopen(req) as resp:
                    resp_data = resp.read()
                    status = resp.status
                    headers = dict(resp.getheaders())
            except urllib.error.HTTPError as e:
                resp_data = e.read()
                status = e.code
                headers = dict(e.headers)
            except Exception as e:
                resp_data = json.dumps({"error": str(e)}).encode("utf-8")
                status = 502
                headers = {"Content-Type": "application/json"}

            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            for k, v in headers.items():
                if k.lower().startswith("x-") or k.lower() in ["retry-after"]:
                    self.send_header(k, v)
            self.end_headers()
            self.wfile.write(resp_data)
        else:
            self.send_error(404, "Not Found")

if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), CustomHandler) as httpd:
        print(f"Serving on port {PORT} with /api/proxy endpoint...")
        httpd.serve_forever()
