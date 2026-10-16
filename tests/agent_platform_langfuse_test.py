#!/usr/bin/env python3
"""Static safety contracts; Docker/Lima validate the vendor schemas on host."""

import importlib.util
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
import urllib.error
import xml.etree.ElementTree as ET
from unittest.mock import patch

sys.dont_write_bytecode = True

ROOT = pathlib.Path(__file__).resolve().parents[1] / "services/agent-platform/langfuse"


class LangfuseTest(unittest.TestCase):
    # [utest->req~agent-platform.langfuse-isolation~1]
    def test_private_pinned_bounded_stack(self):
        stack = json.loads((ROOT / "compose.json").read_text())
        services = stack["services"]
        common = json.loads((ROOT / "common.json").read_text())["services"]
        self.assertEqual(
            common["container"]["logging"]["options"],
            {"max-size": "5m", "max-file": "3"},
        )
        self.assertEqual(common["langfuse"]["extends"], {"service": "container"})
        self.assertEqual(
            common["langfuse"]["environment"]["TELEMETRY_ENABLED"], "false"
        )
        self.assertEqual(
            set(services), {"web", "worker", "postgres", "clickhouse", "redis", "minio"}
        )
        self.assertEqual(services["web"]["ports"], ["127.0.0.1:3000:3000"])
        total = 0
        for name, service in services.items():
            self.assertRegex(service["image"], r"@sha256:[a-f0-9]{64}$")
            self.assertNotIn("privileged", service)
            self.assertNotIn("network_mode", service)
            if name != "web":
                self.assertNotIn("ports", service)
            total += service["mem_limit"]
            self.assertEqual(
                service["extends"],
                {
                    "file": "./common.json",
                    "service": "langfuse" if name in {"web", "worker"} else "container",
                },
            )
            self.assertNotIn("logging", service)
        self.assertLessEqual(total, 5 * 1024**3)
        self.assertEqual(services["web"]["mem_limit"], 1280 * 1024**2)
        self.assertEqual(
            services["web"]["environment"]["NODE_OPTIONS"], "--max-old-space-size=896"
        )
        self.assertNotIn("TELEMETRY_ENABLED", services["web"]["environment"])
        self.assertNotIn("environment", services["worker"])
        self.assertEqual(len(stack["volumes"]), 5)
        config = ET.parse(ROOT / "clickhouse-memory.xml").getroot()
        self.assertEqual(config.findtext("max_server_memory_usage"), "1073741824")
        # Native MergeTree defaults require 20 free entries, pool * ratio(2) >= 20.
        self.assertEqual(config.findtext("background_pool_size"), "16")
        self.assertEqual(config.findtext("logger/size"), "5M")
        self.assertEqual(config.findtext("logger/count"), "3")

    # [utest->req~agent-platform.langfuse-credentials~1]
    def test_redis_secret_is_not_expanded_into_process_arguments(self):
        redis = json.loads((ROOT / "compose.json").read_text())["services"]["redis"]
        self.assertEqual(
            redis["environment"], {"REDIS_AUTH": "${REDIS_AUTH:?required}"}
        )
        self.assertEqual(redis["command"][0:2], ["sh", "-c"])
        command = redis["command"][2]
        self.assertIn('"$$REDIS_AUTH"', command)
        self.assertNotIn("${REDIS_AUTH:?required}", command)
        self.assertIn("umask 077", command)
        self.assertIn(
            "docker-entrypoint.sh redis-server /data/redis-private.conf", command
        )

    # [utest->req~agent-platform.langfuse-query-pool~1]
    def test_query_workers_do_not_share_an_artificial_background_ceiling(self):
        config = ET.parse(ROOT / "clickhouse-memory.xml").getroot()
        self.assertIsNone(config.find("max_thread_pool_size"))
        # User profiles belong in users.d, not this server config file.
        self.assertIsNone(config.find("profiles"))
        self.assertEqual(config.findtext("max_concurrent_queries"), "8")
        self.assertEqual(config.findtext("max_server_memory_usage"), "1073741824")

    # [utest->req~agent-platform.langfuse-engine~1]
    def test_isolated_vm_boundary(self):
        vm = json.loads((ROOT / "lima.yaml").read_text())
        self.assertEqual(vm["vmType"], "vz")
        self.assertEqual(vm["memory"], "6GiB")
        self.assertEqual(vm["cpus"], 4)
        self.assertEqual(vm["mounts"], [])
        self.assertNotIn("networks", vm)
        self.assertEqual(
            vm["portForwards"],
            [
                {
                    "guestPort": 3000,
                    "hostPort": 3000,
                    "hostIP": "127.0.0.1",
                    "proto": "tcp",
                },
                {"guestPortRange": [1, 65535], "proto": "any", "ignore": True},
            ],
        )
        self.assertRegex(vm["images"][0]["digest"], r"^sha256:[a-f0-9]{64}$")
        self.assertEqual(len(vm["images"]), 1)


# [utest->req~agent-platform.synthetic-otlp~1]
class SyntheticTraceTest(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location(
            "synthetic_trace",
            ROOT.parents[2] / "scripts/agent-platform/synthetic-trace.py",
        )
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.env = pathlib.Path(self.temp.name) / ".env"
        self.env.write_text(
            "LANGFUSE_PUBLIC_KEY=public-fixture\nLANGFUSE_SECRET_KEY=private-fixture\n"
        )
        self.env.chmod(0o600)

    def test_complete_private_metadata_only_hierarchy(self):
        body = self.module.payload("public-canary", "mini")
        spans = body["resourceSpans"][0]["scopeSpans"][0]["spans"]
        self.assertEqual(len(spans), 3)
        self.assertEqual(len({span["spanId"] for span in spans}), 3)
        self.assertEqual(len({span["traceId"] for span in spans}), 1)
        self.assertNotIn("parentSpanId", spans[0])
        for span in spans:
            self.assertRegex(span["traceId"], r"^[0-9a-f]{32}$")
            self.assertRegex(span["spanId"], r"^[0-9a-f]{16}$")
            self.assertLess(
                int(span["startTimeUnixNano"]), int(span["endTimeUnixNano"])
            )
            attributes = {a["key"]: a["value"] for a in span["attributes"]}
            self.assertEqual(attributes["langfuse.trace.public"], {"boolValue": False})
            self.assertEqual(
                attributes["langfuse.trace.metadata.source"], {"stringValue": "mini"}
            )
            self.assertFalse(
                any("input" in key or "output" in key for key in attributes)
            )
        self.assertTrue(all(s["parentSpanId"] == spans[0]["spanId"] for s in spans[1:]))

    def test_private_file_and_loopback_only(self):
        for address in [
            "https://example.com",
            "http://127.0.0.1:4000",
            "http://127.0.0.1:3300@evil.invalid",
        ]:
            with self.subTest(address=address), self.assertRaises(ValueError):
                self.module.Trial(self.env, address)
        self.env.chmod(0o640)
        with self.assertRaises(ValueError):
            self.module.Trial(self.env, "http://127.0.0.1:3000")
        self.env.chmod(0o600)
        link = self.env.with_name("link")
        link.symlink_to(self.env)
        with self.assertRaises(ValueError):
            self.module.Trial(link, "http://127.0.0.1:3000")
        with (
            patch.object(self.module.os, "getuid", return_value=os.getuid() + 1),
            self.assertRaises(ValueError),
        ):
            self.module.Trial(self.env, "http://127.0.0.1:3000")

    def test_v4_transport_never_retries_post(self):
        trial = self.module.Trial(self.env, "http://127.0.0.1:3300")
        body = self.module.payload("public-canary", "laptop")
        with patch.object(
            trial, "request", return_value={"partialSuccess": {"rejectedSpans": 1}}
        ) as send:
            with self.assertRaises(RuntimeError):
                trial.send(body)
            send.assert_called_once_with("otel/v1/traces", body)
        error = urllib.error.HTTPError(
            "http://127.0.0.1:3300", 500, "fixture", {}, None
        )
        with patch.object(trial, "request", side_effect=error) as send:
            with self.assertRaises(urllib.error.HTTPError):
                trial.send(body)
            self.assertEqual(send.call_count, 1)

    def test_wire_headers_and_exact_receipt_verification(self):
        trial = self.module.Trial(self.env, "http://127.0.0.1:3300")
        body = self.module.payload("public-canary", "mini")
        with patch.object(
            trial._http, "open", return_value=io.BytesIO(b"{}")
        ) as transport:
            trial.send(body)
            request = transport.call_args.args[0]
            self.assertEqual(
                request.full_url, "http://127.0.0.1:3300/api/public/otel/v1/traces"
            )
            headers = {key.lower(): value for key, value in request.header_items()}
            self.assertEqual(headers["x-langfuse-ingestion-version"], "4")
            self.assertEqual(headers["content-type"], "application/json")
            self.assertTrue(headers["authorization"].startswith("Basic "))
            self.assertEqual(json.loads(request.data), body)
        spans = body["resourceSpans"][0]["scopeSpans"][0]["spans"]
        rows = [
            {
                "id": s["spanId"],
                "parentObservationId": s.get("parentSpanId"),
                "input": None,
                "output": None,
                "public": False,
                "metadata": {
                    "source": "mini",
                    "privacyCanary": "metadata-only-no-input-output",
                },
            }
            for s in spans
        ]
        self.module.verify(rows, spans, "mini")
        for change in (
            {"input": "content"},
            {"public": True},
            {"parentObservationId": "wrong"},
            {
                "metadata": {
                    "source": "laptop",
                    "privacyCanary": "metadata-only-no-input-output",
                }
            },
        ):
            with self.subTest(change=change), self.assertRaises(ValueError):
                self.module.verify([{**rows[0], **change}, *rows[1:]], spans, "mini")

    def test_optimized_python_still_refuses_an_invalid_receipt(self):
        code = (
            "import importlib.util,sys;"
            f"s=importlib.util.spec_from_file_location('probe',{self.module.__file__!r});"
            "m=importlib.util.module_from_spec(s);s.loader.exec_module(m);"
            "spans=m.payload('synthetic','mini')['resourceSpans'][0]['scopeSpans'][0]['spans'];"
            "m.verify([],spans,'mini')"
        )
        result = subprocess.run(
            [sys.executable, "-B", "-O", "-c", code],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("ValueError: synthetic receipt", result.stderr)

    def test_transport_response_is_bounded(self):
        trial = self.module.Trial(self.env, "http://127.0.0.1:3300")
        for size in (1_999_999, 2_000_000):
            with (
                self.subTest(size=size),
                patch.object(
                    trial._http,
                    "open",
                    return_value=io.BytesIO(b"{}" + b" " * (size - 2)),
                ),
            ):
                self.assertEqual(trial.request("v2/observations"), {})
        with (
            patch.object(
                trial._http, "open", return_value=io.BytesIO(b" " * 2_000_001)
            ),
            self.assertRaisesRegex(RuntimeError, "2 MB"),
        ):
            trial.request("v2/observations")

    def test_authentication_never_follows_a_redirect(self):
        handler = self.module.NoRedirect()
        with self.assertRaises(ValueError):
            handler.redirect_request(
                None, None, 302, "redirect", {}, "https://example.com"
            )


if __name__ == "__main__":
    unittest.main()
