#!/usr/bin/env python3
"""Mini-only Sunday pin promotion. Never switches Nix or calls an agent.

The daily daemon runs recovery before pulling, and --scheduled after its rebuild.
Only a clean, current main may propose a pin-only commit. A durable journal keeps
interrupted installs from reaching an ordinary rebuild before recovery.
"""
import argparse
import fcntl
import hashlib
import json
import os
import signal
import subprocess
from contextlib import contextmanager, suppress
from datetime import datetime
from pathlib import Path

from toolchain import ROOT, Registry, atomic_json, select, validate

PIN = "nix/agent-tools.manifest.lock.json"


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], check=True, text=True, capture_output=True, timeout=120).stdout.rstrip("\n")


def notify(message):
    print(message, flush=True)
    subprocess.run(["/usr/bin/osascript", "-e", 'display notification "' + message.replace('"', '') + '" with title "Agent tool pins"'], check=False, timeout=15)


@contextmanager
def locked(state):
    state.mkdir(parents=True, exist_ok=True)
    with (state / "weekly.lock").open("w") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def clean_main(repo):
    if git(repo, "branch", "--show-current") != "main" or git(repo, "status", "--porcelain"):
        raise RuntimeError("weekly pins require a clean main; checkout left untouched")


def run_install(command, env, timeout):
    # Package managers spawn children. On timeout/termination stop the entire
    # group before rollback so a late npm/pip write cannot race restoration.
    with subprocess.Popen(command, env=env, start_new_session=True) as process:
        try:
            rc = process.wait(timeout=timeout)
        finally:
            # Waiting for the parent alone does not prove its children exited.
            # Kill any survivors, including TERM-ignoring grandchildren, before
            # returning to the transaction's rollback handler.
            with suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        if rc:
            raise subprocess.CalledProcessError(rc, command)


def install(repo):
    env = dict(os.environ, AGENT_TOOLS_MANIFEST=str(repo / PIN), AGENT_TOOLS_REPO_ROOT=str(repo), AGENT_TOOLS_STRICT="1", PI_SKIP_VERSION_CHECK="1")
    run_install([str(repo / "scripts/agent-tools/reconcile.sh")], env, 1800)
    run_install([str(repo / "scripts/agent-tools/smoke.py")], env, 180)


def _owned_candidate(repo, head, record):
    committed = git(repo, "show", f"{head}:{PIN}") + "\n"
    return (git(repo, "rev-parse", "HEAD^") == record["base"]
            and git(repo, "diff", "--name-only", record["base"], head) == PIN
            and hashlib.sha256(committed.encode()).hexdigest() == record["digest"])


def _check_recovery(repo, record):
    head = git(repo, "rev-parse", "HEAD")
    if git(repo, "branch", "--show-current") != "main":
        raise RuntimeError("interrupted bump needs main checked out; no files changed")
    # Never restore anyone else's edits or commits. Only this transaction's one
    # pin file and its one commit may be removed; no reset --hard or force push.
    dirty = git(repo, "status", "--porcelain")
    if dirty and any(line[3:] != PIN for line in dirty.splitlines()):
        raise RuntimeError("interrupted bump has unrelated edits; manual recovery required")
    digest = hashlib.sha256((repo / PIN).read_bytes()).hexdigest()
    if digest not in (record["digest"], record["previousDigest"]):
        raise RuntimeError("pin file edited during bump; manual recovery required")
    if head != record["base"] and not _owned_candidate(repo, head, record):
        raise RuntimeError("HEAD advanced during bump; manual recovery required")
    return head


def recover(repo, state):
    journal = state / "transaction.json"
    if not journal.exists():
        return
    record = json.loads(journal.read_text())
    head = _check_recovery(repo, record)
    git(repo, "restore", f"--source={record['base']}", "--staged", "--worktree", "--", PIN)
    if head != record["base"]:
        git(repo, "update-ref", "-m", "rollback failed tool pins", "refs/heads/main", record["base"], head)
    install(repo)
    journal.unlink()
    notify("Restored previous agent pins and installs after failed or interrupted bump")


def install_candidate(repo, state, selected, publish):
    clean_main(repo)
    validate(selected)
    journal = state / "transaction.json"
    state.mkdir(parents=True, exist_ok=True)
    if journal.exists():
        raise RuntimeError("recover previous transaction before installing")
    base = git(repo, "rev-parse", "HEAD")
    # Canonical bytes are hashed before writing so recovery can distinguish our
    # partial write/commit from concurrent user changes after any interruption.
    data = json.dumps(selected, indent=2) + "\n"
    atomic_json(journal, {"base": base, "digest": hashlib.sha256(data.encode()).hexdigest(), "previousDigest": hashlib.sha256((repo / PIN).read_bytes()).hexdigest(), "passed": False})
    try:
        atomic_json(repo / PIN, selected)
        git(repo, "add", "--", PIN)
        git(repo, "-c", "core.hooksPath=/dev/null", "commit", "--only", "-m", "chore: promote age-gated agent tool pins", "--", PIN)
        head = git(repo, "rev-parse", "HEAD")
        install(repo)
        clean_main(repo)
        if git(repo, "rev-parse", "HEAD") != head:
            raise RuntimeError("HEAD changed during install; refusing to publish unrelated commits")
        record = json.loads(journal.read_text())
        record["passed"] = True
        atomic_json(journal, record)
        publish(head)
        journal.unlink()
    except (Exception, KeyboardInterrupt):
        recover(repo, state)
        raise


def preflight(repo):
    clean_main(repo)
    allowed = ("https://github.com/camilojourney/dotfiles.git", "git@github.com:camilojourney/dotfiles.git")
    if any(git(repo, "remote", "get-url", *flags, "origin") not in allowed for flags in ([], ["--push"])):
        raise RuntimeError("origin fetch and push URLs must be camilojourney/dotfiles")
    if git(repo, "rev-parse", "HEAD") != git(repo, "rev-parse", "refs/remotes/origin/main"):
        raise RuntimeError("main must match the daily pull's origin/main before weekly bump")
    # A real receive-pack authorization check, with no ref writes, before any
    # candidate commit or install. No token is created, copied or logged.
    git(repo, "-c", "core.hooksPath=/dev/null", "push", "--dry-run", "origin", "HEAD:refs/heads/main")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--recover", action="store_true")
    parser.add_argument("--scheduled", action="store_true")
    parser.add_argument("--repo", type=Path, default=ROOT)
    args = parser.parse_args()
    state = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "agent-tools"
    os.environ["GIT_TERMINAL_PROMPT"] = "0"
    os.environ["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=10"
    os.environ["PATH"] = f"/run/current-system/sw/bin:/opt/homebrew/bin:{Path.home()}/.local/bin:{Path.home()}/.no-mistakes/bin:" + os.environ.get("PATH", "")
    def interrupted(signum, frame):
        raise KeyboardInterrupt(f"signal {signum}")
    signal.signal(signal.SIGTERM, interrupted)
    try:
        with locked(state):
            recover(args.repo, state)
            if args.recover:
                return
            if not args.scheduled or datetime.now().weekday() != 6:
                return
            preflight(args.repo)
            manifest = json.loads((args.repo / PIN).read_text())
            selected, decisions = select(manifest, datetime.now().astimezone(), Registry())
            print("\n".join(decisions), flush=True)
            if selected == manifest:
                print("weekly pins: no eligible changes")
                return
            def publish(head):
                git(args.repo, "-c", "core.hooksPath=/dev/null", "push", "origin", f"{head}:refs/heads/main")
            install_candidate(args.repo, state, selected, publish)
    except (Exception, KeyboardInterrupt):
        notify("Agent pin update failed; previous pins retained or recovery required. See /var/log/auto-rebuild.log")
        raise


if __name__ == "__main__":
    main()
