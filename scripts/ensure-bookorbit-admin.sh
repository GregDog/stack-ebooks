#!/usr/bin/env bash
# Ensure Pocket ID SSO user has BookOrbit superuser + admin permissions.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/.env"
DOCKER="${DOCKER:-sg docker -c}"

ADMIN_EMAIL="${BOOKORBIT_ADMIN_EMAIL:-gregdogknell@gmail.com}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "${ROOT}/scripts/load-env.sh"
  load_env_file "$ENV_FILE"
  ADMIN_EMAIL="${BOOKORBIT_ADMIN_EMAIL:-$ADMIN_EMAIL}"
fi

for i in $(seq 1 30); do
  if ! $DOCKER "docker inspect bookorbit-db" &>/dev/null; then
    sleep 2
    continue
  fi

  updated=$($DOCKER "docker exec bookorbit-db psql -U bookorbit -d bookorbit -tAc \"
UPDATE users SET is_superuser = true, active = true WHERE lower(email) = lower('${ADMIN_EMAIL}');
INSERT INTO user_permissions (user_id, permission_name)
SELECT id, p FROM users, (VALUES ('manage_app_settings'), ('manage_users')) AS perms(p)
WHERE lower(users.email) = lower('${ADMIN_EMAIL}')
ON CONFLICT DO NOTHING;
UPDATE oidc_providers
SET auto_provision = jsonb_set(
  jsonb_set(auto_provision, '{allowLocalLinking}', 'true'),
  '{defaultPermissionNames}',
  '[\\\"manage_app_settings\\\", \\\"manage_users\\\", \\\"library_download\\\", \\\"email_send\\\"]'::jsonb
)
WHERE slug = 'pocketid';
SELECT count(*) FROM users WHERE lower(email) = lower('${ADMIN_EMAIL}') AND is_superuser = true;
\"" 2>/dev/null | tail -1 || true)

  if [[ "$updated" == "1" ]]; then
    echo "BookOrbit: ensured superuser for ${ADMIN_EMAIL} (OIDC local linking enabled)"
    exit 0
  fi

  if [[ "$updated" == "0" ]]; then
    echo "BookOrbit: user ${ADMIN_EMAIL} not found yet (complete setup or log in once via Pocket ID)"
    exit 0
  fi

  sleep 2
done

echo "WARNING: could not update BookOrbit admin (database not ready)" >&2
exit 0
