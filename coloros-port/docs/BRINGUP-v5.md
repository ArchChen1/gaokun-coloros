# ColorOS 移植调试记录（v3 → v5）

本文记录 gaokun3（MateBook E Go，SC8280XP）移植 OnePlus/ColorOS 17 的启动失败排查过程。
所有结论都来自 Ego 实机的 `metadata` 分区日志（`/gk3-debug/`）与镜像静态分析。

## 诊断基础设施

- 采集脚本：[`gk3-capture-metadata.sh`](gk3-capture-metadata.sh)（v4，有 bug）、[`gk3-capture-v5.sh`](gk3-capture-v5.sh)（v5，已修复）
- 日志落盘：`/metadata/gk3-debug/{kmsg.log, logcat.txt, snapshot.txt}`
- 离线读取：`gk3w.exe readpart --disk 0 --name metadata --out <img>` →
  `e2fsck -fy` 副本 → `debugfs -R "rdump /gk3-debug <dir>"`

采集服务的坑（v4 踩过，务必避免）：

1. 脚本必须 **LF 换行**。混入一个 `\r` 会让最后一行变成 `wait\r`，
   `sh` 找不到命令 → 服务以 `status 127` 退出，`logcat.txt` / `snapshot.txt` 全空。
   实测：`[119.912630] init: Service 'gk3-capture' (pid 2255) exited with status 127`。
2. 不要在每次启动时 `rm -f` 掉上一轮日志，否则重启后什么也查不到。
3. 内核日志要周期性 `dmesg > tmp && mv`，不要 `cat /dev/kmsg` 常连——
   UCSI 每 0.2 s 一行，32 MiB 的 metadata 很快被刷满。
4. 采集服务自身跑在 permissive 诊断域会刷出大量 `avc: denied ... permissive=1`。
   **那些不是启动失败原因**：本次 282 条 AVC 全部来自采集服务自身。
   真正的阻塞只会以 `permissive=0` 出现（本次为 0 条）。

## v3：zygote 崩溃循环（已修）

```
F MediaProfiles: frameworks/av/media/libmedia/MediaProfiles.cpp:1614 CHECK((fp = fopen(xml, "r"))) failed.
  at android.media.CamcorderProfile.native_init
  at com.android.internal.os.ZygoteInit.preloadClasses
F libc: Fatal signal 6 (SIGABRT)
```

根因：ColorOS 的 `system/build.prop` 指定 `media.settings.xml=/vendor/etc/media_profiles_vendor.xml`，
而 gaokun vendor 没有该文件。zygote 预加载 `CamcorderProfile` 时打不开 → abort → 无限重启。

修复（v4c）：在 vendor 补上 `/vendor/etc/media_profiles_vendor.xml`。

验证：v4c 实机日志里 `zygote` 与 `system_server`（pid 1373）能正常起来，
MediaProfiles 不再出现 —— **该修复确认有效**。

## v4c：SurfaceFlinger 起不来（已定位，v5 修）

`system_server` 从 117 s 开始每秒刷：

```
servicemanager: Caller(pid=1373,...u:r:system_server:s0) Since 'SurfaceFlingerAIDL'
  could not be found trying to start it as a lazy AIDL service.
init: Control message: Could not find 'aidl/SurfaceFlingerAIDL' for ctl.interface_start
```

对照 v3 完整 logcat（那次采集成功），SurfaceFlinger 走到：

```
I SurfaceFlinger: SurfaceFlinger's main thread ready to run. Initializing graphics H/W...
D SurfaceFlinger: Threaded RenderEngine with SkiaGL Backend (Ganesh)
```

之后**再无任何输出** —— 卡死在图形硬件（EGL/驱动）初始化里，永远不注册 `SurfaceFlingerAIDL`。

### 根因：ColorOS 的 system 图形栈是给高通 KGSL 编的

ColorOS 与 crDroid（gaokun3）的 system **是同一个 QSSI 构建**
（`ro.build.display.id` 均为 `CP2A.260605.016`、SDK 37、release 17），
但图形库不同：

| 库 | ColorOS | crDroid (gaokun3) |
|---|---|---|
| `libEGL.so` | 250464 B | 270576 B |
| `libEGL_angle.so` | 730096 B | 779200 B |
| `libGLESv2_angle.so` | 6302336 B | 6502912 B |
| `libvulkan.so` | 254264 B | 274696 B |

决定性证据 —— ColorOS 版 `libEGL.so` 含：

```
/dev/kgsl-3d0
/sys/class/kgsl/kgsl-3d0/gpu_model
%s: GPU fs node not ready, retry %d/%d
%s: GPU fs node timeout after 30 seconds!
```

这是**高通 KGSL 专用**逻辑。gaokun3 用 mainline DRM（`/dev/dri/card*`），
内核里没有 kgsl 节点，所以这个等待会一路超时/卡住。
crDroid 版 `libEGL.so` **完全没有 kgsl 引用**，是为本机编译的正确版本。

两侧 `libEGL.so` 的导出符号集合完全一致（124 defined / 0 diff），
只是编译目标不同 —— 替换是安全同源的。

同一台机器的另一个移植项目（GitZhaoo/matebookego_hyperos）也记录了同样的结论：
本机 vendor 没有原生 GLES 驱动（`/vendor/lib64/egl/` 不存在），
渲染只有 `ANGLE → Vulkan → freedreno(turnip)` 一条路，
`persist.graphics.egl=angle` 是唯一可行配置。

### 修复（v5）：把 ColorOS 的图形栈换成 crDroid(gaokun3) 版

替换 `/system/{lib,lib64}/` 下 9 个库（共 18 个文件）：

```
libEGL.so  libGLESv1_CM.so  libGLESv2.so  libGLESv3.so
libEGL_angle.so  libGLESv1_CM_angle.so  libGLESv2_angle.so
libvulkan.so  libegl_flags.so
```

`system` 是 EROFS，流程：挂载 → `rsync -aHAX` 到工作目录（保 xattr/SELinux 标签）
→ 替换库 → `mkfs.erofs -zlz4 -b4096 -C65536` 重打包（保持原 UUID）
→ 验证 `security.selinux=u:object_r:system_lib_file:s0` 标签仍在。

其余 11 个分区逐字节复用 v4c（与 v3 一致），只换 `system_a` 与 `vendor_a`。

## v5 产物

```
boot.img        32,069,632 B   sha256 ec30855ece57548950851ccccfb695f169369a2e3d2e2cacca1ebdcda588193b
super.img.zst   9,383,360,842 B sha256 7ef3bfce682a024e18cb869bf030c0c9e9446a808f269ac3e9f178de3c38dfb5
```

- system_a sha256 `26e558ac927f31cb758ccbdf210e577f016a4089f0ad6eb976005bbd6faf91ee`
- vendor_a sha256 `460462118d3f13d5effcb14c03506c8f0cedf0b3d8e0cbca8fade88e25808944`
- 11 个未改分区与 v4c 逐字节一致
- 分区组占用 11,209,416,704 B / 12,683,575,296 B（余 1405.9 MiB）

## 排查顺序建议（下次少走弯路）

1. 先确认 `metadata` 里到底有没有 v5 采集服务的输出；空文件先查服务有没有以 127 退出。
2. 看 `getprop init.svc.surfaceflinger` 与 logcat 里 `surfaceflinger` 最后一行到哪。
3. 只要出现 `Could not find 'aidl/SurfaceFlingerAIDL'`，就是图形栈没起来，
   先查 `libEGL` 的驱动兼容性，不要去查 zygote。
4. AVC 日志先过滤 `permissive=0`；`permissive=1` 的行几乎都是诊断域噪音。

## 尚未处理（已知，非当前阻塞）

- ESP 启动项在 `permissive` 模式，SELinux 规则补齐后应恢复 `enforcing`。
  `gaokun3_smmustall` 域缺 fork/getsched/proc 权限（当前靠 permissive 放行）。
- ODM 下多个 OPlus 服务启动即退出（`status 1`）：`displaypanelfeature-service`、
  `vendor.camera-provider-gaokun3`、`oplus.performance.hal` 等，需逐个查缺失依赖。
- UCSI 每 0.2 s 刷屏（`ucsi connector is not initialized yet`），是噪音但会挤占内核日志。
---

# v5b：修复 `mkfs.erofs --all-root` 导致的 logd 崩溃

## 现象

v5 刷入后实机：

- `permissive` 生效后 `/metadata/gk3-debug/` 能创建，
  `kmsg.log` 530,536 B 有内容，但 `logcat.txt` **0 字节**。
- `snapshot.txt` 显示 `surfaceflinger`、`vendor.hwcomposer-3`、`zygote` 都是 `running`。
- `kmsg.log` 里每 5 秒一条：

```
init: cannot execv('/system/bin/logd'). See the 'Debugging init' section of init's README.md for tips: Permission denied
init: Service 'logd' (pid 1765) exited with status 127
init: process with updatable components 'logd' exited 4 times before boot completed
```

对照 v3（只改 vendor、system 未重打包）的采集：logd 正常，
`logcat.txt` 3,271,680 B，大量 `logd: logdr: UID=0 GID=0 PID=...` 正常服务记录。
→ **这是 v5 独有的回归，不是移植本身的移植性问题。**

## 根因

`v5_build_system_erofs.sh` 重打包 system 时用了：

```
mkfs.erofs ... --all-root ...
```

`--all-root` 把镜像内 **所有文件属主强制改成 root:root**，破坏了原始 uid/gid 模型。
对比同一路径：

| 文件 | 原始 ColorOS system.img | v5 出厂 system_a.img |
|---|---|---|
| `/system/bin/logd` | `uid=1036 gid=1036 mode=0550` | `uid=0 gid=0 mode=0550` |
| `/system/bin/surfaceflinger` | `uid=0 gid=2000 mode=0755` | `uid=0 gid=0 mode=0755` |
| `/system/bin/init` | `uid=0 gid=2000 mode=0755` | `uid=0 gid=0 mode=0755` |

Android init 启动这类服务是 **fork → setuid(1036) → execve**。
原本 `0550 logd:logd` 时，uid 1036 是属主，可读可执行；
`--all-root` 后变成 `0550 root:root`，uid 1036 既非属主、gid 1036 也不在组 0，
other 位 `---` → `EACCES`，init 报 "Permission denied"，服务以 127 退出。

`logd` 挂掉 → `/dev/socket/logd*` 无人服务 → `logcat` 写不进文件 → `logcat.txt` 为 0 字节。
其它以非 root uid 启动的服务（`pogokey_board`、`vendor.touch-aidl-1` 等）同样受影响。

## 修复

重打包时**去掉 `--all-root`**，以 root 身份执行 `mkfs.erofs` 并保留源树属主。
构建树由 `rsync -aHAX --numeric-ids` 从原镜像解出，属主本来就是正确的，
所以只需换打包命令，不需要重新解包。

已在 `v5_build_system_erofs.sh` 中：

1. 删除 `--all-root`；
2. 增加前置守卫：若 `bin/logd` 属主为 0 直接 `FATAL` 退出，防止回归。

## 验证

重新打包后对出厂 `system_a` 直接 `dump.erofs`：

```
/system/bin/logd            Uid: 1036   Gid: 1036  Access: 0550
/system/bin/surfaceflinger  Uid: 0      Gid: 2000  Access: 0755
/system/bin/init            Uid: 0      Gid: 2000  Access: 0755
```

- `system_a` 与新建 EROFS sha256 一致（`098f060a...`）
- `vendor_a` 未变（`46046211...`）
- 其余 11 个分区与原 v5 逐字节一致
- `libEGL.so` / `libGLESv2_angle.so` / `libvulkan.so` 仍是 crDroid 版
- `strings libEGL.so | grep kgsl-3d0` = **0**（无 KGSL 依赖）
- `fsck.erofs` 通过，分区组余量 1405.9 MiB

## v5b 产物

```
boot.img        32,069,632 B   sha256 ec30855ece57548950851ccccfb695f169369a2e3d2e2cacca1ebdcda588193b
super.img.zst   9,383,360,844 B sha256 c51231c0faaa80a2ff4c0ef537d098d4c06595ab5dccb1f6ddb71628202a5596
```

- system_a sha256 `098f060adf9a22c67c2374ca7d943445d1128ca85c015ba4372085e88e8956bd`
- 与 v5 相比：**仅 system_a 的 inode 属主修复**，boot/vendor 及其它分区不变
- 压缩使用 `zstd -T0 -12`，**不加 `--long=31`**（上次 `bad-magic` 校验失败即由它引起）
- `zstd -t` 与 `sha256sum -c` 均通过