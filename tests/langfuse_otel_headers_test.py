"""Managed shells must not provision agent-export credentials."""
import json
import os
import shlex
import subprocess
import tempfile
import unittest
from functools import cache
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOSTS = (("camilo", "camiloslaptop"), ("camilo-remote", "camilo_mini"))


@cache
def evaluated_zsh_environment(host, user):
    """Relocate the real evaluated environment into an isolated test checkout."""
    return subprocess.check_output([
        "nix", "eval", "--offline", "--raw",
        f"{ROOT}#darwinConfigurations.{host}.config.home-manager.users.{user}.programs.zsh.envExtra",
    ], text=True, stderr=subprocess.PIPE, timeout=60).replace(
        f"/Users/{user}/github/dotfiles", str(ROOT))


class NoAgentHeadersTest(unittest.TestCase):
    # [utest->req~native-tracing.shell-isolation~1]
    def test_fresh_shells_do_not_provision_agent_export_environment_or_files(self):
        for host, user in HOSTS:
            block = evaluated_zsh_environment(host, user)
            for flags in ("-c", "-lc", "-ic", "-lic"):
                with self.subTest(host=host, flags=flags), tempfile.TemporaryDirectory() as name:
                    home = Path(name)
                    secrets = home / ".config/secrets"
                    secrets.mkdir(parents=True)
                    for destination in (secrets / "langfuse.env", home / "stack/project/.env"):
                        destination.parent.mkdir(parents=True, exist_ok=True)
                        destination.write_text(
                            "LANGFUSE_PUBLIC_KEY=fixture-public\n"
                            "LANGFUSE_SECRET_KEY=fixture-private\n")
                    isolated = block.replace(
                        "/Volumes/AgentPlatform/agent-platform/langfuse/project/.env",
                        str(home / "stack/project/.env"))
                    (home / ".zshenv").write_text(isolated)
                    before = sorted(str(p.relative_to(home)) for p in home.rglob("*"))
                    child = (
                        "import json,os; print(json.dumps(sorted(k for k in os.environ "
                        "if k.startswith(('PI_OTEL_', 'OTEL_')) or k == 'LANGFUSE_SECRETS')))"
                    )
                    result = subprocess.run(
                        ["zsh", "-d", flags, "python3 -c " + shlex.quote(child)],
                        check=False, env={"PATH": os.environ["PATH"], "HOME": name, "ZDOTDIR": name},
                        capture_output=True, text=True, timeout=30)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stderr, "")
                    self.assertEqual(json.loads(result.stdout), [])
                    self.assertEqual(
                        sorted(str(p.relative_to(home)) for p in home.rglob("*")), before)

    # [utest->req~native-tracing.shell-isolation~1]
    def test_no_prompt_time_agent_trace_tagging(self):
        for host, user in HOSTS:
            with self.subTest(host=host):
                init = subprocess.check_output([
                    "nix", "eval", "--offline", "--raw",
                    f"{ROOT}#darwinConfigurations.{host}.config.home-manager.users.{user}.programs.zsh.initContent",
                ], text=True, stderr=subprocess.PIPE, timeout=60)
                self.assertNotIn("_fleet_trace_tag", init)
                self.assertNotIn("OTEL_RESOURCE_ATTRIBUTES", init)

    def test_explicit_native_langfuse_environment_is_not_removed(self):
        for host, user in HOSTS:
            with self.subTest(host=host), tempfile.TemporaryDirectory() as name:
                native = {"LANGFUSE_PUBLIC_KEY": "fixture-public",
                          "LANGFUSE_SECRET_KEY": "fixture-private",
                          "LANGFUSE_SECRETS": str(Path(name) / "explicit.env")}
                child = "import os; " + "; ".join(
                    f"assert os.environ.get({key!r}) == {value!r}" for key, value in native.items())
                result = subprocess.run(
                    ["zsh", "-d", "-c", evaluated_zsh_environment(host, user) +
                     "\npython3 -c " + shlex.quote(child)],
                    check=False, env={"PATH": os.environ["PATH"], "HOME": name, "ZDOTDIR": name, **native},
                    capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
