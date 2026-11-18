#!/bin/bash
set -euo pipefail
B=/home/cenmin/coloros-build
TREE=$B/ramdisk-firststage-tree
OUT=$B/ramdisk-firststage.img
rm -rf "$TREE"
mkdir -p "$TREE"
cd "$TREE"
gzip -dc "$B/boot-unpack/ramdisk.new" | cpio -idmu --quiet
install -m 0755 "$B/first_stage_logger" "$TREE/first_stage.sh"
find . -print0 | cpio --null -o --format=newc --quiet | gzip -9 > "$OUT"
test -s "$OUT"
file "$OUT"
sha256sum "$OUT"
