#!/usr/bin/env bash
# 把 build/export_inputs.sh 的分片上传到 GitHub Release（默认 inputs-v1），供 fetch.sh 拉取。
#
#   GK3_GH_TOKEN=<有 repo 权限的 token> bash build/publish_inputs.sh
#   GK3_SLICES_OUT=/path GK3_INPUTS_TAG=inputs-v1 bash build/publish_inputs.sh
#
# 已存在且大小一致的分片跳过，中断后重跑即可续传。
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/env.sh"

OUT=${GK3_SLICES_OUT:-$HOME/gk3-slices}
SLUG=${GK3_REPO_SLUG:-ArchChen1/gaokun-coloros}
TAG=${GK3_INPUTS_TAG:-inputs-v1}
: "${GK3_GH_TOKEN:?需要 GK3_GH_TOKEN（对 $SLUG 有 repo 权限）}"
API=https://api.github.com
UP=https://uploads.github.com
AUTH="Authorization: Bearer $GK3_GH_TOKEN"
ACCEPT='Accept: application/vnd.github+json'

# 子命令：id（release id）、assets（列出）、size <name>、id_of <name>、size-or-msg（上传响应）
py() { python3 -c "$1" "${@:2}"; }

release_id() { py 'import json,sys; d=json.load(sys.stdin); print(d.get("id") or "")'; }

list_assets() {
  curl -sS -H "$AUTH" -H "$ACCEPT" "$API/repos/$SLUG/releases/$1/assets?per_page=100" \
    | py 'import json,sys
for a in json.load(sys.stdin): print("  %-34s %12d" % (a["name"], a["size"]))'
}

asset_size() {  # <name>
  py 'import json,sys
for a in json.load(sys.stdin):
    if a["name"] == sys.argv[1]:
        print(a["size"]); raise SystemExit
print("")' "$1"
}

asset_id() {  # <name>
  py 'import json,sys
for a in json.load(sys.stdin):
    if a["name"] == sys.argv[1]:
        print(a["id"]); raise SystemExit
print("")' "$1"
}

upload_result() {
  py 'import json,sys
d = json.load(sys.stdin)
print("  -> %s" % (d.get("size") if d.get("size") is not None else d.get("message", "")))'
}

echo "== Release $TAG（$SLUG）"
rid=$(curl -sS -H "$AUTH" -H "$ACCEPT" "$API/repos/$SLUG/releases/tags/$TAG" | release_id || true)
if [ -z "${rid:-}" ]; then
  echo "  新建 Release $TAG"
  rid=$(curl -sS -X POST -H "$AUTH" -H "$ACCEPT" "$API/repos/$SLUG/releases" \
    -d "{\"tag_name\":\"$TAG\",\"name\":\"构建输入 $TAG\",\"draft\":false,\"prerelease\":true,\"body\":\"构建输入分片（$TAG）。由 build/export_inputs.sh 生成、build/fetch.sh 消费；清单见 inputs/targets.txt 与 inputs/slices.txt。\"}" \
    | release_id)
fi
echo "  release id=$rid"

echo '== 已有资产'
list_assets "$rid"

echo '== 上传分片'
n=0; s=0
for f in "$OUT"/*.part*; do
  [ -s "$f" ] || continue
  name=$(basename "$f"); size=$(stat -c%s "$f")
  assets_json=$(curl -sS -H "$AUTH" -H "$ACCEPT" "$API/repos/$SLUG/releases/$rid/assets?per_page=100")
  have=$(printf '%s' "$assets_json" | asset_size "$name")
  if [ -n "${have:-}" ]; then
    if [ "$have" = "$size" ]; then echo "  跳过 $name（已存在，$size B）"; s=$((s+1)); continue; fi
    echo "  大小不符 $name（远端 $have），删除重传"
    aid=$(printf '%s' "$assets_json" | asset_id "$name")
    curl -sS -X DELETE -H "$AUTH" -H "$ACCEPT" "$API/repos/$SLUG/releases/assets/$aid" >/dev/null || true
  fi
  echo "  ↑ $name（$((size/1024/1024)) MiB）"
  # --data-binary @file 会把整块读进内存（1.9 GB 直接 OOM），-T 流式上传
  curl -sS --fail --retry 3 --retry-delay 5 --max-time 7200 \
    -X POST -H "$AUTH" -H 'Content-Type: application/octet-stream' -H "$ACCEPT" \
    -T "$f" "$UP/repos/$SLUG/releases/$rid/assets?name=$name" | upload_result
  n=$((n+1))
done

echo "完成：上传 $n，跳过 $s"
echo "前缀：https://github.com/$SLUG/releases/download/$TAG"
echo PUBLISH_OK
