#!/bin/bash
#
# Regression test for scripts/check-upstream-configs.sh.
#
# Runs the checker against a hermetic upstream fixture whose moving branch is
# distinct from the resolved commit. The fake git remote accepts only a fetch
# and archive of that resolved commit, then the test validates the resulting
# mirror and metadata contracts.
#
# Run: bash tests/check_upstream_configs_test.sh

set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
REAL_PYTHON=$(command -v python3)
EXPECTED_COMMIT=1111111111111111111111111111111111111111
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/check-upstream-configs.XXXXXX")
FIXTURE="$ROOT/fixture"
UPSTREAM_SOURCE="$ROOT/upstream"
STUB_BIN="$ROOT/bin"

cleanup() {
  rm -rf "$ROOT"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

mkdir -p "$FIXTURE/scripts" "$FIXTURE/upstream/kunchenguid/snapshot" \
  "$FIXTURE/files/.config/wezterm" "$UPSTREAM_SOURCE/home/.config/wezterm" "$STUB_BIN"
cp "$REPO_ROOT/scripts/check-upstream-configs.sh" "$FIXTURE/scripts/"
printf 'resolved upstream config\n' >"$UPSTREAM_SOURCE/home/.config/wezterm/wezterm.lua"
printf 'local config\n' >"$FIXTURE/files/.config/wezterm/wezterm.lua"

"$REAL_PYTHON" - "$FIXTURE/upstream/kunchenguid/decisions.json" <<'PY'
import json, pathlib, sys

path = pathlib.Path(sys.argv[1])
path.write_text(json.dumps({
    "upstream": {
        "repo": "https://github.com/test/repo",
        "ref": "main",
        "mirror_commit": "old-mirror",
        "last_checked_commit": "old-snapshot",
        "last_checked_at": "2020-01-01",
    },
    "files": {
        "wezterm/wezterm.lua": {
            "policy": "track",
            "adopted_upstream_sha256": "not-used",
            "our_additions": [],
        },
    },
}, indent=2) + "\n")
PY

cat >"$STUB_BIN/git" <<'EOF'
#!/bin/bash
set -euo pipefail

expected=${EXPECTED_COMMIT:?}
source=${UPSTREAM_SOURCE:?}

if [ "$1" = "init" ]; then
  mkdir -p "${@: -1}/.git"
  exit 0
fi

if [ "$1" = "-C" ]; then
  shift 2
fi

case "$1" in
  remote)
    exit 0
    ;;
  fetch)
    [ "${@: -1}" = "$expected" ] || exit 2
    exit 0
    ;;
  rev-parse)
    [ "$2" = "FETCH_HEAD" ] || exit 2
    printf '%s\n' "$expected"
    ;;
  archive)
    [ "${@: -1}" = "$expected" ] || exit 2
    tar -C "$source" -cf - .
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "$STUB_BIN/git"

cat >"$STUB_BIN/curl" <<'EOF'
#!/bin/bash
set -euo pipefail

expected=${EXPECTED_COMMIT:?}
source=${UPSTREAM_SOURCE:?}
url=""
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    http*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "$url" == *"/commits/"* ]]; then
  printf '{"sha":"%s"}\n' "$expected"
  exit 0
fi

rel=${url#*/home/.config/}
mkdir -p "$(dirname "$out")"
cp "$source/home/.config/$rel" "$out"
EOF
chmod +x "$STUB_BIN/curl"

PATH="$STUB_BIN:/usr/bin:/bin" \
EXPECTED_COMMIT="$EXPECTED_COMMIT" \
UPSTREAM_SOURCE="$UPSTREAM_SOURCE" \
bash "$FIXTURE/scripts/check-upstream-configs.sh" >/dev/null

actual_mirror=$(tr -d '\n' <"$FIXTURE/upstream/kunchenguid/repository.commit")
[ "$actual_mirror" = "$EXPECTED_COMMIT" ] || fail "mirror commit did not use the resolved commit"
[ "$(tr -d '\n' <"$FIXTURE/upstream/kunchenguid/repository/home/.config/wezterm/wezterm.lua")" = "resolved upstream config" ] \
  || fail "mirror contents did not come from the resolved commit"

"$REAL_PYTHON" - "$FIXTURE/upstream/kunchenguid/decisions.json" "$EXPECTED_COMMIT" <<'PY'
import json, pathlib, sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text())
expected = sys.argv[2]
upstream = data["upstream"]
assert upstream["mirror_commit"] == expected
assert upstream["last_checked_commit"] == expected
PY

echo "PASS: checker mirrors and records the resolved upstream commit"
