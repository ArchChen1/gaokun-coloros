#!/bin/bash
set -euo pipefail
D=/home/cenmin/ramdisk-firststage-verify
rm -rf "$D"
mkdir -p "$D"
cd "$D"
gzip -dc /home/cenmin/coloros-build/ramdisk-firststage.img | cpio -idmu --quiet
file init first_stage.sh
stat -c '%a %s %n' init first_stage.sh fstab.gaokun3
cmp -s init /home/cenmin/coloros-build/boot-unpack/ramdisk-tree/init
echo INIT_UNCHANGED=0
cmp -s first_stage.sh /home/cenmin/coloros-build/first_stage_logger
echo LOGGER_MATCH=0
grep -n '^system ' fstab.gaokun3
