#!/usr/bin/env bash
set -euo pipefail
B=/home/cenmin/coloros-build/readback
S=/mnt/e/gaokun-coloros/coloros-port/out/super-coloros-a.img
P=/mnt/e/gaokun-coloros/coloros-port/scripts/partition_inspect.py
rm -rf "$B"
mkdir -p "$B"
python3 "$P" "$S" --extract vendor_a "$B/vendor.img"
python3 "$P" "$S" --extract system_a "$B/system.img"
python3 "$P" "$S" --extract my_manifest_a "$B/my_manifest.img"
ls -lh "$B"
