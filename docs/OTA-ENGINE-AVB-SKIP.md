# OTA 卡点：EraseSystemOtherAvbFooter（kInstallDeviceOpenError 7）

## 现象

自签 payload 的签名关通过后，安装立刻失败：

```
Erasing AVB footer of system_other partition before update.
Cannot get ro.postinstall.fstab.prefix
has_avb.has_value() failed
GetSystemOtherPath failed
EraseSystemOtherAvbFooter failed
Unable to initialize partition metadata for slot B
Failed to parse manifest
kInstallDeviceOpenError (7)
```

## 机制

`update_engine` 在准备目标槽的 partition metadata 时，**无条件**先擦 `system_other` 的 AVB footer：

1. 需要 `ro.postinstall.fstab.prefix` 找到 postinstall 的 fstab；
2. 再从该 fstab 里找 `system_other` 条目并读它的 AVB 信息；
3. 本机既没有 `system_other` 分区，super 里也没有它的 AVB 描述，`has_avb` 必然为空，函数返回失败；
4. 这个失败发生在**任何分区写入和快照创建之前**，所以不解决它，OTA 一步都走不了。

注意它跟 payload 内容无关：本轮 payload 只含 `my_region`，照样触发。

## 解法：给 update_engine 打 3 字节补丁

函数入口那段判断改成无条件跳转（视作成功）：

| 文件偏移 | 原字节 | 补丁后 | 原指令 | 新指令 |
|---|---|---|---|---|
| `0xe9500` | `e0 02 00 36` | `01 00 00 14` | `tbz w0,#0,0xe955c` | `b 0xe9504` |

- 原厂二进制 md5 `a8096f37aab6d1abd570bb58b6e2552b`（2,815,560 B）
- 补丁后 md5 `dc757f0a91d74cb340310c27fba8d564`
- 补丁脚本：`tools/ota/patch_update_engine_avb.py`（校验输入 md5、校验输出 md5、幂等）
- 上一轮是拿补丁版二进制 + KernelSU 模块 bind mount 过去的（那时还没去 root）；现在 `update_engine` 在 system 里，只能打进镜像。

## 打回镜像的流程

1. `build/rebuild_system_patched.sh`（WSL，需要 `wsl -u root`，mkfs.erofs 在开发机上被硬拦截，只能本地跑）
2. 金丝雀：先用当前树原样重打，与 `parts/system.erofs` 逐字节 `cmp`；**只允许**超级块区（偏移 ≤ 1280）有差异（`build_time` 每次都会变，校验和随它变，UUID 早期是随机生成的）。超级块之外有任何差异 → 停。
3. 打补丁 → 重打 → 截齐到分区长度 → `fsck.erofs` clean → 再解包校验镜像内 `update_engine` 的 md5 是 `dc757f0a…`。
4. `tools/raw_extent_write.ps1 -Sector 2048 -Bytes 1137397760` 原位写回 `system_a`（先 dry run 备份并比对备份 sha 与基座一致，再 `-Write`，写完按 1 MB 分块回读比对）。

## 已验证的事实

- 基座 `parts/system.erofs` 解包后与 `v50-build/system` 树**内容 0 差异**（1.6 GB，含符号链接），所以改镜像只需接受超级块时间戳/校验和不同。
- 基座 `system.erofs` 的 UUID 是 `383ec563-55d9-48b8-bf8b-5dea81dc2a3b`（早期未固定 UUID 的产物）；`build/current_build.sh` 现在固定为 `4f3a1b2c-5d6e-4f70-8a91-b2c3d4e5f601`。UUID 不参与挂载（系统盘按 dm 设备路径挂），重打按流水线的固定值走。
- 候选镜像 `work/system_patched.erofs`：1,137,397,760 B（= `system_a` 分区长度），sha256 `80934a5fdebed67cd3099cb37f4b5ecc07e1781449ed7d07f179353c97459985`。

## 待验证

写回后重跑 `region_snap.bin` 小快照包，确认能过 `kInstallDeviceOpenError (7)`，进入真正的快照创建/写入阶段。
