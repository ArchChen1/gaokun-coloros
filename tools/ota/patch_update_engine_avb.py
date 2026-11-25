#!/usr/bin/env python3
"""给 gaokun3 的 /system/bin/update_engine 打 3 字节补丁：跳过 system_other 的 AVB footer 擦除。

背景：本机没有 system_other 分区，也没有它的 AVB 信息。update_engine 在
DynamicPartitionControlAndroid::EraseSystemOtherAvbFooter() 里必然失败，链式报
  has_avb.has_value() failed
  → GetSystemOtherPath failed
  → EraseSystemOtherAvbFooter failed
  → Unable to initialize partition metadata for slot B
  → kInstallDeviceOpenError (7)
这个失败发生在任何分区写入和快照创建之前，所以不跳过它，OTA 一步都走不了。

补丁位置是函数入口的判断：
  0xe9500: tbz w0,#0,0xe955c   (e0 02 00 36)
改成：
  0xe9500: b 0xe9504           (01 00 00 14)
即"无条件视为成功"。

只对 md5 = a8096f37aab6d1abd570bb58b6e2552b 的原厂二进制生效；打完的 md5 应为
dc757f0a91d74cb340310c27fba8d564（与上一轮实验目录里的 update_engine_patched.bin 一致）。
幂等：已打过就跳过。

用法：
  python3 tools/ota/patch_update_engine_avb.py /home/cenmin/v50-build/system/system/bin/update_engine
"""
import hashlib
import sys

STOCK_MD5 = "a8096f37aab6d1abd570bb58b6e2552b"
PATCHED_MD5 = "dc757f0a91d74cb340310c27fba8d564"
OFFSET = 0xE9500
ORIG = bytes([0xE0, 0x02, 0x00, 0x36])
PATCH = bytes([0x01, 0x00, 0x00, 0x14])


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    path = sys.argv[1]
    cur = md5(path)
    if cur == PATCHED_MD5:
        print("已打过补丁，跳过")
        return
    if cur != STOCK_MD5:
        raise SystemExit(f"md5 不是原厂二进制：{cur}（期望 {STOCK_MD5}），拒绝改")

    with open(path, "r+b") as f:
        f.seek(OFFSET)
        got = f.read(4)
        if got != ORIG:
            raise SystemExit(f"0x{OFFSET:x} 处字节不是预期：{got.hex()}")
        f.seek(OFFSET)
        f.write(PATCH)

    new = md5(path)
    if new != PATCHED_MD5:
        raise SystemExit(f"打完后 md5 不符：{new}（期望 {PATCHED_MD5}）")
    print(f"已打补丁：{path}  md5 {STOCK_MD5} -> {PATCHED_MD5}")


if __name__ == "__main__":
    main()
