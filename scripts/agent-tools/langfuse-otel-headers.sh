#!/usr/bin/env bash
# Print the OTLP headers that authenticate agent traces to the local Langfuse.
# The keys stay in ~/.config/secrets/langfuse.env (written by langfuse-up.sh),
# never in this public repo. Without that file there is nothing to print.
#   (no flag)  JSON for Claude Code's otelHeadersHelper
#   --env      k=v pairs for OTEL_EXPORTER_OTLP_HEADERS (percent-encoded)
set -euo pipefail

secrets="${LANGFUSE_SECRETS:-$HOME/.config/secrets/langfuse.env}"
if [ ! -r "$secrets" ]; then
  [ "${1:-}" = --env ] || echo '{}'
  exit 0
fi

pk=$(sed -n 's/^LANGFUSE_INIT_PROJECT_PUBLIC_KEY=//p' "$secrets")
sk=$(sed -n 's/^LANGFUSE_INIT_PROJECT_SECRET_KEY=//p' "$secrets")
auth=$(printf '%s:%s' "$pk" "$sk" | base64 | tr -d '\n')

if [ "${1:-}" = --env ]; then
  printf 'Authorization=Basic%%20%s,x-langfuse-ingestion-version=4\n' "$auth"
else
  printf '{"Authorization": "Basic %s", "x-langfuse-ingestion-version": "4"}\n' "$auth"
fi
