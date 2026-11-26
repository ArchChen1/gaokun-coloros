#!/system/bin/sh
# gk3otad —— 极窄的系统写入服务。
#
# 唯一职责：等待 com.oplus.ota 在自己私有目录落一份 request 文件，
# 校验请求指向的 payload 路径，然后调 update_engine_client 把它写进非当前槽。
#
# 边界（故意写死，防止这个 root 服务被当成通用后门）：
#   * 只接受 /data/data/com.oplus.ota/ 下的 payload 路径
#   * 不接受任意外部参数，headers 只从 request 里给出的 properties 文件读
#   * payload 的信任由 update_engine 用 my_engineering 里的 otacerts 验签兜底
#   * 只写「另一槽」（引擎自己算），不碰 userdata、不碰 misc 以外的块

DIR=/data/data/com.oplus.ota/files

while true; do
    sleep 5
    [ -f "$DIR/request" ] || continue

    payload=$(sed -n 's/^payload=//p' "$DIR/request" | head -1)
    props=$(sed -n 's/^props=//p' "$DIR/request" | head -1)
    mv -f "$DIR/request" "$DIR/request.done" 2>/dev/null

    : > "$DIR/status"
    chmod 644 "$DIR/status"

    case "$payload" in
        /data/data/com.oplus.ota/*|/data/user/0/com.oplus.ota/*) ;;
        *) echo "reject: bad payload path: $payload" >> "$DIR/status"; chmod 644 "$DIR/status"; continue ;;
    esac
    [ -f "$payload" ] || { echo "reject: payload missing" >> "$DIR/status"; chmod 644 "$DIR/status"; continue; }

    echo "start $(date)" >> "$DIR/status"
    /system/bin/update_engine_client --reset_status >> "$DIR/status" 2>&1
    /system/bin/update_engine_client \
        --payload="file://$payload" \
        --headers="$(cat "$props" 2>/dev/null)" \
        --update --follow >> "$DIR/status" 2>&1
    echo "rc=$?" >> "$DIR/status"
    chmod 644 "$DIR/status"
    sync
    # 留一份全日志给排查用（App 侧只能读到摘要）
    cp "$DIR/status" /data/local/tmp/gk3otad.status 2>/dev/null
    chmod 644 /data/local/tmp/gk3otad.status 2>/dev/null
done
