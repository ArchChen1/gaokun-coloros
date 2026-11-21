# v38r2 策略隔离版

日期：2026-11-21

## 背景

v38 刷入后没有进入 boot animation，停在跑码循环，但 metadata 仍写入了：

- `gk3-init-write-test`
- `gk3-boot-write-test`

说明 init 至少执行到了 `on boot`，问题发生在更后面的 framework/system_server 或某个早期服务崩溃/重启。

v38 同时引入了两个独立变量：

1. SELinux policy 追加规则；
2. vendor `gaokun3-unavailable-features.xml`。

v38r2 用于隔离这两个变量。

## v38r2 变更

- 保留 v38 的 system/vendor/ODM precompiled policy 修改；
- 从 vendor 移除 `gaokun3-unavailable-features.xml`；
- 其余与 v38 相同；
- boot.img 不变。

## 产物

```text
release-coloros-v38r2/boot.img       sha256 ec30855ece57548950851ccccfb695f169369a2e3d2e2cacca1ebdcda588193b
release-coloros-v38r2/super.img.zst  sha256 faf2de16ddad7b31368a2028e9a6353d6ba37df763ef27fbf7c48268ce019815

system-v38.erofs                     sha256 3813a078c8556a46ebd988b2265cd2a32553b7e174c76090f4d1389854624c63
vendor_a_v38r2.img                   sha256 b2ea02352bc338208ab20ec0d911ab25fde519e3c47cba9575fee530bda3ddbd
odm_v38.img                          sha256 8ce0d5722ae76a30a6673581581199a535ae7af9227a2482d24dcc604ae7b00b
super-coloros-v38r2.simg             sha256 643f7f784f3f58129153e84905e9818249b2ec90e2cb191ac7f3ab8dc8595013
```

## 验证

- `lpunpack` 反解 super，system/vendor/ODM 与输入逐字节一致；
- vendor `e2fsck` 通过；
- `zstd -t` 通过。

## 用途

- 如果 v38r2 能进入动画：问题来自 v38 新增的 unavailable-feature XML；
- 如果 v38r2 仍然跑码循环：问题更可能来自 v38 的 policy 修改，下一步应回退到 v37 并只做单一 policy 项。