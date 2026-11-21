# v38 静态策略修正版

日期：2026-11-21

## 目标

不再依赖 USB ADB 或运行日志，先把 HyperOS 已证明、且当前 ColorOS 明确缺失的策略/特性声明静态补齐。

## 变更

### system

- 在 `system/etc/selinux/plat_sepolicy.cil` 追加 9 条规则：
  - `system_server` / `hal_audio_default` ashmem
  - `audioserver` ashmem + prop 读取
  - `untrusted_app` 基础域 ashmem/qemu/proc
- 重新计算 `plat_sepolicy_and_mapping.sha256`：
  - `e721518ad5263ea708edf722ada40dfc0784b5e504ef07ccf5a67718835b1942`

### vendor

- 替换 `precompiled_sepolicy` 为包含新规则的重编译策略：
  - `fd20568ca8fbfc31c6ac083c247d72e7dab33672c079155f5eeb7b97d0d66838`
- 更新 vendor 的三个 precompiled 摘要文件。
- 新增 `etc/permissions/gaokun3-unavailable-features.xml`：
  - `sensor.light`
  - `sensor.compass`
  - `location.gps`
  - `telephony`
  - `telephony.gsm`
  - `telephony.cdma`
  - `telephony.ims`
  - `nfc`
  - `context_hub`
  - `sensor.dynamic.head_tracker`
- XML 标签：`u:object_r:vendor_configs_file:s0`

### odm

- 用当前 ColorOS ODM 完整策略 + gaokun vendor 重新编译 precompiled policy。
- 替换 ODM `precompiled_sepolicy`，并更新三个摘要文件。
- 不删除 ODM 原始 feature XML；由 vendor 的 unavailable-feature 统一覆盖。

## 未改动

- `services.jar` / USB UsbService
- USB ADB / `persist.sys.usb.config`
- light-service
- displayconfig/RRO
- SF idle / GPU min_freq / blur
- OTA / cotad
- `ro.sf.lcd_density` / `ro.zygote` 属性冲突

## 产物

```text
release-coloros-v38/boot.img       sha256 ec30855ece57548950851ccccfb695f169369a2e3d2e2cacca1ebdcda588193b
release-coloros-v38/super.img.zst  sha256 00e917ccb5e74abdf600fe9ca7816109e749dd72541ee7a3ae4f7f802a6477a0

system-v38.erofs                   sha256 3813a078c8556a46ebd988b2265cd2a32553b7e174c76090f4d1389854624c63
vendor_a_v38.img                   sha256 de22b5a165eab4c9ad0a9062e416607c47f01c984ec260ed2c0c825148ca7216
odm_v38.img                        sha256 8ce0d5722ae76a30a6673581581199a535ae7af9227a2482d24dcc604ae7b00b
super-coloros-v38.simg             sha256 a5b590051535ab313455f40ea2aed73494eed4108b138350dce813db9e21a2d2
```

路径：

```text
/home/cenmin/coloros-build/release-coloros-v38
```

## 验证

- `secilc` 编译成功：
  - `types=4809`
  - `allows=125100`
- `checkpolicy` 回读确认目标规则存在，共 9 条相关 allow。
- system `fsck.erofs` 通过。
- vendor `e2fsck` 通过。
- ODM `fsck.erofs` 通过。
- `lpunpack` 从最终 super 反解：
  - `system_a` 与 `system-v38.erofs` 逐字节一致
  - `vendor_a` 与 `vendor_a_v38.img` 逐字节一致
  - `odm_a` 与 `odm_v38.img` 逐字节一致
- `zstd -t` 通过。

## 风险

- 这是静态策略修正，不保证直接到达 `sys.boot_completed=1`。
- 新策略增加了 audioserver/untrusted_app 权限；如果后续恢复 enforcing，仍需按最终策略检查 neverallow。
- 当前 ESP slot A 是 permissive；本次没有改 ESP。
- 本次没有加入任何运行日志采集器。

## 下一步

如果刷 v38 后仍然没有 `gk3-boot-completed-marker`，下一轮应静态处理：

1. `ro.sf.lcd_density` / `ro.zygote` 覆盖冲突；
2. ODM 中仍保留的 binaural/virtual provider VINTF；
3. 可能失败的 ODM OPlus HAL service；
4. 最后再考虑 services.jar USB 和 light-service。

不要重新引入 USB ADB 作为阻塞路径。