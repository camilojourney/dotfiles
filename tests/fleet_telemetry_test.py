"""Offline evaluation proves retirement without unloading jobs or activating Nix."""
import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class FleetTelemetryTest(unittest.TestCase):
    # [utest->req~native-tracing.on-demand-usage~1]
    def test_no_scheduled_skill_usage_or_outcome_export_on_any_target(self):
        for host in ("camilo", "camilo-remote", "camilo-total", "camilo-remote-total"):
            with self.subTest(host=host):
                labels = json.loads(subprocess.check_output([
                    "nix", "eval", "--offline", "--json",
                    f"{ROOT}#darwinConfigurations.{host}.config.launchd.user.agents",
                    "--apply", 'agents: builtins.mapAttrs (_: agent: agent.serviceConfig.Label or "") agents',
                ], text=True, stderr=subprocess.PIPE, timeout=60))
                self.assertNotIn("fleet-skill-usage", labels)
                self.assertNotIn("org.dotfiles.fleet-skill-usage", labels.values())

    def test_rebuild_keeps_fleet_skill_installer_on_both_hosts(self):
        for host, user in (("camilo", "camiloslaptop"), ("camilo-remote", "camilo_mini")):
            with self.subTest(host=host):
                activation = json.loads(subprocess.check_output([
                    "nix", "eval", "--offline", "--json",
                    f"{ROOT}#darwinConfigurations.{host}.config.home-manager.users.{user}.home.activation.linkSkills",
                ], text=True, stderr=subprocess.PIPE, timeout=60))
                self.assertIn("linkGeneration", activation["after"])
                self.assertIn(
                    f"/Users/{user}/github/fleet-system/system/skills/link-skills.sh",
                    activation["data"],
                )
                self.assertIn('if [ -f "$linkSkills" ]', activation["data"])
                self.assertIn('/bin/bash "$linkSkills"', activation["data"])


if __name__ == "__main__":
    unittest.main()
