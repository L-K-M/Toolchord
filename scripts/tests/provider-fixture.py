"""Loopback-only OpenAI-compatible fixture for the signed provider app check."""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer


class Provider(BaseHTTPRequestHandler):
    def reply(self, value):
        body = json.dumps(value).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path != "/v1/models" or self.headers.get("Authorization"):
            return self.send_error(400)
        self.reply({"data": [{"id": "probe-model"}]})

    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if (self.path != "/v1/chat/completions" or payload.get("model") != "probe-model"
                or payload.get("messages") != [{"role": "user", "content": "Synthetic authoring prompt"}]):
            return self.send_error(400)
        self.reply({"choices": [{"message": {"content": "generated fixture"}}]})

    def log_message(self, *args):
        pass


server = HTTPServer(("127.0.0.1", 0), Provider)
print(server.server_port, flush=True)
server.serve_forever()
