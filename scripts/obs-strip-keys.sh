#!/usr/bin/env bash
# Git clean filter for OBS files (.gitattributes, filter=obs-keys): commits the
# configuration with stream keys and login tokens blanked, while the working
# copy OBS reads keeps them. Text substitution keeps OBS's own formatting.
# Hotkey bindings also use "key" but always hold OBS_KEY_* names; keep those.
set -euo pipefail

exec perl -pe '
  s/"(key|stream_key|bearer_token|password)"(\s*:\s*)"(?!OBS_KEY_)(?:[^"\\]|\\.)*"/"$1"$2""/g;
  s/^(\w*Token)=.*$/$1=/;
'
