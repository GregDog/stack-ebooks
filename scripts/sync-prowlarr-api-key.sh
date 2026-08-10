#!/usr/bin/env bash
# Copy Prowlarr API key from the audiobooks stack if .env is missing it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/.env"
PROWLARR_CONFIG="/opt/audiobooks/prowlarr/config/config.xml"

if [[ ! -f "$ENV_FILE" ]]; then
  exit 0
fi

if grep -qE '^PROWLARR_API_KEY=.{8,}' "$ENV_FILE" 2>/dev/null; then
  exit 0
fi

if [[ ! -f "$PROWLARR_CONFIG" ]]; then
  echo "WARNING: set PROWLARR_API_KEY in ${ENV_FILE} (Prowlarr config not found)" >&2
  exit 0
fi

api_key="$(grep -oP '(?<=<ApiKey>)[^<]+' "$PROWLARR_CONFIG" | head -1 || true)"
if [[ -z "$api_key" ]]; then
  echo "WARNING: could not read Prowlarr API key from ${PROWLARR_CONFIG}" >&2
  exit 0
fi

if grep -q '^PROWLARR_API_KEY=' "$ENV_FILE"; then
  sed -i "s|^PROWLARR_API_KEY=.*|PROWLARR_API_KEY=${api_key}|" "$ENV_FILE"
else
  echo "PROWLARR_API_KEY=${api_key}" >>"$ENV_FILE"
fi
echo "Prowlarr: copied PROWLARR_API_KEY from audiobooks stack into ${ENV_FILE}"
