#!/usr/bin/env python3
"""Real shell -> authored Pi package selection -> loopback HTTP, using fake keys."""
import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import shlex
import threading

from langfuse_otel_headers_test import HeaderTest, ROOT

# [itest->req~native-tracing.shell-authentication~1]
def main():
    settings = json.loads((ROOT / "home/.pi/agent/settings.json").read_text())
    selected = [p for p in settings["packages"] if "pi-opentelemetry" in p]
    assert len(selected) == 1, "expected one authored telemetry package"
    extension = Path(selected[0])
    assert extension.is_absolute() and extension.is_dir(), "selected local installation missing"
    received = []

    class Collector(BaseHTTPRequestHandler):
        def do_POST(self):
            if self.headers.get("Transfer-Encoding") == "chunked":
                chunks = []
                while True:
                    size = int(self.rfile.readline().strip(), 16)
                    if size == 0:
                        self.rfile.readline()
                        break
                    chunks.append(self.rfile.read(size))
                    self.rfile.read(2)
                payload = b"".join(chunks)
            else:
                payload = self.rfile.read(int(self.headers["Content-Length"]))
            received.append((self.path, self.headers.get("Authorization"),
                             self.headers.get("x-langfuse-ingestion-version"), json.loads(payload)))
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b"{}")

        def log_message(self, *_args):
            pass

    fixture = HeaderTest()
    fixture.setUp()
    server = ThreadingHTTPServer(("127.0.0.1", 0), Collector)
    thread = threading.Thread(target=server.serve_forever)
    thread.start()
    try:
        fixture.env.update(PI_OTEL_EXPORTER_OTLP_HEADERS="fixture-inherited",
                           OTEL_EXPORTER_OTLP_HEADERS="fixture-standard")
        command = (f"export PI_OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:{server.server_port}\n"
                   f"node {shlex.quote(str(ROOT / 'tests/fixtures/pi_otel_export.mjs'))} "
                   f"{shlex.quote(str(Path(extension).resolve()))}")
        result = fixture.shell(command)
        assert result.returncode == 0, "export process failed (output withheld)"
        assert result.stdout == "" and result.stderr == "", "unexpected exporter diagnostics"
        expected = "Basic " + base64.b64encode(b"fixture-public:fixture-private").decode()
        assert len(received) == 1, "expected one HTTP export"
        path, auth, version, body = received[0]
        assert path == "/v1/traces" and auth == expected and version == "4", "authentication mismatch"
        spans = body["resourceSpans"][0]["scopeSpans"][0]["spans"]
        assert spans[0]["name"] == "synthetic-private-file-export"
        print("PASS: shell-to-Pi-exporter HTTP authentication with synthetic credentials")
    finally:
        server.shutdown()
        thread.join()
        server.server_close()
        fixture.doCleanups()


if __name__ == "__main__":
    main()
