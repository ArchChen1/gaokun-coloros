#!/usr/bin/env python3
"""按现有 super 布局生成 legacy A/B 的两份元数据镜像（A 槽只含 _a，B 槽只含 _b）。

_b 分区的实际起点在超级分区后半段（19660800 扇区起），而 lpmake 总是从 2048
扇区开始顺序分配，所以在 B 槽镜像前面垫一个 pad 分区把起点推到真实位置。
"""
import json
import subprocess
import sys

LAYOUT = "/mnt/e/gk3-coloros/tools/ota/testdata/lp-layout.json"
LPMAKE = "/mnt/e/gk3-coloros/tools/otatools/bin/lpmake"
DEVICE_SIZE = 21474836480
GROUP = "gaokun3_dynamic_partitions"

d = json.load(open(LAYOUT))
parts = d["partitions"]
a = [p for p in parts if p["name"].endswith("_a")]
b = [p for p in parts if p["name"].endswith("_b")]
a.sort(key=lambda p: p["extents"][0]["target_start_sector"])
b.sort(key=lambda p: p["extents"][0]["target_start_sector"])

first_b = b[0]["extents"][0]["target_start_sector"]
pad_bytes = (first_b - 2048) * 512
print(f"A 槽 {len(a)} 个分区，B 槽 {len(b)} 个分区，pad={pad_bytes} B（{first_b} 扇区起）")


def run(out, spec, groups):
    cmd = [LPMAKE, "-d", str(DEVICE_SIZE), "-m", "65536", "-s", "2", "-b", "4096", "-F", "-o", out]
    for g, size in groups:
        cmd += ["-g", f"{g}:{size}"]
    for name, size, group in spec:
        cmd += ["-p", f"{name}:readonly:{size}:{group}"]
    subprocess.run(cmd, check=True)


# A 槽：只要 _a，顺序与真实一致 → extents 与设备上完全相同
run("/tmp/meta_a.img",
    [(p["name"], p["bytes"], GROUP + "_a") for p in a],
    [(GROUP + "_a", sum(p["bytes"] for p in a))])

# B 槽：pad + _b，起点被 pad 推到真实位置
run("/tmp/meta_b.img",
    [("pad", pad_bytes, "pad")] + [(p["name"], p["bytes"], GROUP + "_b") for p in b],
    [(GROUP + "_b", sum(p["bytes"] for p in b)), ("pad", pad_bytes)])

print("已生成 /tmp/meta_a.img /tmp/meta_b.img")
