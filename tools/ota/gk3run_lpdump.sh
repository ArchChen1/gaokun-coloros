#!/system/bin/sh
# gk3run v2：定位 super 内 my_region_b 的 extent，并读出合并后内容
OUT=/data/local/tmp/gk3run2.out
{
    echo "== whoami"
    id
    echo "== new_partition.csv"
    cat /metadata/ota/new_partition.csv 2>&1
    echo "== merge_stats"
    cat /metadata/ota/merge_stats 2>&1
    echo
    echo "== by-name super"
    ls -l /dev/block/by-name/super 2>&1
    echo "== lpdump my_region"
    lpdump /dev/block/by-name/super 2>&1 | grep -i -B1 -A8 "my_region" | head -40
    echo "== lpdump groups"
    lpdump /dev/block/by-name/super 2>&1 | grep -iE "Name:|Group|Attributes" | head -60
} > "$OUT" 2>&1
chmod 644 "$OUT"
