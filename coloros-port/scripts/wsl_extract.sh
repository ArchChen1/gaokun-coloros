#!/usr/bin/env bash
set -euo pipefail
SRC=/mnt/e/gaokun-coloros/coloros-port/work/opd2513
DST=/home/cenmin/coloros-trees
rm -rf "$DST"
mkdir -p "$DST"
cd "$DST"
for p in system system_ext product vendor odm my_product my_stock my_manifest; do
  echo "==== $p ===="
  mkdir -p "$p"
  fsck.erofs --extract="$p" --preserve "$SRC/$p.img" >"/tmp/$p-extract.log" 2>&1
  tail -n 3 "/tmp/$p-extract.log"
done
du -sh "$DST"/*
