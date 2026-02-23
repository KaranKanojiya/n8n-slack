#!/usr/bin/env bash
# Backup n8n + Postgres volumes into this project (local-n8n-setup/backups/).
# Run from: local-n8n-setup/
# Requires: stack running for Postgres dump (docker compose up -d).

set -e
cd "$(dirname "$0")"
BACKUP_DIR="backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

# Load .env for Postgres user/db (optional; defaults below)
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi
PG_USER="${POSTGRES_USER:-postgres}"
PG_DB="${POSTGRES_DB:-n8n}"

echo "Backing up to $BACKUP_DIR (timestamp: $TIMESTAMP) ..."

# 1) Postgres: logical dump (safe, works while running)
PG_FILE="$BACKUP_DIR/n8n_db_$TIMESTAMP.sql"
if docker compose exec -T postgres pg_dump -U "$PG_USER" "$PG_DB" > "$PG_FILE" 2>/dev/null; then
  echo "  Postgres: $PG_FILE"
else
  echo "  Postgres: skip (is the stack running? try: docker compose up -d)"
fi

# 2) n8n_data volume: tar (config, encryption key, etc.)
# Volume name = project name + _n8n_data (project = directory name)
N8N_VOLUME="local-n8n-setup_n8n_data"
N8N_FILE="$BACKUP_DIR/n8n_data_$TIMESTAMP.tar.gz"
if docker run --rm -v "$N8N_VOLUME:/data:ro" -v "$(pwd)/$BACKUP_DIR:/backup" alpine tar czf "/backup/n8n_data_$TIMESTAMP.tar.gz" -C /data . 2>/dev/null; then
  echo "  n8n_data: $N8N_FILE"
else
  echo "  n8n_data: skip (volume $N8N_VOLUME not found or Docker not running)"
fi

echo "Done."
