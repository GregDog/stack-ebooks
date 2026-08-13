#!/usr/bin/env bash
# Configure BookOrbit OIDC for family: group mapping, default library, no admin default perms.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/.env"
DOCKER="${DOCKER:-sg docker -c}"

MEDIA_OIDC_GROUP="${BOOKORBIT_MEDIA_OIDC_GROUP:-media-users}"
FAMILY_PERMISSION="${BOOKORBIT_FAMILY_PERMISSION:-library_download}"
DEFAULT_LIBRARY_ID="${BOOKORBIT_DEFAULT_LIBRARY_ID:-}"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "${ROOT}/scripts/load-env.sh"
  load_env_file "$ENV_FILE"
  MEDIA_OIDC_GROUP="${BOOKORBIT_MEDIA_OIDC_GROUP:-$MEDIA_OIDC_GROUP}"
  FAMILY_PERMISSION="${BOOKORBIT_FAMILY_PERMISSION:-$FAMILY_PERMISSION}"
  DEFAULT_LIBRARY_ID="${BOOKORBIT_DEFAULT_LIBRARY_ID:-$DEFAULT_LIBRARY_ID}"
fi

for i in $(seq 1 30); do
  if ! $DOCKER "docker inspect bookorbit-db" &>/dev/null; then
    sleep 2
    continue
  fi

  if [[ -z "${DEFAULT_LIBRARY_ID}" ]]; then
    DEFAULT_LIBRARY_ID=$($DOCKER "docker exec bookorbit-db psql -U bookorbit -d bookorbit -tAc \"SELECT id FROM libraries ORDER BY id LIMIT 1;\"" 2>/dev/null | tr -d '[:space:]')
  fi
  DEFAULT_LIBRARY_ID="${DEFAULT_LIBRARY_ID:-1}"

  if $DOCKER "docker exec bookorbit-db psql -U bookorbit -d bookorbit -v ON_ERROR_STOP=1 -c \"
UPDATE oidc_providers SET scopes = 'openid profile email groups',
  auto_provision = jsonb_set(jsonb_set(auto_provision, '{enabled}', 'true'), '{defaultPermissionNames}', '[]'::jsonb)
WHERE slug = 'pocketid';
\"" 2>/dev/null \
  && $DOCKER "docker exec bookorbit-db psql -U bookorbit -d bookorbit -v ON_ERROR_STOP=1 -c \"
INSERT INTO oidc_group_mappings (provider_id, oidc_group_claim, permission_name)
SELECT id, '${MEDIA_OIDC_GROUP}', '${FAMILY_PERMISSION}' FROM oidc_providers WHERE slug = 'pocketid'
ON CONFLICT (provider_id, oidc_group_claim) DO UPDATE SET permission_name = EXCLUDED.permission_name;
\"" 2>/dev/null \
  && $DOCKER "docker exec bookorbit-db psql -U bookorbit -d bookorbit -v ON_ERROR_STOP=1 -c \"
INSERT INTO app_settings (key, value) VALUES ('default_library_access', '{\\\"libraryIds\\\":[${DEFAULT_LIBRARY_ID}]}')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
\"" 2>/dev/null; then
    echo "BookOrbit: family OIDC group ${MEDIA_OIDC_GROUP} → ${FAMILY_PERMISSION}, default library ${DEFAULT_LIBRARY_ID}"
    exit 0
  fi

  sleep 2
done

echo "WARNING: could not configure BookOrbit family OIDC" >&2
exit 0
