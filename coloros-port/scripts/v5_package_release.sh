set -u
CB=/home/cenmin/coloros-build
REL=$CB/release-coloros-v5
SRC=$CB/super-coloros-v5.simg

rm -rf "$REL"; mkdir -p "$REL"
echo "=== compress super (12 threads, default 4MiB window) ==="
time zstd -T0 -12 -f "$SRC" -o "$REL/super.img.zst"
echo "=== integrity test ==="
zstd -t "$REL/super.img.zst" 2>&1 | tail -2
echo "=== boot.img (unchanged from v4c) ==="
cp -f "$CB/boot-coloros.img" "$REL/boot.img"
cd "$REL"
sha256sum boot.img super.img.zst > install-artifacts.sha256
cat install-artifacts.sha256
ls -l
echo V5_RELEASE_PACKED