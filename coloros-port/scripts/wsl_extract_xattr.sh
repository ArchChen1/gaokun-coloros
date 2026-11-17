#!/usr/bin/env bash
set -euo pipefail
SRC=/mnt/e/gaokun-coloros/coloros-port/work/opd2513
DST=/home/cenmin/coloros-trees-xattr
MNT=/mnt/erofs-source
rm -rf "$DST"
mkdir -p "$DST" "$MNT"
for p in system system_ext product vendor odm my_product my_stock my_manifest; do
  echo "==== $p ===="
  mkdir -p "$DST/$p"
  mount -t erofs -o loop,ro "$SRC/$p.img" "$MNT"
  cp -a --reflink=auto "$MNT"/. "$DST/$p"/
  umount "$MNT"
done
du -sh "$DST"/*
