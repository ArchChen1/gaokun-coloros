#!/bin/bash
set -euo pipefail
B=/home/cenmin/coloros-build
SRC=$B/boot-unpack/ramdisk.new
TREE=$B/ramdisk-delayed-tree
OUT=$B/ramdisk-delayed.img
install -m 0644 /mnt/e/gaokun-coloros/coloros-port/scripts/debug_init_delayed.c "$B/debug_init_delayed.c"
aarch64-linux-gnu-gcc -static -O2 -Wall -Wextra -Werror -o "$B/debug-init-delayed" "$B/debug_init_delayed.c"
file "$B/debug-init-delayed"
sha256sum "$B/debug-init-delayed"
rm -rf "$TREE"
mkdir -p "$TREE"
cd "$TREE"
gzip -dc "$SRC" | cpio -idmu --quiet
test -x init
orig=$(sha256sum init | awk '{print $1}')
mv init init.real
install -m 0755 "$B/debug-init-delayed" init
real=$(sha256sum init.real | awk '{print $1}')
test "$orig" = "$real"
find . -print0 | cpio --null -o --format=newc --quiet | gzip -9 > "$OUT"
test -s "$OUT"
echo "original_init=$orig"
echo "init_real=$real"
file "$OUT"
ls -lh "$OUT"
sha256sum "$OUT"