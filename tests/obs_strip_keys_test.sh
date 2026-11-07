#!/usr/bin/env bash
# Committed OBS settings never contain stream keys or login tokens, while the
# working copy OBS reads keeps them and hotkey bindings survive.
# Run: bash tests/obs_strip_keys_test.sh
set -euo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# A throwaway repo wired exactly like the dotfiles: same attributes, same filter.
repo="$TMP_ROOT/repo"
git init -q "$repo"
cp "$REPO_ROOT/.gitattributes" "$repo/"
git -C "$repo" config filter.obs-keys.clean "bash $REPO_ROOT/scripts/obs-strip-keys.sh"
git -C "$repo" config filter.obs-keys.required true
profile="$repo/home/.config/obs-studio/basic/profiles/Streaming"
mkdir -p "$profile"

aitum='{"outputs":[{"type":"stream","name":"Twitch","server":"rtmp://live.twitch.tv/app","key":"live_123_SECRET\"x","bearer_token":"TOKEN_SECRET"}],"start_all_streams_hotkey":[{"key":"OBS_KEY_F9","command":true}]}'
service='{
    "type": "rtmp_common",
    "settings": {
        "service": "YouTube - RTMPS",
        "key": "abcd-SECRET-efgh",
        "password": "PASS_SECRET"
    }
}'
basic_ini=$'[General]\nName=Streaming\n\n[YouTube]\nRefreshToken=REFRESH_SECRET\nToken=ACCESS_SECRET\n'
printf '%s' "$aitum" > "$profile/aitum.json"
printf '%s\n' "$service" > "$profile/service.json"
printf '%s' "$basic_ini" > "$profile/basic.ini"
git -C "$repo" add -A

for f in aitum.json service.json basic.ini; do
  stored=$(git -C "$repo" show ":home/.config/obs-studio/basic/profiles/Streaming/$f")
  grep -q SECRET <<<"$stored" && fail "$f committed a secret: $stored"
  grep -q SECRET "$profile/$f" || fail "$f working copy lost its secret"
done

stored_aitum=$(git -C "$repo" show ":home/.config/obs-studio/basic/profiles/Streaming/aitum.json")
expected_aitum='{"outputs":[{"type":"stream","name":"Twitch","server":"rtmp://live.twitch.tv/app","key":"","bearer_token":""}],"start_all_streams_hotkey":[{"key":"OBS_KEY_F9","command":true}]}'
[[ $stored_aitum == "$expected_aitum" ]] || fail "aitum.json stored as: $stored_aitum"
git -C "$repo" show ":home/.config/obs-studio/basic/profiles/Streaming/service.json" | grep -qF '"key": "",' \
  || fail "service.json lost its formatting"

# A key-only change in OBS stages nothing. (`git status` may still list the
# file from its size until `git add` refreshes it; git compares stat first.)
git -C "$repo" -c user.name=t -c user.email=t@t commit -qm init
printf '%s' "${aitum/live_123_SECRET/live_456_NEWSECRET}" > "$profile/aitum.json"
git -C "$repo" add -A
git -C "$repo" diff --cached --quiet || fail "rotating a key staged a change"

printf 'PASS: keys and tokens are blanked in commits, kept on disk, hotkeys untouched\n'
