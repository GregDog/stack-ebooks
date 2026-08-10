#!/usr/bin/env bash
# Load KEY=value lines from a dotenv file without expanding $ in values.
# Docker Compose .env files must use $$ for a literal dollar sign; this helper
# unescapes $$ → $ when exporting for bash scripts.
load_env_file() {
  local file="$1"
  local line key value
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%$'\r'}"
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      value="${value//\$\$/$}"
      export "${key}=${value}"
    fi
  done <"$file"
}
