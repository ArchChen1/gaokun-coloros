# v39 结果与 v40 后启动阶段探针

日期：2026-11-21

## v39 实测结果

v39 后：

- 开机动画可以正常跑到 100%；
- 不再出现 `OplusWifiStbcMrcSolution.handleBootCompleted()` 空指针；
- `system_server` 没有再次因该 OPlus Wi‑Fi 路径崩溃；
- 但 `sys.boot_completed` 仍未写入；
- 到 100% 后黑屏，随后自动重启；第二次启动同样现象。

v39 metadata 中：

- `gk3-v38r3-zygote-trigger` 存在；
- `gk3-v38r3-bootanim-trigger` 存在；
- `/gk3-v38r3/` 日志存在；
- 没有 `gk3-v38r3-boot-completed`。

## 已确认阶段

v39 日志显示：

```text
boot_progress_ams_ready
boot_progress_enable_screen
ActivityManager: bootAnimationComplete, mCallFinishBooting = true
ActivityManagerTiming: FinishBooting
ActivityManagerTiming: OnBootPhase_1000_...
SystemService.PHASE_BOOT_COMPLETED
```

说明 framework 已经进入 finishBooting / PHASE_BOOT_COMPLETED，但尚未完成到设置 `sys.boot_completed=1`。

剩余崩溃仍包括：

- `com.qti.phone` 的 IMS 初始化数组越界；
- `com.android.phone` 的 CarrierConfig 空指针；
- `com.coloros.bootreg` / `com.android.systemui` 的 `drawRenderNode called on a context with no surface!`；
- radio VINTF 缺少 `android.hardware.radio.*` slot1/slot2 实例。

## v40 变更

业务镜像不变，只扩展一次性探针：

- 保留 v39 的 Smart Antenna feature 删除；
- 保留 v38r3 早期 zygote 探针；
- 在 `init.svc.bootanim=stopped` 后增加 3/10/30/60 秒快照；
- 不新增常驻 service；
- 不新增轮询；
- 不修改 system、my_product、ODM、boot。

新增输出：

```text
/metadata/gk3-v40-bootanim-trigger
/metadata/gk3-v40/postboot-10-*
/metadata/gk3-v40/postboot-30-*
/metadata/gk3-v40/postboot-60-*
/metadata/gk3-v40-boot-completed
```

每个快照抓取：

- `getprop`
- `ps -A`
- `/proc/1/status`
- `/proc/mounts`
- `dmesg`
- `logcat -b all`
- `logcat -b crash`
- tombstone/ANR/dropbox 目录
- 可用的 `/proc/last_kmsg` / pstore

## 产物

```text
system-v38.erofs
3813a078c8556a46ebd988b2265cd2a32553b7e174c76090f4d1389854624c63

vendor_a_v40.img
bec67d91d9878bf2d2e2e11bb38bc46b5a811d44890745e49d9983ed365c9bd1

odm_v38.img
8ce0d5722ae76a30a6673581581199a535ae7af9227a2482d24dcc604ae7b00b

my_product_a_v39.img
69dbe55ee04628ab4302b6054574deeda8b6305da02b965f271fe393b3a6e0b3

super-coloros-v40.simg
b3cba32bcd8e6d3822aba1057842f9b673e875b6161d235dbcbd9c0cd7c32599

release super.img.zst
fb1f236853c499eaba23d205c2d4ead36e45606a6db7ceb4f53db505ed51d184

boot.img
ec30855ece57548950851ccccfb695f169369a2e3d2e2cacca1ebdcda588193b
```

## 验证

- 13 个分区逐字节一致；
- `zstd -t`；
- system、my_product `fsck.erofs`；
- vendor `e2fsck -fn`；
- feature XML SELinux xattr 保留；
- v40 探针权限 `0755 root:root`。