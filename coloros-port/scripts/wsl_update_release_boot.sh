#!/usr/bin/env bash
set -euo pipefail
REL=/mnt/e/gaokun-coloros/coloros-port/out/release-coloros-a
B=/home/cenmin/coloros-build/boot-coloros.img
cp -f "$B" "$REL/boot.img"
chmod 644 "$REL/boot.img"
cd "$REL"
sha256sum boot.img super.img.zst > install-artifacts.sha256
cat install-artifacts.sha256
ls -lh
