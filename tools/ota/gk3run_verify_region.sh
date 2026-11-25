#!/system/bin/sh
# gk3run v3：读 super 内 my_region_a extent 并算 sha256（与 new_partition.csv 的哈希比对）
OUT=/data/local/tmp/gk3run3.out
{
    echo "== dump my_region_a extent"
    dd if=/dev/block/nvme0n1p10 of=/data/local/tmp/mr_a.img bs=512 skip=19638272 count=14136 2>&1
    echo "== size"
    ls -l /data/local/tmp/mr_a.img
    echo "== sha256"
    sha256sum /data/local/tmp/mr_a.img
    echo "== mount ro check (erofs?)"
    file /data/local/tmp/mr_a.img 2>&1 || true
} > "$OUT" 2>&1
chmod 644 "$OUT"
