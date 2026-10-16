#!/usr/bin/env python3
"""Send complete metadata-only OTLP spans to the fresh private trial, once."""

import argparse
import base64
import json
import os
import stat
import time
import urllib.parse
import urllib.request
import uuid
from pathlib import Path


# [impl->req~agent-platform.synthetic-otlp~1]
def payload(name, source, children=2):
    """One complete root plus optional children, with no input/output attributes."""
    trace_id = uuid.uuid4().hex
    root_id = uuid.uuid4().hex[:16]
    now = time.time_ns()
    attributes = {
        "langfuse.trace.name": name,
        "langfuse.observation.type": "span",
        "langfuse.environment": "synthetic-trial",
        "langfuse.trace.metadata.source": source,
        "langfuse.trace.metadata.privacyCanary": "metadata-only-no-input-output",
        "langfuse.trace.public": False,
    }
    spans = []
    for index in range(children + 1):
        span = {
            "traceId": trace_id,
            "spanId": root_id if index == 0 else uuid.uuid4().hex[:16],
            "name": name if index == 0 else f"synthetic-child-{index}",
            "kind": 1,
            "startTimeUnixNano": str(now + index * 1000),
            "endTimeUnixNano": str(now + 1000000 - index * 1000),
            "attributes": [
                {
                    "key": key,
                    "value": {
                        "boolValue" if isinstance(value, bool) else "stringValue": value
                    },
                }
                for key, value in attributes.items()
            ],
            "status": {"code": 1},
        }
        if index:
            span["parentSpanId"] = root_id
        spans.append(span)
    return {
        "resourceSpans": [
            {
                "resource": {
                    "attributes": [
                        {
                            "key": "service.name",
                            "value": {"stringValue": "agent-platform-synthetic"},
                        }
                    ]
                },
                "scopeSpans": [
                    {
                        "scope": {"name": "agent-platform-synthetic", "version": "1"},
                        "spans": spans,
                    }
                ],
            }
        ]
    }


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("trial authentication must not follow redirects")


class Trial:
    def __init__(self, env_path, base_url):
        if base_url not in {"http://127.0.0.1:3000", "http://127.0.0.1:3300"}:
            raise ValueError("only the private trial loopback endpoints are accepted")
        path = Path(env_path)
        info = path.lstat()
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_mode & 0o077
        ):
            raise ValueError("trial environment must be an owner-only regular file")
        values = dict(
            line.split("=", 1)
            for line in path.read_text().splitlines()
            if line and not line.startswith("#")
        )
        keys = values["LANGFUSE_PUBLIC_KEY"] + ":" + values["LANGFUSE_SECRET_KEY"]
        self._auth = "Basic " + base64.b64encode(keys.encode()).decode()
        self._base = base_url + "/api/public/"
        self._http = urllib.request.build_opener(
            urllib.request.ProxyHandler({}), NoRedirect()
        )

    def request(self, route, body=None):
        request = urllib.request.Request(
            self._base + route,
            data=None if body is None else json.dumps(body).encode(),
            headers={
                "Authorization": self._auth,
                "Content-Type": "application/json",
                "x-langfuse-ingestion-version": "4",
            },
        )
        with self._http.open(request, timeout=10) as response:
            data = response.read(2_000_001)
        if len(data) > 2_000_000:
            raise RuntimeError("trial response exceeded the 2 MB safety bound")
        return json.loads(data)

    def send(self, body):
        # Do not retry: v4 immutable observations are not an exactly-once sink.
        response = self.request("otel/v1/traces", body)
        if response.get("partialSuccess", {}).get("rejectedSpans", 0):
            raise RuntimeError("trial rejected synthetic spans")
        return response

    def observations(self, trace_id):
        query = urllib.parse.urlencode(
            {
                "traceId": trace_id,
                "limit": 1000,
                "fields": "core,basic,io,metadata,trace_context",
            }
        )
        return self.request("v2/observations?" + query)


def verify(rows, spans, source):
    expected = {span["spanId"]: span.get("parentSpanId") for span in spans}
    checks = (
        len(rows) == len(spans),
        {row["id"]: row["parentObservationId"] for row in rows} == expected,
        all(
            row.get("input") in (None, "") and row.get("output") in (None, "")
            for row in rows
        ),
        all(not row["public"] for row in rows),
        all(row["metadata"]["source"] == source for row in rows),
        all(
            row["metadata"]["privacyCanary"] == "metadata-only-no-input-output"
            for row in rows
        ),
    )
    if not all(checks):
        raise ValueError("synthetic receipt identity or privacy verification failed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("env_path")
    parser.add_argument("base_url")
    parser.add_argument("source", choices=["mini", "laptop"])
    args = parser.parse_args()
    trial = Trial(args.env_path, args.base_url)
    body = payload("synthetic-canary-" + args.source, args.source)
    spans = body["resourceSpans"][0]["scopeSpans"][0]["spans"]
    start = time.monotonic()
    trial.send(body)
    for _ in range(30):
        try:
            rows = trial.observations(spans[0]["traceId"])["data"]
        except urllib.error.HTTPError as error:
            raise RuntimeError(
                f"synthetic trace {spans[0]['traceId']} readback failed HTTP {error.code}; do not repeat POST"
            ) from None
        if len(rows) == 3:
            break
        time.sleep(1)
    else:
        raise RuntimeError("synthetic receipt not visible within 30 polls")
    verify(rows, spans, args.source)
    print(
        json.dumps(
            {
                "source": args.source,
                "traceID": spans[0]["traceId"],
                "observationIDs": sorted(row["id"] for row in rows),
                "observations": len(rows),
                "metadataOnly": True,
                "private": True,
                "readbackSeconds": time.monotonic() - start,
            }
        )
    )


if __name__ == "__main__":
    main()
