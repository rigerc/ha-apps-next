"""Serve a minimal authenticated Home Assistant MySQL service response."""

import json
import os
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        if self.path != "/services/mysql":
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        expected = f"Bearer {os.environ['SUPERVISOR_TOKEN']}"
        if self.headers.get("Authorization") != expected:
            self.send_error(HTTPStatus.UNAUTHORIZED)
            return

        body = json.dumps(
            {
                "data": {
                    "host": os.environ["MYSQL_HOST"],
                    "port": int(os.environ.get("MYSQL_PORT", "3306")),
                    "username": os.environ["MYSQL_USER"],
                    "password": os.environ["MYSQL_PASSWORD"],
                }
            }
        ).encode()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        return


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
