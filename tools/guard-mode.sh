#!/usr/bin/env bash
set -euo pipefail
MODE_FILE="config/mode.yaml"
if [[ -f "$MODE_FILE" ]]; then
  MODE=$(grep -E '^mode:' "$MODE_FILE" | awk '{print $2}')
else
  MODE="read-only"
fi
ADMIN_TOKEN_FILE=${ADMIN_OVERRIDE_TOKEN_FILE:-}
if [[ -n "$ADMIN_TOKEN_FILE" && -f "$ADMIN_TOKEN_FILE" ]]; then
  ADMIN_TOKEN=$(<"$ADMIN_TOKEN_FILE")
else
  ADMIN_TOKEN=${ADMIN_OVERRIDE_TOKEN:-}
fi
CONFIG_TOKEN=$(grep -A2 '^adminOverride:' "$MODE_FILE" | grep 'token:' | awk '{print $2}' | tr -d '"')
OVERRIDE_OK=0
if [[ -n "$ADMIN_TOKEN" && -n "$CONFIG_TOKEN" && "$ADMIN_TOKEN" == "$CONFIG_TOKEN" ]]; then
  OVERRIDE_OK=1
fi
if [[ "$MODE" == "read-only" && "$OVERRIDE_OK" -eq 0 ]]; then
  echo "System is in read-only mode. Edits are blocked." >&2
  exit 1
fi
exit 0
