#!/bin/bash
set -euo pipefail
B=/home/cenmin/coloros-build
SRC=$B/boot-unpack/ramdisk.new
TREE=$B/ramdisk-debug-tree
OUT=$B/ramdisk-debug.img
rm -rf "$TREE"
mkdir -p "$TREE"
cd "$TREE"
gzip -dc "$SRC" | cpio -idmu --quiet
test -x "$B/debug-init"
test -f "$TREE/init"
mv "$TREE/init" "$TREE/init.real"
install -m 0755 "$B/debug-init" "$TREE/init"
find . -print0 | cpio --null -o --format=newc --quiet | gzip -9 > "$OUT"
test -s "$OUT"
file "$OUT"
sha256sum "$OUT"
