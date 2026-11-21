# v42：SurfaceFlinger 不再等待缺失的 OPPO display HAL

日期：2026-11-21

## 依据

v41 的 SurfaceFlinger 参数已生效：

    debug.sf.enable_hwc_vds=0
    debug.sf.latch_unsignaled=1
    debug.sf.disable_backpressure=1

但 v41 实测仍然黑屏，错误数量没有明显下降：

    SurfaceFlinger: trackPendingFrame: Invalid present fence
    HWUI: drawRenderNode called on a context with no surface!

因此问题不在参数，而在 ColorOS SurfaceFlinger 本身。

## 参考实现

analysis/pipa-cos17-port 的 ColorOS 17 移植记录明确写：

- ColorOS SurfaceFlinger 会同步等待缺失的 OPPO display HAL；
- 具体接口包括 vendor.oplus.hardware.display.MixLut3D.IMixLut3D、IDisplayColorFeature 和 Pixelworks IIris；
- 等待会导致 SurfaceFlinger 主线程卡住；
- 项目用 patch_sf_waits.py 把 4 个 AServiceManager_waitForService 调用改成 checkService，后续代码已处理 null binder。

该脚本在当前 ColorOS donor 的 surfaceflinger 上实测匹配：

    patched 4 waitForService -> checkService sites
    (0x3c6f70, 0x3d22b8, 0x3ffedc, 0x42e2d0)

## v42 变更

- 只替换 system/bin/surfaceflinger；
- 使用原地覆盖，保留：
  - mode 0755
  - uid 0
  - gid 2000
  - security.selinux=u:object_r:surfaceflinger_exec:s0
- 其余 system 文件、vendor、ODM、my_product、boot 不变；
- 保留 v41 SurfaceFlinger 参数；
- 保留 v40 3/10/30/60 秒探针。

## 产物

    system-v42.erofs
    661ec01212399ade99b2e7db9374e9d12961304748491c1529fbc67d589e50d1

    patched surfaceflinger
    44482c704adf3f661f688695a37655150bc8c4851b360a06f0ffb03beb73dcac

    vendor_a_v41.img
    44582d0bb84b5ba42a33d826f1f954b539923d78597570bb3efae20b8397f840

    odm_v38.img
    8ce0d5722ae76a30a6673581581199a535ae7af9227a2482d24dcc604ae7b00b

    my_product_a_v39.img
    69dbe55ee04628ab4302b6054574deeda8b6305da02b965f271fe393b3a6e0b3

    super-coloros-v42.simg
    af5adb39ead4986053650a236190087fe8369c5cfea666796ad4aa834dca0556

    release super.img.zst
    c03cb537730dcb2c05fbcb1e28abc78cf0588e1f56a22ec8637cafae5cc92791

    boot.img
    ec30855ece57548950851ccccfb695f169369a2e3d2e2cacca1ebdcda588193b

## 验证

- 13 个分区逐字节一致；
- zstd -t；
- system、my_product fsck.erofs；
- vendor e2fsck -fn；
- system 内 surfaceflinger 与补丁文件哈希一致；
- surfaceflinger 的 SELinux xattr、uid/gid/mode 保留。

## 预期

如果 pipa 记录的等待问题在本机同样成立：

- trackPendingFrame: Invalid present fence 应减少或消失；
- bootreg/SystemUI 的 drawRenderNode ... no surface 应停止；
- 应出现 sys.boot_completed=1 和 /metadata/gk3-v40-boot-completed。

如果仍失败，再检查 displaypanelfeature 的 HIDL/AIDL 不一致和 displaypanel HAL 缺失 libqservice.so。