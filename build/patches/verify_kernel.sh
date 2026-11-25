#!/bin/bash
# 内核/引导三件套的账本校验。补丁丢失在系统层之外的最后一环，就是这里。
#
#   bash build/patches/verify_kernel.sh [kernel-artifact.json]
#
# 验五件套（REPLAY=1 再加第六件）：
#   1) 内核树存在，Makefile 版本 = 7.2.9
#   2) git HEAD = 账本、工作区 clean、提交数 = 账本（补丁被 reset / 多打 / 少打都会露出来）
#   3) .config sha = 账本，且与仓库里那份 config 完全一致（config 漂移会静默改掉能力，比如 UBLK）
#   4) 仓库里的合并补丁 sha = 账本；文件锁 136 个文件内容逐个核对（补丁被手改/丢一半会露出来）
#   5) vmlinuz.efi 的 sha/size = 账本；本机留存的 ESP 三件套若在，也逐份比
#   6) REPLAY=1：检出 v7.2.9 基线 → 打合并补丁 → 与当前树逐字节比（证明补丁层可重建）
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
LEDGER=${1:-$ROOT/patches/kernel-build/kernel-artifact.json}
FAIL=0
say() { printf '%s\n' "$*"; }
ok() { printf '  OK   %s\n' "$*"; }
fail() { printf '  FAIL %s\n' "$*"; FAIL=1; }

js() { python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(eval(sys.argv[2]))" "$LEDGER" "$1"; }
K=$(js "d['kernel']['tree']")
CFG_SHA=$(js "d['kernel']['config_sha256']")
HEAD=$(js "d['kernel']['head']")
CNT=$(js "d['kernel']['commit_count']")
ART=$(js "d['kernel']['artifact']['path']")
ART_SHA=$(js "d['kernel']['artifact']['sha256']")
ART_SIZE=$(js "d['kernel']['artifact']['bytes']")
GIT="git -C $K -c safe.directory=$K"

say "== 1. 内核树 / 版本"
if [ -f "$K/Makefile" ]; then
    V1=$(sed -n 's/^VERSION = //p' "$K/Makefile")
    V2=$(sed -n 's/^PATCHLEVEL = //p' "$K/Makefile")
    V3=$(sed -n 's/^SUBLEVEL = //p' "$K/Makefile")
    V="$V1.$V2.$V3"
    [ "$V" = "7.2.9" ] && ok "内核树 $K 版本 $V" || fail "版本 $V != 7.2.9"
else fail "内核树不存在：$K"; fi

say "== 2. git 状态（补丁层）"
if [ -d "$K/.git" ]; then
    H=$($GIT rev-parse HEAD 2>/dev/null)
    [ "$H" = "$HEAD" ] && ok "HEAD ${H:0:12}…" || fail "HEAD ${H:0:12}… != 账本 ${HEAD:0:12}…（补丁层变了）"
    N=$($GIT rev-list --count HEAD 2>/dev/null)
    [ "$N" = "$CNT" ] && ok "提交数 $N" || fail "提交数 $N != 账本 $CNT"
    D=$($GIT status --porcelain 2>/dev/null | wc -l)
    [ "$D" = "0" ] && ok "工作区 clean" || fail "工作区有 $D 处未提交改动（编译产物可能不是这个 HEAD 出来的）"
else fail "不是 git 仓库，无法证明补丁层"; fi

say "== 3. config"
C=$(sha256sum "$K/.config" 2>/dev/null | cut -d' ' -f1)
[ "$C" = "$CFG_SHA" ] && ok ".config ${C:0:16}…" || fail ".config ${C:0:16}… != 账本 ${CFG_SHA:0:16}…"
R=$(js "d['kernel']['config_in_repo']")
if [ -f "$ROOT/$R" ]; then
    RC=$(sha256sum "$ROOT/$R" | cut -d' ' -f1)
    [ "$RC" = "$CFG_SHA" ] && ok "仓库 $R 与 .config 一致" || fail "仓库 config sha ${RC:0:16}… 与账本不一致"
else fail "仓库里缺 config：$R"; fi

say "== 4. 补丁文本（可重建性）与文件锁"
P=$(js "d['kernel']['combined_patch']['path']")
PS=$(js "d['kernel']['combined_patch']['sha256']")
if [ -f "$ROOT/$P" ]; then
    A=$(sha256sum "$ROOT/$P" | cut -d' ' -f1)
    [ "$A" = "$PS" ] && ok "$P ${A:0:16}…（$(js "d['kernel']['combined_patch']['bytes']") B）" || fail "$P ${A:0:16}… != 账本 ${PS:0:16}…"
else fail "仓库里缺合并补丁：$P（内核补丁层不可重建）"; fi
L=$(js "d['kernel']['files_lock']['path']")
python3 - "$ROOT/$L" "$K" <<'PY'
import hashlib, json, sys, os
lock, tree = sys.argv[1], sys.argv[2]
d = json.load(open(lock))
bad = 0
for e in d["files"]:
    p = os.path.join(tree, e["path"])
    try:
        h = hashlib.sha256(open(p, "rb").read()).hexdigest()
    except FileNotFoundError:
        h = "missing"
    if h != e["sha256"]:
        bad += 1
        if bad <= 5: print(f"  FAIL {e['path']} 被改过（{h[:12]}… != {e['sha256'][:12]}…）")
print(f"  {'OK  ' if bad==0 else 'FAIL'} 文件锁：{len(d['files'])-bad}/{len(d['files'])} 个补丁文件内容符合")
sys.exit(1 if bad else 0)
PY
[ $? = 0 ] || FAIL=1

say "== 5. 产物"
if [ -f "$ART" ]; then
    S=$(stat -c%s "$ART"); A=$(sha256sum "$ART" | cut -d' ' -f1)
    [ "$A" = "$ART_SHA" ] && [ "$S" = "$ART_SIZE" ] && ok "vmlinuz.efi $S B ${A:0:16}…" \
        || fail "vmlinuz.efi $S B ${A:0:16}… != 账本 ${ART_SIZE} B ${ART_SHA:0:16}…（重新编译过？需上机验证后再更新账本）"
else fail "产物不存在：$ART"; fi
for pair in "esp_Image:image" "esp_gaokun3.dtb:dtb" "esp_ramdisk.img:ramdisk"; do
    f=${pair%%:*}; key=${pair##*:}
    p="$ROOT/work/$f"
    [ -f "$p" ] || { say "  --   $f 不在本机，跳过"; continue; }
    a=$(sha256sum "$p" | cut -d' ' -f1)
    e=$(js "d['esp']['$key']['sha256']")
    [ "$a" = "$e" ] && ok "$f ${a:0:16}…" || fail "$f ${a:0:16}… != 账本 ${e:0:16}…"
done

if [ "${REPLAY:-0}" = 1 ]; then
    say "== 6. 重放（REPLAY=1，慢）"
    BASE=$(js "d['kernel']['base_commit']")
    WT=$(mktemp -d)/wt
    if $GIT worktree add --detach "$WT" "$BASE" >/dev/null 2>&1; then
        if git -C "$WT" apply --whitespace=nowarn "$ROOT/$P"; then
            BAD=0
            for f in $(python3 -c "import json,sys;print('\n'.join(e['path'] for e in json.load(open(sys.argv[1]))['files']))" "$ROOT/$L"); do
                cmp -s "$WT/$f" "$K/$f" || { BAD=$((BAD+1)); echo "  FAIL 重放后不一致：$f"; }
            done
            [ "$BAD" = 0 ] && ok "基线 + 合并补丁 可重建当前树的 136 个文件" || FAIL=1
        else fail "合并补丁在基线上打不上"; fi
        $GIT worktree remove --force "$WT" >/dev/null 2>&1
    else fail "建临时 worktree 失败"; fi
fi

say ""
if [ "$FAIL" = 0 ]; then say "BOOT_VERIFY_PASSED"; exit 0; fi
say "BOOT_VERIFY_FAILED"; exit 1
