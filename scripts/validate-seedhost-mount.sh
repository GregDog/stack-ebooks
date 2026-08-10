#!/usr/bin/env bash
# Validate SeedHost rclone mount and Shelfmark path access.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/.env"
DOCKER="${DOCKER:-sg docker -c}"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "${ROOT}/scripts/load-env.sh"
  load_env_file "$ENV_FILE"
fi

MOUNT_POINT="${SEEDHOST_MOUNT_POINT:-/mnt/seedhost-ebooks}"
CONTAINER_PATH="${SEEDHOST_CONTAINER_PATH:-/home16/harenix/downloads/ebooks}"
DOWNLOADS_DIR="/nas/eBookDownloads"
LIBRARY_DIR="/nas/eBooks"
UNIT="rclone-seedhost-ebooks.service"

fail=0
ok() { echo "OK  $*"; }
bad() { echo "FAIL $*"; fail=1; }

echo "==> Host mount (${MOUNT_POINT})"
if systemctl is-active --quiet "$UNIT" 2>/dev/null; then
  ok "systemd ${UNIT} is active"
else
  bad "systemd ${UNIT} is not active (run: sudo bash scripts/install-seedhost-mount.sh)"
fi

if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
  ok "mountpoint ${MOUNT_POINT}"
else
  bad "not a mountpoint: ${MOUNT_POINT}"
fi

if findmnt -rn "$MOUNT_POINT" 2>/dev/null | grep -q read-only; then
  ok "host mount is read-only"
elif mount | grep "$MOUNT_POINT" | grep -q '\bro\b'; then
  ok "host mount is read-only"
else
  bad "host mount may be writable — expected read-only"
fi

echo "==> Shelfmark container"
if ! $DOCKER "docker inspect shelfmark" &>/dev/null; then
  bad "shelfmark container not running"
else
  if $DOCKER "docker exec shelfmark test -d '${CONTAINER_PATH}'"; then
    ok "container sees ${CONTAINER_PATH}"
  else
    bad "container missing ${CONTAINER_PATH}"
  fi

  if $DOCKER "docker exec shelfmark sh -c 'touch \"${CONTAINER_PATH}/.write-test\" 2>/dev/null'" ; then
    bad "container can write to ${CONTAINER_PATH} (should be read-only)"
  else
    ok "container cannot write to ${CONTAINER_PATH} (read-only)"
  fi

  if $DOCKER "docker exec shelfmark test -d '${DOWNLOADS_DIR}'"; then
    ok "container sees ${DOWNLOADS_DIR}"
  else
    bad "container missing ${DOWNLOADS_DIR} (create on Synology: /volume1/.../eBookDownloads)"
  fi

  if $DOCKER "docker exec shelfmark sh -c 'touch \"${DOWNLOADS_DIR}/.write-test\" && rm -f \"${DOWNLOADS_DIR}/.write-test\"'"; then
    ok "${DOWNLOADS_DIR} is writable in container"
  else
    bad "${DOWNLOADS_DIR} is not writable in container"
  fi
fi

echo "==> BookOrbit container"
if ! $DOCKER "docker inspect bookorbit" &>/dev/null; then
  bad "bookorbit container not running"
else
  if $DOCKER "docker exec bookorbit test -d '${LIBRARY_DIR}'"; then
    ok "container sees ${LIBRARY_DIR}"
  else
    bad "container missing ${LIBRARY_DIR} (create on Synology: /volume1/.../eBooks)"
  fi

  if $DOCKER "docker exec bookorbit sh -c 'touch \"${LIBRARY_DIR}/.write-test\" && rm -f \"${LIBRARY_DIR}/.write-test\"'"; then
    ok "${LIBRARY_DIR} is writable in container"
  else
    bad "${LIBRARY_DIR} is not writable in container"
  fi

  if $DOCKER "docker exec bookorbit test -d '${DOWNLOADS_DIR}'"; then
    ok "container sees Book Dock ${DOWNLOADS_DIR}"
  else
    bad "container missing Book Dock ${DOWNLOADS_DIR}"
  fi
fi

if [[ "$fail" -ne 0 ]]; then
  echo
  echo "Validation failed."
  exit 1
fi

echo
echo "All SeedHost / ebook path checks passed."
