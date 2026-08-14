#!/usr/bin/env bash
# Build a CA bundle for Shelfmark: system roots + Caddy internal CA for id.cvss.io OIDC.
# REQUESTS_CA_BUNDLE must not point at the Caddy root alone — that breaks public HTTPS APIs
# such as Hardcover used by universal search.
set -euo pipefail

DOCKER="${DOCKER:-sg docker -c}"
VOLUME="${CADDY_DATA_VOLUME:-stackproxy_caddy_data}"
CONFIG_DIR="${SHELFMARK_CONFIG_DIR:-/opt/ebooks/shelfmark/config}"
OUT="${CONFIG_DIR}/combined-ca.crt"
CADDY_ROOT="/data/caddy/pki/authorities/local/root.crt"
SYSTEM_CA="/etc/ssl/certs/ca-certificates.crt"

mkdir -p "${CONFIG_DIR}"

if [[ ! -f "${SYSTEM_CA}" ]]; then
  echo "ERROR: system CA bundle not found at ${SYSTEM_CA}" >&2
  exit 1
fi

if ! $DOCKER "docker volume inspect ${VOLUME}" &>/dev/null; then
  echo "ERROR: Caddy data volume ${VOLUME} not found" >&2
  exit 1
fi

if ! $DOCKER "docker run --rm -v ${VOLUME}:/data alpine test -f ${CADDY_ROOT}"; then
  echo "ERROR: Caddy internal CA not found — deploy stackproxy first" >&2
  exit 1
fi

cp "${SYSTEM_CA}" "${OUT}"
$DOCKER "docker run --rm -v ${VOLUME}:/data alpine cat ${CADDY_ROOT}" >> "${OUT}"
chmod 644 "${OUT}"

echo "Shelfmark: wrote combined CA bundle to ${OUT}"
