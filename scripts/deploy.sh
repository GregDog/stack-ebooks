#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DOCKER="${DOCKER:-sg docker -c}"

bash scripts/validate.sh

bash scripts/ensure-env.sh
if [[ -f "${ROOT}/.env" ]]; then
  bash scripts/sync-prowlarr-api-key.sh
fi

if [[ -f "${ROOT}/.env" ]] && grep -qE '^SEEDHOST_SFTP_PASSWORD=.{1,}' "${ROOT}/.env" 2>/dev/null \
   || grep -qE '^SEEDHOST_SFTP_KEY_FILE=/' "${ROOT}/.env" 2>/dev/null; then
  if ! mountpoint -q /mnt/seedhost-ebooks 2>/dev/null; then
    echo "==> SeedHost ebook mount not active; running install-seedhost-mount.sh"
    bash scripts/install-seedhost-mount.sh
  fi
else
  echo "WARNING: ${ROOT}/.env missing SeedHost credentials — skip mount install" >&2
fi

MOUNT_POINT="${SEEDHOST_MOUNT_POINT:-/mnt/seedhost-ebooks}"
if [[ -f "${ROOT}/.env" ]]; then
  # shellcheck source=/dev/null
  source "${ROOT}/scripts/load-env.sh"
  load_env_file "${ROOT}/.env"
  MOUNT_POINT="${SEEDHOST_MOUNT_POINT:-/mnt/seedhost-ebooks}"
fi

if ! mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
  echo "ERROR: SeedHost rclone mount is not active at ${MOUNT_POINT}" >&2
  echo "  cp .env.example .env  # set SEEDHOST_SFTP_PASSWORD" >&2
  echo "  bash scripts/install-seedhost-mount.sh" >&2
  exit 1
fi

echo "==> Deploying ebooks stack"
$DOCKER "docker compose pull"
$DOCKER "docker compose up -d"

if $DOCKER "docker compose ps --status running --services" 2>/dev/null | grep -qx shelfmark; then
  bash scripts/ensure-shelfmark-admin.sh
fi

echo "==> Container status"
$DOCKER "docker compose ps"

if [[ -f "${ROOT}/.env" ]]; then
  bash scripts/validate-seedhost-mount.sh
fi

echo "Deploy complete."
