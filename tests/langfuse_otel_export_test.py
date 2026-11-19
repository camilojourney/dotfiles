"""Check authored exporter entry points without agents, credentials or a backend."""
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class NoAgentExportTest(unittest.TestCase):
    # [utest->req~native-tracing.no-agent-export~1]
    def test_pi_has_no_global_telemetry_package(self):
        settings = json.loads((ROOT / "home/.pi/agent/settings.json").read_text())
        manifest = json.loads((ROOT / "nix/agent-tools.manifest.lock.json").read_text())
        self.assertNotRegex(json.dumps(settings.get("packages", [])), r"(?i)opentelemetry|langfuse")
        self.assertNotRegex(json.dumps(manifest), r"(?i)pi-opentelemetry")

    # [utest->req~native-tracing.no-agent-export~1]
    def test_claude_telemetry_is_disabled_and_helper_is_unwired(self):
        settings = json.loads((ROOT / "home/.claude/settings.json").read_text())
        env = settings.get("env", {})
        self.assertEqual(env.get("CLAUDE_CODE_ENABLE_TELEMETRY"), "0")
        self.assertNotIn("CLAUDE_CODE_ENHANCED_TELEMETRY_BETA", env)
        self.assertEqual([key for key in env if key.startswith("OTEL_")], [])
        self.assertNotIn("otelHeadersHelper", settings)

    def test_export_only_helpers_are_archived_not_active(self):
        for path in ("scripts/agent-tools/langfuse-otel-headers.sh",
                     "tests/fixtures/pi_otel_export.mjs"):
            with self.subTest(path=path):
                self.assertFalse((ROOT / path).exists())
                self.assertTrue((ROOT / "archive/agent-langfuse-export" / path).is_file())
        self.assertTrue((ROOT / "scripts/agent-tools/langfuse-up.sh").is_file())
        self.assertTrue((ROOT / "services/agent-platform/langfuse").is_dir())


if __name__ == "__main__":
    unittest.main()
