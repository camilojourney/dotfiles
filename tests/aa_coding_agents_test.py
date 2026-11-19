"""Artificial Analysis fetch and CLI parsing with an offline HTTP response."""
import importlib.util
import json
import sys
import unittest
from contextlib import redirect_stdout
from io import BytesIO, StringIO
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("aa_coding_agents", ROOT / ".agents/skills/update-models/scripts/aa-coding-agents.py")
aa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(aa)


class CodingAgentsTest(unittest.TestCase):
    def setUp(self):
        self.payload = json.dumps({
            "modelsAndReleases": {"releases": [{
                "name": "Test model", "creator": {"slug": "openai", "name": "OpenAI"},
                "releaseDate": "2026-11-01", "deprecated": False,
            }]},
            "benchmarkRows": [{
                "id": "a" * 32, "isDefault": True, "agentName": "test-agent",
                "display": {"agent": "Test agent", "model": "Modèle"},
                "indexScore": 0.75, "mean": {"costUsd": 1.5, "agentWallTimeSec": 120},
            }],
        }, ensure_ascii=False, separators=(",", ":"))
        chunks = (self.payload[:80], self.payload[80:])
        self.page = "".join(f"<script>self.__next_f.push([1,{json.dumps(chunk, ensure_ascii=False)}])</script>" for chunk in chunks).encode("utf-8")
        response = patch("urllib.request.urlopen", side_effect=lambda *args, **kwargs: BytesIO(self.page))
        response.start()
        self.addCleanup(response.stop)

    def test_http_body_is_read_and_decoded_as_text(self):
        payload = aa.fetch_payload()
        self.assertIsInstance(payload, str)
        self.assertEqual(payload, self.payload)

    def test_json_cli_outputs_fetched_rows(self):
        out = StringIO()
        with patch.object(sys, "argv", ["aa-coding-agents.py", "--json"]), redirect_stdout(out):
            aa.main()
        self.assertEqual(json.loads(out.getvalue()), [{
            "agent": "Test agent", "model": "Modèle", "index": 0.75,
            "cost_usd_per_task": 1.5, "minutes_per_task": 2.0, "unavailable": False,
        }])

    def test_releases_cli_outputs_fetched_releases(self):
        out = StringIO()
        with patch.object(sys, "argv", ["aa-coding-agents.py", "--releases"]), redirect_stdout(out):
            aa.main()
        self.assertEqual(out.getvalue(), "2026-11-01  OpenAI / Test model\n")


if __name__ == "__main__":
    unittest.main()
