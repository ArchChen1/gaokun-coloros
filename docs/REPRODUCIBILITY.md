# 可复现性现状

目标：同一份输入（`inputs/targets.txt` 里的 13 个目标）在任何机器上产出**同一份** `super.img`。
现在的结论是：**内容等价、字节不等价**。下面是实测数据与原因，别把它当成已完成。

## 实测（2026-11-24，GitHub `ubuntu-24.04` 运行器）

| 运行 | 条件 | super.img bytes | sha256 |
|---|---|---|---|
| 本机 v54 | `mkfs.erofs` 1.9.4（本机装的那份），随机 UUID | 9,833,219,624 | `a3d0d0f3…6b0b` |
| system #6 | 运行器自带 `mkfs.erofs` 1.7.1 | 9,833,445,028 | `d3a59031…85e8` |
| system #8 | 钉版 1.9.4，随机 UUID | 9,833,264,776 | `3acd3336…cbfb` |
| system #9 | 与 #8 完全同一个提交，重跑 | 9,833,?（未记） | `e424f54c…102b` |
| system #10 | 钉版 1.9.4 + `-U` 固定 UUID | 20 GiB / `SPARSE_OK` | `8f699558…fcfd` |

三次都通过了全部断言（13 条），sparse 头一致（v1.0、blk 4096、展开 20 GiB）。差别只在字节。

## 三个不确定来源

1. **erofs 版本**（已消除）：运行器自带 1.7.1，与本机 1.9.4 差几百 KB。现在 `build/deps.sh` 从仓库内的
   `tools/toolchain/erofs-utils-v1.9.4.tar.gz`（sha `ab97e155…3918`）自己编，装到
   `$GK3_WORKDIR/toolchain/erofs-install`，`build/env.sh` 优先用它。
2. **`mkfs.erofs` 的 UUID**（已消除）：默认每次随机生成，写进 superblock。现在 `current_build.sh` 传固定
   `-U`（system `4f3a1b2c-5d6e-4f70-8a91-b2c3d4e5f601`、odm `…f602`）。#9 → #10 的差别就是这一项。
3. **vendor 分区用 loop 挂载打补丁**（未消除，主因）：`current_build.sh` 第 1 步 `mount -o loop,rw` 改
   `init.gaokun3.rc`、给 `v29_usb_capture.sh` 设 SELinux 标签，inode 的 mtime/ctime 变成当次构建时间。
   实测：同一份基座、同一个补丁打两次，sha 分别是 `03c42dc1…902e` 与 `c595e6ba…1e24`——**必然不同**。
   ext4 的 ctime 无法用 `touch` 伪造，只能离线改。

另外：解包树顺序。tar 用 `--sort=name` 打包，CI 两次解包顺序一致；但与本机历史树的顺序不同，
导致 lz4 分块边界不同、体积略有差异。这一项只影响“与本机旧产物对比”，不影响 CI 自身一致性。

## 要做到字节一致，需要做的

把 vendor 补丁从“挂载后改”换成“离线改”，全部走 `debugfs -w`：

```bash
cp base.img vendor.img
# 写文件：先 rm 掉旧 inode，再 write 新文件
debugfs -w -R "rm /etc/init/hw/init.gaokun3.rc" vendor.img
debugfs -w -R "write patched.rc /etc/init/hw/init.gaokun3.rc" vendor.img
# 时间戳固定（sif 能改 atime/mtime/ctime，mount 改不了 ctime）
debugfs -w -R "sif /etc/init/hw/init.gaokun3.rc ctime 1577836800" vendor.img
debugfs -w -R "sif /etc/init/hw/init.gaokun3.rc mtime 1577836800" vendor.img
# SELinux 标签（ea_set）
debugfs -w -R "ea_set /bin/v29_usb_capture.sh security.selinux u:object_r:gaokun3_wlanap_exec:s0" vendor.img
```

风险：改的是要刷进设备的分区，写坏了会起不来。校验链要保留：`e2fsck -fn`、只读挂载核对文件内容与标签、
以及 `current_verify.sh` 里那 5 条 vendor 断言。做之前先在 v54 产物上对比“补丁后 vendor 的文件级差异”
（只允许 rc 内容与 v29 标签变化），确认 debugfs 改出来的镜像与原镜像文件级等价。

优先级：低于 OTA 主线。当前“拉取就能编译”已经成立，字节一致属于发行质量项，不是阻塞项。
