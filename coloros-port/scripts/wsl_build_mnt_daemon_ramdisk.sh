#!/bin/bash
set -euo pipefail
B=/home/cenmin/coloros-build
SRC=$B/boot-unpack/ramdisk.new
TREE=$B/ramdisk-mnt-daemon-tree
OUT=$B/ramdisk-mnt-daemon.img
install -m 0644 /mnt/e/gaokun-coloros/coloros-port/scripts/debug_init_mnt_daemon.c "$B/debug_init_mnt_daemon.c"
aarch64-linux-gnu-gcc -static -O2 -Wall -Wextra -Werror -o "$B/debug-init-mnt-daemon" "$B/debug_init_mnt_daemon.c"
file "$B/debug-init-mnt-daemon"
sha256sum "$B/debug-init-mnt-daemon"
rm -rf "$TREE"
mkdir -p "$TREE"
cd "$TREE"
gzip -dc "$SRC" | cpio -idmu --quiet
test -x init
orig=$(sha256sum init | awk '{print $1}')
mv init init.real
install -m 0755 "$B/debug-init-mnt-daemon" init
real=$(sha256sum init.real | awk '{print $1}')
test "$orig" = "$real"
find . -print0 | cpio --null -o --format=newc --quiet | gzip -9 > "$OUT"
test -s "$OUT"
echo "original_init=$orig"
echo "init_real=$real"
file "$OUT"
ls -lh "$OUT"
sha256sum "$OUT"