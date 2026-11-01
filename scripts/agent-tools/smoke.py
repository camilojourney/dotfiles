#!/usr/bin/env python3
"""No model calls, credentials, installs, network requests or worker launches."""
import os
import subprocess


def main():
    env = dict(os.environ, PI_SKIP_VERSION_CHECK="1", PI_OFFLINE="1", PI_TELEMETRY="0")
    for command in ("pi", "quota-axi", "tasks-axi", "gh-axi"):
        for flag in ("--version", "--help"):
            result = subprocess.run([command, flag], env=env, check=True, text=True, capture_output=True, timeout=30)
            if not (result.stdout.strip() or result.stderr.strip()):
                raise RuntimeError(f"{command} {flag} returned no output")
            print(f"PASS {command} {flag}", flush=True)
    print("Worker-launch check limited to Pi CLI startup/help; no billable worker launched.")


if __name__ == "__main__":
    main()
