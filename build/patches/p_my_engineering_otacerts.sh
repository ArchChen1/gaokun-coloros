#!/bin/bash
# 补丁：my_engineering 换成自签 OTA 证书（update_engine 只认 otacerts.zip 里以 x509.pem 结尾的条目）
#
# 背景：donor 里的 etc/security/otacerts.zip 是 OPPO 原厂证书，我们的 payload 用自签 RSA 签，
# 引擎在 kDownloadMetadataSignatureVerificationError 处会拒。换成自签证书后 OTA 才能验签。
#
# 输入 = v49 donor（EROFS，f38ccd36…）；输出 = 账本产物 ce71e4b6… 的内容等价版。
# EROFS 重建不保证字节一致（mkfs 版本/时间戳/压缩实现都在变），所以验的是文件树。
#
# 用法：
#   bash build/patches/p_my_engineering_otacerts.sh <donor.img> <out.img> [参考镜像]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
IN=${1:?用法: p_my_engineering_otacerts.sh <donor.img> <out.img> [参考镜像]}
OUT=${2:?}
REF=${3:-}
IN_SHA=f38ccd367fb88bf6c123a025a7dbbe7174b95227f242fc5c925121ee1e6179ab
ZIP="$ROOT/.secrets/payload/otacerts.zip"
ZIP_SHA=e98d97cb883e7bfa857443e3119070c162d15c721829a158b2c7a9314aef42a8
SIZE=335872                     # my_engineering 分区 656 sectors
UUID=F5FBEAE9-13CB-F055-964B-193C260A63B4
FSCK=/home/cenmin/toolchain/erofs-install/bin/fsck.erofs
MKFS=/home/cenmin/toolchain/erofs-install/bin/mkfs.erofs

got=$(sha256sum "$IN" | cut -d' ' -f1)
[ "$got" = "$IN_SHA" ] || { echo "输入不是 v49 donor（$got != $IN_SHA），拒绝改" >&2; exit 1; }
[ -f "$ZIP" ] || { echo "缺自签证书包 $ZIP" >&2; exit 1; }
[ "$(sha256sum "$ZIP" | cut -d' ' -f1)" = "$ZIP_SHA" ] || { echo "证书包 sha 不是 e98d97cb…" >&2; exit 1; }
[ -x "$FSCK" ] && [ -x "$MKFS" ] || { echo "缺 erofs 工具" >&2; exit 1; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
"$FSCK" --extract="$T/tree" "$IN" >/dev/null 2>&1 || { echo "解包失败" >&2; exit 1; }
old=$(sha256sum "$T/tree/etc/security/otacerts.zip" | cut -d' ' -f1)
echo "    donor 里的 otacerts.zip = ${old:0:16}…（原厂证书，预期与自签不同）"
install -m 644 "$ZIP" "$T/tree/etc/security/otacerts.zip"

"$MKFS" -zlz4 -b4096 -C65536 -U "$UUID" "$OUT" "$T/tree" >/dev/null
sz=$(stat -c%s "$OUT")
if [ "$sz" -gt "$SIZE" ]; then echo "   镜像 $sz > 分区 $SIZE，装不下" >&2; exit 1; fi
truncate -s "$SIZE" "$OUT"
echo "   输出 $OUT  $sz B（truncate 到 $SIZE）  sha $(sha256sum "$OUT" | cut -c1-16)…"

[ -n "$REF" ] || { echo "   未给参考镜像，跳过内容核对"; exit 0; }
A=$(mktemp -d); B=$(mktemp -d)
mount -o loop,ro "$OUT" "$A"; mount -o loop,ro "$REF" "$B"
if diff -rq --no-dereference "$A" "$B" > /tmp/p_myeng.diff 2>&1; then
    echo "OK  my_engineering 证书补丁：文件树与账本产物一致（otacerts.zip = 自签 ${ZIP_SHA:0:16}…）"
else
    echo "FAIL 与参考镜像的文件树不同：" >&2; head -20 /tmp/p_myeng.diff >&2; exit 3
fi
umount "$A" "$B"; rmdir "$A" "$B"
