#!/bin/bash
set -euo pipefail
base=/home/cenmin/coloros-build
items="release-coloros-v8 release-coloros-v9-stub release-coloros-v12 super-coloros-v8.simg super-coloros-v9.simg super-coloros-v9-stub.simg"
echo "=== v23 cleanup $(date -Is) ==="
for item in $items; do
  target="$base/$item"
  [ -e "$target" ] || continue
  resolved=$(realpath -m "$target")
  case "$resolved" in
    "$base"/*) ;;
    *) echo "unsafe path: $resolved" >&2; exit 1 ;;
  esac
  echo "removing $resolved"
  rm -rf --one-file-system -- "$resolved"
done
sync
df -h /home
echo V23_CLEANUP_DONE