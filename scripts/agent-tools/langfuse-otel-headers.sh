#!/usr/bin/env bash
# Read local Langfuse keys, never source them as shell code.
# --file prints only a private header file's path, not its contents.
#   (no flag)  JSON for Claude Code's otelHeadersHelper
#   --env      k=v pairs for OTEL_EXPORTER_OTLP_HEADERS (percent-encoded)
#   --file     atomically refresh owner-only headers beside the secrets file
set +x
set -euo pipefail

secrets="${LANGFUSE_SECRETS:-$HOME/.config/secrets/langfuse.env}"
if [ ! -r "$secrets" ]; then
  if [ "${1:-}" = --file ]; then exit 1; fi
  [ "${1:-}" = --env ] || echo '{}'
  exit 0
fi

pk=$(sed -n 's/^LANGFUSE_INIT_PROJECT_PUBLIC_KEY=//p' "$secrets")
sk=$(sed -n 's/^LANGFUSE_INIT_PROJECT_SECRET_KEY=//p' "$secrets")
# [impl->req~native-tracing.private-header-file~1]
if [ "${1:-}" = --file ]; then
  # Never publish an empty or incomplete credential after a partial rotation.
  [ -n "$pk" ] && [ -n "$sk" ] || exit 1
  umask 077
  dir="${secrets%/*}/pi-otel"
  mkdir -p "$dir"
  [ -d "$dir" ] && [ ! -L "$dir" ] && [ -O "$dir" ] || exit 1
  chmod 700 "$dir"
  headers="$dir/headers"
  [ ! -L "$headers" ] && [ ! -d "$headers" ] || exit 1
  tmp=$(mktemp "$dir/.headers.XXXXXX")
  trap 'rm -f "$tmp"' EXIT
  trap 'exit 1' HUP INT TERM
fi

auth=$(printf '%s:%s' "$pk" "$sk" | base64 | tr -d '\n')

if [ "${1:-}" = --file ]; then
  printf 'Authorization=Basic%%20%s,x-langfuse-ingestion-version=4\n' "$auth" > "$tmp"
  mv -f "$tmp" "$headers"
  printf '%s\n' "$headers"
elif [ "${1:-}" = --env ]; then
  printf 'Authorization=Basic%%20%s,x-langfuse-ingestion-version=4\n' "$auth"
else
  printf '{"Authorization": "Basic %s", "x-langfuse-ingestion-version": "4"}\n' "$auth"
fi
