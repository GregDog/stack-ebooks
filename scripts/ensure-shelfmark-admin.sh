#!/usr/bin/env bash
# Promote Pocket ID SSO user to Shelfmark admin (local login disabled).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT}/.env"
DOCKER="${DOCKER:-sg docker -c}"

ADMIN_EMAIL="${SHELFMARK_ADMIN_EMAIL:-gregdogknell@gmail.com}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "${ROOT}/scripts/load-env.sh"
  load_env_file "$ENV_FILE"
  ADMIN_EMAIL="${SHELFMARK_ADMIN_EMAIL:-$ADMIN_EMAIL}"
fi

for i in $(seq 1 30); do
  if ! $DOCKER "docker inspect shelfmark" &>/dev/null; then
    sleep 2
    continue
  fi

  count=$($DOCKER "docker exec shelfmark python3 -c \"
import sqlite3
con = sqlite3.connect('/config/users.db')
cur = con.cursor()
cur.execute('UPDATE users SET role = \\\"admin\\\" WHERE lower(email) = lower(?)', ('${ADMIN_EMAIL}',))
con.commit()
print(cur.rowcount)
\"" 2>/dev/null || echo "err")

  if [[ "$count" == "1" ]]; then
    echo "Shelfmark: promoted ${ADMIN_EMAIL} to admin"
    exit 0
  fi
  if [[ "$count" == "0" ]]; then
    echo "Shelfmark: OIDC user ${ADMIN_EMAIL} not found yet (log in once via Pocket ID)"
    exit 0
  fi
  sleep 2
done

echo "WARNING: could not update Shelfmark admin (database not ready)" >&2
exit 0
