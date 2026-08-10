#!/usr/bin/env bash
# Wrapper for systemd — sources stack .env and execs rclone mount (ebook downloads).
set -euo pipefail

ENV_FILE="/opt/stacks/ebooks/.env"
RCLONE_CONF="/opt/ebooks/shelfmark/rclone/rclone.conf"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing ${ENV_FILE}" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

MOUNT_POINT="${SEEDHOST_MOUNT_POINT:-/mnt/seedhost-ebooks}"
REMOTE_PATH="${SEEDHOST_SFTP_REMOTE_PATH:-downloads/ebooks}"

mkdir -p "$MOUNT_POINT"

exec /usr/bin/rclone mount "seedhost-sftp:${REMOTE_PATH}" "$MOUNT_POINT" \
  --config "$RCLONE_CONF" \
  --read-only \
  --vfs-cache-mode full \
  --dir-cache-time 1m \
  --allow-other \
  --uid 1000 \
  --gid 1000 \
  --log-file /opt/ebooks/shelfmark/rclone/rclone-mount.log \
  --log-level INFO
