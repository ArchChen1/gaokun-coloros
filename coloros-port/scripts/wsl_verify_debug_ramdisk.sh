#!/bin/bash
set -euo pipefail
D=/home/cenmin/ramdisk-debug-verify-3
rm -rf "$D"
mkdir -p "$D"
cd "$D"
gzip -dc /home/cenmin/coloros-build/ramdisk-debug.img | cpio -idmu --quiet
file init init.real
stat -c '%a %s %n' init init.real fstab.gaokun3 dev/kmsg dev/console
cmp -s init /home/cenmin/coloros-build/debug-init
echo WRAPPER_CMP=0
cmp -s init.real /home/cenmin/coloros-build/boot-unpack/ramdisk-tree/init
echo ORIG_INIT_CMP=0
sha256sum init.real /home/cenmin/coloros-build/boot-unpack/ramdisk-tree/init

grep -n '^system ' fstab.gaokun3
grep -n '^vendor ' fstab.gaokun3
