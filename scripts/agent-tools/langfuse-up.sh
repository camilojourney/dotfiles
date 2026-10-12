#!/usr/bin/env bash
# Run the self-hosted Langfuse that stores agent traces and eval scores, from
# its official docker compose file pinned below. OrbStack (nix/configuration.nix)
# provides Docker. First run writes random secrets and API keys to
# ~/.config/secrets/langfuse.env. UI and OTLP endpoint: http://localhost:3000
set -euo pipefail

LANGFUSE_REF="${LANGFUSE_REF:-cb2ceba}"
dir="${LANGFUSE_DIR:-$HOME/.local/share/langfuse}"
secrets="$HOME/.config/secrets/langfuse.env"

mkdir -p "$dir" "$(dirname "$secrets")"
chmod 700 "$(dirname "$secrets")"
curl -fsSL "https://raw.githubusercontent.com/langfuse/langfuse/$LANGFUSE_REF/docker-compose.yml" -o "$dir/docker-compose.yml"
# The official file publishes the web UI and MinIO on every interface; keep
# both on loopback like the other services.
cat > "$dir/loopback.yml" <<'LOOPBACK'
services:
  langfuse-web:
    ports: !override
      - 127.0.0.1:3000:3000
  minio:
    ports: !override
      - 127.0.0.1:9090:9000
      - 127.0.0.1:9091:9001
LOOPBACK

if [ ! -f "$secrets" ]; then
  r() { openssl rand -hex "${1:-16}"; }
  umask 077
  cat > "$secrets" <<SECRETS
SALT=$(r)
ENCRYPTION_KEY=$(r 32)
NEXTAUTH_SECRET=$(r)
POSTGRES_PASSWORD=$(r)
DATABASE_URL=postgresql://postgres:\${POSTGRES_PASSWORD}@postgres:5432/postgres
CLICKHOUSE_PASSWORD=$(r)
MINIO_ROOT_PASSWORD=$(r)
LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY=\${MINIO_ROOT_PASSWORD}
LANGFUSE_S3_MEDIA_UPLOAD_SECRET_ACCESS_KEY=\${MINIO_ROOT_PASSWORD}
LANGFUSE_S3_BATCH_EXPORT_SECRET_ACCESS_KEY=\${MINIO_ROOT_PASSWORD}
REDIS_AUTH=$(r)
LANGFUSE_INIT_ORG_ID=fleet
LANGFUSE_INIT_ORG_NAME=Fleet
LANGFUSE_INIT_PROJECT_ID=fleet
LANGFUSE_INIT_PROJECT_NAME=fleet
LANGFUSE_INIT_PROJECT_PUBLIC_KEY=pk-lf-$(r)
LANGFUSE_INIT_PROJECT_SECRET_KEY=sk-lf-$(r)
LANGFUSE_INIT_USER_EMAIL=$(git config --global user.email)
LANGFUSE_INIT_USER_NAME=$(git config --global user.name | tr -d ' ')
LANGFUSE_INIT_USER_PASSWORD=$(r 12)
SECRETS
  echo "langfuse-up: wrote $secrets"
fi

docker compose --project-name langfuse --env-file "$secrets" \
  -f "$dir/docker-compose.yml" -f "$dir/loopback.yml" up -d
echo "langfuse-up: http://localhost:3000 (login: LANGFUSE_INIT_USER_EMAIL / LANGFUSE_INIT_USER_PASSWORD in $secrets)"
