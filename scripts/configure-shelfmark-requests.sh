#!/usr/bin/env bash
# Enable Shelfmark request workflow so family must request books for admin approval.
set -euo pipefail

DOCKER="${DOCKER:-sg docker -c}"
USERS_PLUGIN="/config/plugins/users.json"

for i in $(seq 1 30); do
  if ! $DOCKER "docker inspect shelfmark" &>/dev/null; then
    sleep 2
    continue
  fi

  if $DOCKER "docker exec shelfmark test -f ${USERS_PLUGIN}" 2>/dev/null; then
    $DOCKER "docker exec shelfmark python3 -c \"
import json
path = '${USERS_PLUGIN}'
with open(path) as f:
    cfg = json.load(f)
cfg['REQUESTS_ENABLED'] = True
cfg['REQUEST_POLICY_DEFAULT_EBOOK'] = 'request_book'
cfg['REQUEST_POLICY_DEFAULT_AUDIOBOOK'] = 'request_book'
cfg.setdefault('REQUEST_POLICY_RULES', [])
cfg.setdefault('MAX_PENDING_REQUESTS_PER_USER', 20)
cfg.setdefault('REQUESTS_ALLOW_NOTES', True)
with open(path, 'w') as f:
    json.dump(cfg, f, indent=2)
    f.write('\\n')
print('ok')
\"" 2>/dev/null | grep -q ok && {
      echo "Shelfmark: requests enabled (default mode: request_book)"
      exit 0
    }
  fi
  sleep 2
done

echo "WARNING: could not configure Shelfmark request policy" >&2
exit 0
