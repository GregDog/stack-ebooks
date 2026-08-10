#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DOCKER="${DOCKER:-sg docker -c}"

echo "==> Validating Compose"
$DOCKER "docker compose --env-file .env.example config" >/dev/null 2>&1 || \
  $DOCKER "docker compose config" >/dev/null

if mountpoint -q /mnt/seedhost-ebooks 2>/dev/null; then
  echo "==> Validating SeedHost mount"
  bash scripts/validate-seedhost-mount.sh
else
  echo "WARNING: /mnt/seedhost-ebooks not mounted (OK if first-time setup before install-seedhost-mount.sh)"
fi

echo "All validations passed."
