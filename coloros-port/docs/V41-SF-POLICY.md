# v41：HyperOS SurfaceFlinger 参数修正

日期：2026-11-21

## v40 实测结论

v40 的 3/10/30 秒快照成功，60 秒因 metadata 写满未完成。

30 秒快照中：

- system_server、zygote、surfaceflinger 都存活；
- sys.boot_completed 仍未写入；
- init.svc.bootanim=stopped；
- sys.power.screenoff.reason=2，PowerManager 日志明确为：

```text
Going to sleep due to timeout
screenOffTimeout=30000
```

因此屏幕熄灭是正常的 30 秒超时，不是 watchdog 立即重启。

真正的异常是显示 surface：

```text
SurfaceFlinger: trackPendingFrame: Invalid present fence
HWUI: drawRenderNode called on a context with no surface!
```

com.coloros.bootreg 和 com.android.systemui 反复因没有有效 surface 而 abort，导致 bootreg/SystemUI 重启，UI 无法真正显示。

## HyperOS 对照

HyperOS 参考实机属性：

```text
debug.sf.enable_hwc_vds=0
debug.sf.latch_unsignaled=1
debug.sf.disable_backpressure=1
debug.sf.set_idle_timer_ms=1000000
debug.sf.set_touch_timer_ms=1000000
debug.sf.enable_frame_rate_override=false
persist.sys.background_blur_supported=false
```

ColorOS v40 当前：

```text
debug.sf.enable_hwc_vds=true
```

这与 mainline drm_hwcomposer 不匹配，是最可疑的直接差异。

## v41 变更

仅新增一组 on post-fs-data 属性，在 SurfaceFlinger 启动前生效：

```text
debug.sf.enable_hwc_vds=0
debug.sf.latch_unsignaled=1
debug.sf.disable_backpressure=1
debug.sf.set_idle_timer_ms=1000000
debug.sf.set_touch_timer_ms=1000000
debug.sf.enable_frame_rate_override=false
persist.sys.background_blur_supported=false
log.tag.drmhwc=E
```

保留：

- v39 Smart Antenna feature 删除；
- v40 3/10/30/60 秒探针；
- v38r3 早期探针；
- v38r2 SELinux policy；
- 其他所有分区。

不修改 services.jar，不修改 IMS，不删除 displaypanel HAL。

## 产物

```text
system-v38.erofs
3813a078c8556a46ebd988b2265cd2a32553b7e174c76090f4d1389854624c63

vendor_a_v41.img
44582d0bb84b5ba42a33d826f1f954b539923d78597570bb3efae20b8397f840

odm_v38.img
8ce0d5722ae76a30a6673581581199a535ae7af9227a2482d24dcc604ae7b00b

my_product_a_v39.img
69dbe55ee04628ab4302b6054574deeda8b6305da02b965f271fe393b3a6e0b3

super-coloros-v41.simg
4ac9d7b4af854a79873a8590e5af5f3ac83b53ac990d1275e36d0998e67c1020

release super.img.zst
4bd033980a08ea4e2863f0550ea53c5d26193c1ddaf0cc09300d350e6360c979

boot.img
ec30855ece57548950851ccccfb695f169369a2e3d2e2cacca1ebdcda588193b
```

## 验证

- 13 个分区逐字节一致；
- zstd -t；
- system、my_product fsck.erofs；
- vendor e2fsck -fn；
- Smart Antenna feature 仍不存在，SELinux xattr 保留；
- v40 探针和 v41 属性均在 vendor rc 中。

## 观察点

如果 v41 修复：

- trackPendingFrame: Invalid present fence 应显著减少或消失；
- bootreg/SystemUI 不再因 drawRenderNode ... no surface 反复 abort；
- 最终应出现 /metadata/gk3-v40-boot-completed 和 sys.boot_completed=1。

如果仍失败，下一步优先检查 vendor.oplus.hardware.displaypanelfeature@1.0 与 AIDL 声明不一致，以及 displaypanel HAL 缺失 libqservice.so 导致的 display 调用异常。