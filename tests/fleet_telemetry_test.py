#!/usr/bin/env python3
"""Execute each host's evaluated scheduled collector against isolated fake inputs."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FleetTelemetryTest(unittest.TestCase):
    def test_both_collectors_run_and_failures_remain_visible(self):
        for host in ("camilo", "camilo-remote"):
            arguments = json.loads(subprocess.check_output([
                "nix", "eval", "--offline", "--json",
                f"{ROOT}#darwinConfigurations.{host}.config.launchd.user.agents.fleet-skill-usage.serviceConfig.ProgramArguments",
            ], text=True, stderr=subprocess.PIPE))
            for codes in ((0, 0), (1, 0), (0, 1), (1, 1)):
                with self.subTest(host=host, exits=codes), tempfile.TemporaryDirectory() as name:
                    home = Path(name)
                    scripts = (
                        home / "github/fleet-system/system/skills/meta/skill-creator-fleet/scripts/skill_usage.py",
                        home / "github/firstmate/bin/fm-trace-evidence.py",
                    )
                    for index, script in enumerate(scripts):
                        script.parent.mkdir(parents=True)
                        script.write_text(
                            "import json,os,pathlib,sys\n"
                            f"p=pathlib.Path(os.environ['HOME'])/'called-{index}.json'\n"
                            "p.write_text(json.dumps(sys.argv[1:]))\n"
                            f"sys.exit({codes[index]})\n"
                        )
                    env = {key: value for key, value in os.environ.items() if not key.startswith("PI_OTEL_")}
                    env.update(HOME=str(home), ZDOTDIR=str(home))
                    result = subprocess.run(arguments, env=env, capture_output=True, text=True, timeout=30)
                    self.assertEqual(result.returncode, int(any(codes)), result.stderr)
                    self.assertEqual(json.loads((home / "called-0.json").read_text()), ["update"])
                    self.assertEqual(json.loads((home / "called-1.json").read_text()), ["--flush"])


if __name__ == "__main__":
    unittest.main()
