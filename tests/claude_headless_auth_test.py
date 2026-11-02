#!/usr/bin/env python3
"""Exercise evaluated host zsh environments with synthetic headless tokens only."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

from langfuse_otel_headers_test import ROOT, evaluated_zsh_environment


class ClaudeHeadlessAuthTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.blocks = {}
        for host, user in (("camilo", "camiloslaptop"), ("camilo-remote", "camilo_mini")):
            cls.blocks[host] = evaluated_zsh_environment(host, user)

    def shell(self, host, flags, present, inherited=None):
        with tempfile.TemporaryDirectory(prefix="claude-headless-fixture-") as name:
            home = Path(name)
            secrets = home / ".config/secrets"
            secrets.mkdir(parents=True, mode=0o700)
            (secrets / "langfuse.env").write_text(
                "LANGFUSE_INIT_PROJECT_PUBLIC_KEY=fixture-public\n"
                "LANGFUSE_INIT_PROJECT_SECRET_KEY=fixture-private\n")
            token_file = secrets / "claude-code-oauth.env"
            if present:
                token_file.write_text("export CLAUDE_CODE_OAUTH_TOKEN=fixture-headless-token\n")
                token_file.chmod(0o600)
            (home / ".zshenv").write_text(self.blocks[host])
            env = {"PATH": os.environ["PATH"], "HOME": name, "ZDOTDIR": name,
                   "LANGFUSE_SECRETS": str(secrets / "langfuse.env")}
            if inherited is not None:
                env["CLAUDE_CODE_OAUTH_TOKEN"] = inherited
            child = (
                "import json,os; "
                "print(json.dumps({'token':os.environ.get('CLAUDE_CODE_OAUTH_TOKEN')}))"
            )
            result = subprocess.run(["zsh", "-d", flags, "python3 -c " + shlex.quote(child)],
                                    env=env, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
            self.assertEqual(token_file.exists(), present)
            if present:
                self.assertEqual(token_file.stat().st_mode & 0o777, 0o600)
            return json.loads(result.stdout)["token"]

    def test_mini_loads_token_for_ssh_and_interactive_children(self):
        for flags in ("-c", "-lc", "-ic", "-lic"):
            with self.subTest(flags=flags):
                self.assertEqual(self.shell("camilo-remote", flags, True), "fixture-headless-token")

    def test_missing_file_creates_no_token_and_preserves_explicit_environment(self):
        self.assertIsNone(self.shell("camilo-remote", "-lc", False))
        self.assertEqual(self.shell("camilo-remote", "-c", False, "fixture-inherited"),
                         "fixture-inherited")

    def test_laptop_does_not_load_mini_private_file(self):
        self.assertIsNone(self.shell("camilo", "-lic", True))

    def test_documented_save_command_is_private_quiet_and_shell_safe(self):
        line = next(line for line in (ROOT / "docs/AUTOMATIONS.md").read_text().splitlines()
                    if line.startswith("ssh -t mac-mini 'umask"))
        argv = shlex.split(line)
        self.assertEqual(argv[:3], ["ssh", "-t", "mac-mini"])
        self.assertEqual(len(argv), 4)
        for existing in (False, True):
            with self.subTest(existing=existing), tempfile.TemporaryDirectory() as name:
                home = Path(name)
                destination = home / ".config/secrets/claude-code-oauth.env"
                if existing:
                    destination.parent.mkdir(parents=True)
                    destination.write_text("fixture-old")
                    destination.chmod(0o644)
                env = {"PATH": os.environ["PATH"], "HOME": name, "ZDOTDIR": name}
                token = "fixture-'$`\\\\token"
                saved = subprocess.run(["zsh", "-d", "-c", argv[3]], input=token + "\n",
                                       env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(saved.returncode, 0, saved.stderr)
                self.assertEqual(saved.stdout, "")
                self.assertEqual(saved.stderr, "")
                self.assertEqual(destination.stat().st_mode & 0o777, 0o600)
                self.assertEqual(len(destination.read_text().splitlines()), 1)
                checked = subprocess.run([
                    "zsh", "-d", "-c",
                    '. "$HOME/.config/secrets/claude-code-oauth.env"; '
                    'test "$CLAUDE_CODE_OAUTH_TOKEN" = "$1"', "fixture", token,
                ], env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(checked.returncode, 0, checked.stderr)
                self.assertEqual(checked.stdout, "")
                self.assertEqual(checked.stderr, "")


if __name__ == "__main__":
    unittest.main()
