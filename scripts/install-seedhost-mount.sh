#!/usr/bin/env bash
# Install and enable the read-only rclone SFTP mount for SeedHost ebook qBittorrent downloads.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/.env"
RCLONE_DIR="/opt/ebooks/shelfmark/rclone"
RCLONE_CONF="${RCLONE_DIR}/rclone.conf"
SYSTEMD_UNIT="rclone-seedhost-ebooks.service"
SYSTEMD_SRC="${ROOT}/host/systemd/${SYSTEMD_UNIT}"

if [[ ! -f "$ENV_FILE" ]]; then
  bash "${ROOT}/scripts/ensure-env.sh"
  echo "Edit ${ENV_FILE} with SeedHost credentials, then re-run this script." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

: "${SEEDHOST_SFTP_HOST:?SEEDHOST_SFTP_HOST required in .env}"
: "${SEEDHOST_SFTP_USER:?SEEDHOST_SFTP_USER required in .env}"
SEEDHOST_MOUNT_POINT="${SEEDHOST_MOUNT_POINT:-/mnt/seedhost-ebooks}"
SEEDHOST_SFTP_REMOTE_PATH="${SEEDHOST_SFTP_REMOTE_PATH:-downloads/ebooks}"

if [[ -z "${SEEDHOST_SFTP_PASSWORD:-}" && -z "${SEEDHOST_SFTP_KEY_FILE:-}" ]]; then
  echo "Set SEEDHOST_SFTP_PASSWORD or SEEDHOST_SFTP_KEY_FILE in ${ENV_FILE}" >&2
  exit 1
fi

echo "==> Installing packages (rclone, fuse3) if needed"
if ! command -v rclone >/dev/null; then
  sudo apt-get update -qq
  sudo apt-get install -y rclone fuse3
fi

echo "==> Enabling allow_other in fuse.conf"
if ! grep -q '^user_allow_other' /etc/fuse.conf 2>/dev/null; then
  echo "user_allow_other" | sudo tee -a /etc/fuse.conf >/dev/null
fi

echo "==> Creating directories"
sudo mkdir -p "$SEEDHOST_MOUNT_POINT" "$RCLONE_DIR" /opt/ebooks/shelfmark/config /opt/ebooks/bookorbit/data/{app,postgres}
sudo chown -R greg:greg /opt/ebooks "$SEEDHOST_MOUNT_POINT"
sudo chmod 755 "$SEEDHOST_MOUNT_POINT"

echo "==> Writing rclone config"
AUTH_BLOCK=""
if [[ -n "${SEEDHOST_SFTP_KEY_FILE:-}" ]]; then
  if [[ ! -f "$SEEDHOST_SFTP_KEY_FILE" ]]; then
    echo "Key file not found: ${SEEDHOST_SFTP_KEY_FILE}" >&2
    exit 1
  fi
  AUTH_BLOCK="key_file = ${SEEDHOST_SFTP_KEY_FILE}"
else
  obscured="$(rclone obscure "$SEEDHOST_SFTP_PASSWORD")"
  AUTH_BLOCK="pass = ${obscured}"
fi

cat >"${RCLONE_CONF}" <<EOF
[seedhost-sftp]
type = sftp
host = ${SEEDHOST_SFTP_HOST}
user = ${SEEDHOST_SFTP_USER}
${AUTH_BLOCK}
EOF
chmod 600 "${RCLONE_CONF}"

echo "==> Testing SFTP connection"
rclone lsd "seedhost-sftp:${SEEDHOST_SFTP_REMOTE_PATH}" --config "${RCLONE_CONF}" | head -5

echo "==> Installing systemd unit"
sudo cp "${SYSTEMD_SRC}" "/etc/systemd/system/${SYSTEMD_UNIT}"
sudo systemctl daemon-reload
sudo systemctl enable "${SYSTEMD_UNIT}"
sudo systemctl restart "${SYSTEMD_UNIT}"

sleep 3
if ! mountpoint -q "$SEEDHOST_MOUNT_POINT"; then
  echo "Mount failed. Check: sudo journalctl -u ${SYSTEMD_UNIT} -n 30" >&2
  exit 1
fi

echo "Mount active at ${SEEDHOST_MOUNT_POINT}"
mount | grep "$SEEDHOST_MOUNT_POINT" || true

if command -v docker >/dev/null && sg docker -c 'docker inspect shelfmark' &>/dev/null; then
  echo "==> Recreating shelfmark container (refresh FUSE bind mount)"
  (cd "$ROOT" && sg docker -c 'docker compose up -d --force-recreate shelfmark')
fi
