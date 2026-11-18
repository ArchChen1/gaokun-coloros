#!/bin/bash
set -euo pipefail
ROOT=/tmp/odm-current/root
echo '===== all service names under odm ====='
grep -RhoE '^[[:space:]]*service[[:space:]]+[A-Za-z0-9_.@-]+' "$ROOT/etc/init" 2>/dev/null | sed -E 's/^[[:space:]]*service[[:space:]]+//' | sort -u
echo '===== rc files containing interfaces ====='
grep -RIl '^[[:space:]]*interface ' "$ROOT/etc/init" 2>/dev/null | sort