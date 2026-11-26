# 在线更新（OTA 在线接入）方案

日期：2026-11-24　设备：OPD2513 /gaokun3 / ColorOS 17.0.1　当前 super：20 GiB 双槽（A 有内容，B 已写入并校验）

## 1. 先把三件事讲清楚

**为什么设置里看不到 "系统更新"**

v43 精简时删掉了 `Cota`（priv-app）、`RomUpdate`（app）和 `bin/cotad`，Settings 里的软件更新入口依赖这几个组件；现在设备上只剩 `com.oplus.upgradeguide`（升级引导小卡片，不是更新器），也没有任何 Activity 响应 `android.settings.SYSTEM_UPDATE_SETTINGS`。所以缺的是**入口组件**，不是更新能力 —— `update_engine`（running）和 `update_engine_client`（带 `--oplus_switch_slot`）都还在。

**之前 "官方前端本地更新" 研究到什么程度**（`docs/releases/V43-OTA-STATUS-2026-11-23.md`）



* 前端这条路已经彻底打通：克隆的 v9 APK 能走完 选包 → state 14 校验 → state 7 可装 → 立即安装 → 8.9 GB 复制 17 s → 签名校验 → 调 `applyPayload`。

* 引擎侧当时堵两层：① `system_other` 的 AVB footer 擦除（4 字节补丁证明可跳过）；② **super 没有 B 槽目标分区**（缺约 11.5 GiB）—— 这条今天已经不存在了，super 扩到 20 GiB、B 槽 13 个分区齐备。

* 结论：**引擎的第二层堵点已被我们的双槽改造消除**，但 "官方前端能装" 不等于 "能在线更新"—— 官方前端的 "检查更新" 走的是 Oplus 私有协议（cotaservice + 官方服务器），那套我们既没有服务端也改不动。

**我们现在手里已经验证过的执行器**

13 个分区 9.37 GiB 写入 170 s、回读 27 s、13/13 sha 一致；`--oplus_switch_slot=true` 来回切两趟成功；A 槽内容全程未动。

## 2. 三条可选路线



|               | A：标准 OTA 在线                                                                                    | B：自建清单 + dd 写 B（推荐）                       | C：半自动（官方前端 + 手动选包）     |
| ------------- | ---------------------------------------------------------------------------------------------- | ----------------------------------------- | ---------------------- |
| 在线怎么走         | App 调 `update_engine_client --update --payload=http://…`，引擎自己下载 + 校验 + 写 B                     | App 读静态清单 → 只下变更分区 → `dd` 写 B → 回读校验 → 切槽 | 用户在官方前端里手动选 zip，前端交给引擎 |
| 前置条件          | 要生成 payload、要 payload 签名与 `otacerts.zip` 匹配（需重建 my\_engineering 换证书）；或继续用打过补丁的 `update_engine` | 已有：脚本、校验、切槽全部实测通过                         | 需要恢复 Cota 前端 + 每次手工选包  |
| 能更新 boot / 内核 | 能（payload 可以带 boot）                                                                            | 不能（只覆盖 super 内动态分区；换内核要另刷 `boot_b`）       | 看包内容                   |
| 增量            | 依赖 payload 差分                                                                                  | 按分区 sha 只下变化项（system/odm 常变，其余多数不变）       | 整包                     |
| 工作量           | 大（payload 工具链 + 证书链 + 引擎补丁要长期维护）                                                               | 中（App + 清单 + 打包脚本）                        | 小，但 "在线" 退化成人肉         |
| 开源可发行         | 一般（依赖私有证书 / 补丁）                                                                                | 好（全部代码与脚本在仓里）                             | 差（依赖克隆的私有 APK）         |

选 B 的核心理由：这条链路的每一步都已经在真机上验证过，唯一新增的是 "下载" 和 "界面"；而 A 的每一步都还停留在 "理论上可行"，而且会把 "更新" 绑死在一张我们自己造的证书和一份打过补丁的引擎上 —— 这两样东西每次上游换版本都要重新对一遍。

## 3. 推荐方案：B 的拆解

**服务端（静态，无需自己写接口）**



```
ota/index-<channel>.json      # 版本、日期、更新日志、每个分区的 sha256/bytes/URL、总 sha
ota/<version>/<file>          # 13 个分区镜像（分片 <1.9 GB）+ apply/rollback 脚本
```



* 托管先用 GitHub Release（分片能力已在 `inputs` 那套验证过）；量大了再换 R2 整文件（vahiru 就是这么干的，`ota.072172.xyz`）。

* `index.json` 用 ed25519 签名，公钥硬编码进 App —— 否则任何人改一行 JSON 就能往你机器上刷分区。

* 断点续传 + 空间预检（`/data` 至少要 10 GiB 空闲）。

**客户端 App（原生 ARM64，不引入新工具链）**



1. 检查更新：拉 `index.json`，比对本地 `installed.json`（记录当前每个分区的 sha，安装时落盘）。

2. 下载：只下 sha 不同的分区，进度按字节；失败重试三次，校验失败即删重下。

3. 安装：`su -c sh apply_b.sh`（KSU 授权一次），App 只做进度展示与日志收集。**校验通过才允许切槽**，这条已经在脚本里硬卡住。

4. 切槽 + 重启：`update_engine_client --oplus_switch_slot=true`，提示 "重启后生效"。

5. 回滚：主界面保留 "切回另一槽" 按钮（同一条命令），以及 "安装前快照" 入口（`/misc` 4 KiB 恢复到系统里前先确认 A 仍可启动）。

**入口（不动 Settings APK）**



* 必做：桌面图标 + `android.settings.SYSTEM_UPDATE_SETTINGS` 注册。

* 想让 "设置 → 关于本机" 里出现一行，只有两条路：恢复 Cota 组件（v43 删的，审计结论说它牵连首启引导，风险不小），或给 Settings 打 overlay 补丁（每次上游更新都要重打）。建议先不改 Settings。

**与 "官方前端" 的关系**

v9 clone APK 留着当 "离线安装器" 用（有人拿 U 盘 / 局域网传 zip 时），不进在线流程。它的价值是证明了 "官方引擎能收下我们的包"，不是当 UI。

## 4. 阶段与工作量



| 阶段 | 内容                                                                    | 预估      | 产出           |
| -- | --------------------------------------------------------------------- | ------- | ------------ |
| P0 | 双槽 super 上重跑一次官方本地安装（现成 8.9 GB payload），确认引擎第二层堵点是否真的消失               | 半天      | 结论：A 路线能不能走通 |
| P1 | 清单格式 + 打包脚本 `tools/ota/make_release.py`（产出镜像 + index.json + 签名）+ 首版上传 | 0.5–1 天 | 服务端可用        |
| P2 | App 下载 / 校验 / 进度（含断点续传）                                               | 1.5 天   | 能下完整包        |
| P3 | App 触发安装 + 切槽 + 回滚 + 安装标记                                             | 1 天     | 端到端          |
| P4 | 入口（桌面图标 + action 注册）                                                  | 0.5 天   | 可从设置 / 桌面进入  |
| P5 | 全流程演练：A → 新版 B → 回滚 → 再升                                              | 1 天     | 验收报告         |

P0 值得先做：如果官方 payload 引擎在双槽 super 上真的能建快照并装完，那 "在线" 最简单的实现就是 App 给一个 URL，剩下全交给引擎，我们连 dd 都不用维护；代价是要处理 payload 签名（换 `otacerts.zip` 或继续用补丁引擎）。**这是唯一一处需要你拍板的技术分叉。**

## 5. 风险与护栏



* **清单必须签名**，否则等于给攻击者一个 "往 super 写任意分区" 的后门。

* **root 依赖**：dd 路线必须有 root（KSU 授权）。将来如果走官方引擎路线就没有这个依赖 —— 这也是 P0 的另一个价值。

* **切槽不会校验目标槽**：`--oplus_switch_slot` 无条件切；所以脚本把 "回读校验通过" 卡在切槽之前，App 不许绕过脚本直接调用切槽。

* **换内核必须同步刷&#x20;**`boot_b`：`boot_a`/`boot_b` 目前 sha 相同（`aaaeb1b5…ffe8`），一旦只改 super 不改 boot，切 B 会起不来。在线包里有 boot 变更时必须一起写，且要先确认降落伞（原槽仍可启动）。

* **上游更新适配**：先合并上游再重打分区，清单里记录上游 commit 与 erofs 版本；`installed.json` 保留上一版，方便退回。

* **数据**：任何情况下只写 B 槽与 `/misc` 的 bootctrl 块，不碰 `userdata`。

## 6. 需要拍板



1. **执行器**：先花半天验证官方 payload 引擎（若通，在线更简单、还能带 boot），还是直接走已验证的 dd 路线？

2. **托管**：GitHub Release（免费、分片、已有能力）还是 R2 / 对象存储（整文件、需要账号与额度）？

3. **客户端形态**：独立原生 Kotlin App（体积小、依赖少），还是复用安装器的 Flutter 工程（品牌统一但多一层运行时）？

4. **入口深度**：只做桌面图标 + action 注册（不动系统），还是连 Settings 里的 "系统更新" 一行也要出现（要恢复 Cota 或打 Settings 补丁）？

## 7. 入口机制实测（2026-11-24，已跑通）

这一段把"设置里那个前端"从设想变成事实，结论可以直接当设计依据。

**Settings 怎么决定显示那一行**（反编译 `com.android.settings` 的 `classes12.dex`）

- `SoftwareUpdatePreferenceController` 继承 `OtaUpdateController`，`getAvailabilityStatus()` 最后一步是
  `ApplicationUtils.isApplicationInfoEnabled(ctx, "com.oplus.ota")`：**包在、且 enabled → 显示**，否则 `UNSUPPORTED`。
- 点击走 `getTargetIntentStatic()`：`new Intent("com.oplus.ota.MAIN")`（GOTA 分支是另一条，CN ROM 不走）。
- 结论：**装一个包名 `com.oplus.ota`、声明 `com.oplus.ota.MAIN` 的 Activity，设置里那一行就自己长出来**，不用改 Settings。
- 实测入口位置：设置 → 系统与更新 → 更多系统设置 → **软件更新**；点进去由 Settings 以 Activity Embedding 把我们的页面内嵌到右栏，标题显示"系统更新"。

**为什么普通 `adb install` 装不上**（反编译 `oplus-services.jar` 的 `OplusThirdPartyAppSignCheckManager.isIllegalAppNameAsOplusPackage`）

```
isDebugMode  = getprop("persist.sys.oplus.debug", false)
isSystemApp  = packages.xml 里该包是否 system
if (签名存在 && !isDebugMode && !isSystemApp
    && isOplusPackageName(pkgName)          // com.oplus./com.coloros. 前缀
    && 平台签名不匹配 && 不是 oplus 签名)   → 拒绝，-8
```

两个合法出口：**① 预装成系统应用（`isSystemApp` 直接跳过整套校验）；② 开发期 `setprop persist.sys.oplus.debug true`**。
实测：没做 ①，只做 ②，`adb install` 立刻 Success，Settings 里那一行随之出现，点击进入我们的 Activity（focus 变成 `com.oplus.ota/MainActivity`）。

**由此定下的发布形态**

- 更新器包名就是 `com.oplus.ota`，预装进 `my_product` 随镜像分发，不依赖任何属性开关。
- 上游若把真 Cota 带回来，需要移除同名组件或让我们的优先 —— 写进上游适配清单。
- v9 克隆 APK 退出主线，只留作"离线本地安装"（用户自己拿 zip 时用），不进在线流程。
- 开发期 `persist.sys.oplus.debug` 当前为 `true`（否则装不上调试包），预装路径走通后必须置回 `false`。

## 8. 已落地的东西（2026-11-24）

### 8.1 更新器骨架 `updater/` + 免 Gradle 构建

- `updater/AndroidManifest.xml`：包名 `com.oplus.ota`，`MainActivity` 响应 `com.oplus.ota.MAIN`，`usesCleartextTraffic=true`（开发期回源 HTTP）。
- `updater/res/`：Material NoActionBar 深色主题，ColorOS 风格大标题 + 版本 + 状态 + 主按钮 + 信息卡（`activity_main.xml`）。
- `updater/src/com/oplus/ota/MainActivity.java`：读版本/槽位（走 `getprop`，避开隐藏 API `SystemProperties`），按钮触发后台线程检查。
- `updater/src/com/oplus/ota/ReleaseSource.java`：`HttpURLConnection` 拉 `index.json`，`org.json` 解析 `version/channel/total_size/parts[]`。
- `build/updater_build.ps1`：aapt2 compile/link（带 `--java` 生成 R）→ javac `--release 8` → d8 → python 追加 `classes.dex` → zipalign → apksigner；首次运行自动生成 `updater/keystore/gk3-ota.jks`（口令 `gk3ota`）。产物 `work/updater-build/gk3-ota.apk`（约 17 KB）。
  - 两个坑记下来：`param()` 块必须首行之上的注释可以、但脚本要用 pwsh 跑（`powershell -File` 会解析失败）；`android.os.SystemProperties` 不在 `android.jar` 里，且 `R` 类只有加 `--java` 才生成。

### 8.2 服务端清单工具 `tools/ota/make_release.py`

`--parts <13 个镜像目录> --version --channel --out --base-url`，逐个算 sha256 后写 `index.json`（`format/version/channel/build_date/total_size/base_url/parts[{name,file,size,sha256}]/signature`）。`signature` 目前为 null，等 S3 定密钥后接 ed25519。

### 8.3 真机验证（在线检查这一环已通）

- `adb install -r` 新包 → `am start -n com.oplus.ota/.MainActivity`。
- 本机 `python -m http.server 8001` 提供 `ota/index.json`（version `17.0.2.100`）。
- 点「检查更新」后界面显示 **发现新版本 17.0.2.100 ｜ 清单版本 17.0.2.100 ｜ 13 个分区 ｜ 9.37 GB**，卡片行显示当前版本 `11.C.17_1170_202611051230`、槽位 `A`。
- 即：Settings 入口 → 我们的 UI → HTTP 拉清单 → 版本比对，全链路在真机上成立。

### 8.4 下一步（按顺序）

1. `DownloadTask`：按 `parts[].sha256` 与设备侧现有分区 sha 比对，只下变更分区到 `/data/local/tmp/gk3-ota/b/`，落盘即校验。
2. 复用已验证的 `apply_b.sh`（写 `_b` → 回读 sha → 切槽），UI 上给进度与阶段文案（下载 / 校验 / 写入 / 待重启）。
3. 错误回滚：写一半失败 → `rollback.sh`，并把 `/misc` 快照 dd 回去。
4. S3 打包（13 镜像 + index.json + 签名）与分发；发版前把 `persist.sys.oplus.debug` 置回 `false`、预装进 `my_product`。

## 9. 发布形态改为「payload + 标准 OTA zip」（2026-11-26 决定）

原来的清单描述的是 13 个分区镜像（dd 路线的产物）。现在引擎路线已经端到端跑通，发布单元改成**一个 payload**，
`make_release.py` 也因此支持单条目登记。

- `make_payload.py --zip <path>`：除了 `payload.bin` + `.properties`，再产出一份标准 A/B OTA zip，
  内含 `payload.bin`（**store**，不再 deflate，内部已压过）、`payload_properties.txt`、
  `META-INF/com/google/android/{update-binary,updater-script}` 两个占位文件；>4 GiB 自动 Zip64。
- `make_release.py --payload <payload.bin> [--zip <zip>]`：`index.json` 里多一个 `payload` 对象
  （`file/size/sha256/file_hash/metadata_size`，可选 `zip`），`parts` 保留给 dd 路线，引擎路线下为空。
- 体积关系：zip ≈ payload + 3 KB（store 模式不产生二次压缩收益，换来的是通用性）。

**执行器的现实约束（2026-11-26 核实）**

`installer/` 那套是 **Windows 端整机重装工具**（需要 USB 写 GPT/boot/super/ESP），不是设备内的写入器；
本机没有 USB 传输通道，所以它不能当 UI 的后端。设备内能写 B 槽的只有：

| 通道 | 谁在跑 | 前置条件 |
|---|---|---|
| `update_engine` + `UpdateEngine` binder | root 守护进程 | 调用方要有系统权限（原厂 Cota 就是这么做的） |
| `update_engine_client` 命令行 | root | 需要 root 通道（当前只有 A 槽调试版有） |
| dd 写分区 | root | 同上 |

结论：要让「设置 → 软件更新 → 点一下就装」成立，`com.oplus.ota` **必须预装进镜像**（平台签名 + priv-app + 白名单），
走 `UpdateEngine` binder；否则 UI 只能做到「下载 + 校验 + 待安装」，写入仍要人肉进 A 槽。


## 10. 预装更新器版本（system = a4b91f73，2026-11-26）

**镜像变化**：`system_patched.erofs` 内容 1,076,695,040 B（truncate 至 1,137,397,760 B），sha `a4b91f7305641b51c993f625063be8074b81674953242a721d1b7cc1fe2ed22e`。
新增三样东西：`system/priv-app/OtaUpdater/OtaUpdater.apk`（`com.oplus.ota`，25,188 B，sha `d419956fdc83…`）、`system/bin/gk3otad.sh`(0755)、`system/etc/init/gk3otad.rc`。
同时把早期充电图标实验留在 `system/etc/gk3-charge/SystemUI.apk`（99 MB）移出树（该副本运行时不加载，已归档到 `/home/cenmin/archive/gk3-charge-20261126`），否则新 APK 会顶破分区。

**账本与闸门**：`verify_all.sh` 第 2 层 system 钉死值改成 `a4b91f73`，第 3 层新增「镜像内更新器 + 写入服务」（挂载后查 priv-app apk、`bin/gk3otad.sh`、`etc/init/gk3otad.rc`）。主账本与 `inputs/manifest-2026-11-26-release.json` 已同步，13/13 自证通过。

**压缩出包（首次带压缩）**：`--compress xz --level 6 --jobs 8`，块 4 MiB，2407 个 op 全为 `REPLACE_XZ`（没有触发 ZERO 块）。
payload `7,266,354,314 B`（6.77 GiB，原始 9.37 GiB，压缩比 0.722，耗时 465 s），sha `5fa58d2830…`，
`METADATA_SIZE=140050`，`FILE_HASH=X6WNKDBq…`。离线自检 `verify_payload.py` → `PAYLOAD_VERIFY_PASSED`（解包重拼 13 分区逐分区 sha 一致、extents 无空洞、整份 sha 对上前文）。

标准 zip：`update.zip` `7,266,355,585 B`（比 payload 大 1,271 B），sha `0861b704bf…`，`payload.bin` 以 `ZIP_STORED` + Zip64 内嵌。
发布清单 `work/release_a4b91/index.json` 同时登记 payload 与 zip（`payload.sha256` / `payload.zip.sha256`），`signature` 仍为 null。

**为什么 Windows 侧出包要换一份账本**：`make_payload.py` 在 Windows python 下读不到 `/home/...` 绝对路径，`work/manifest-win.json` 是把同一份账本里的路径映射成 `\\wsl.localhost\Ubuntu-24.04\home\...` 的一次性输入副本，不入库。

**刷写流程（与第七节一致，只是 payload 带压缩）**：push payload + props 到 `/data/local/tmp` → 开机菜单选 `Direct boot (rescue) - slot _a`（A 槽调试版有 root 通道）→ 触发 `gk3run` 跑 `update_engine_client --update --follow` 写 `_b` → 引擎 `markSuccessful` 后重启落回 B → 复核预装 APK、`init.svc.gk3otad=running`、13 分区 sha。

## 11. 首次端到端 UI 实测（2026-11-26 14:05）

**在线链路通了**：把 `persist.sys.gk3.ota.url` 指到电脑上的静态服务（`http://192.168.1.152:8848/index.json`），
点「检查更新」→ 显示「发现新版本 OPD2513_11.C.17_1170_202611261400 ｜ 更新包 7.55 GB ｜ sha f6961edd4031…」→
点「下载更新包」→ 24% 起稳步推进、1.80 GB / 7.55 GB → 下完自动 sha256 校验 →「更新包已就绪」。

**安装点了但被写入服务拒了**：状态显示「已交给系统写入服务 / reject: bad payload path」。
原因是路径写法：`getFilesDir()` 给的是 `/data/user/0/com.oplus.ota/files/…`，而 `gk3otad.sh` 的白名单只写了
`/data/data/com.oplus.ota/*`。两者是同一个目录（`/data/data` 是 `/data/user/0` 的别名），
但字面匹配不过。修法是最小改动：白名单加一条 `/data/user/0/com.oplus.ota/*`，reject 日志带上实际路径。

**顺带确认的两件事**：① 之前 `adb install` 的那份 `com.oplus.ota` 会把 priv-app 里的系统版盖掉
（`pm path` 指 `/data/app/…`、flags 带 `UPDATED_SYSTEM_APP`），`pm uninstall` 之后就回落成
`/system/priv-app/OtaUpdater/OtaUpdater.apk`（flags `SYSTEM` + `PRIVILEGED`），UI 一致；② `gk3otad` 开机即
`init.svc.gk3otad=running`，`seclabel u:r:su:s0` 在 permissive 下可用。

**压缩结论（重要，推翻第 10 节的 xz 选择）**：同一份账本出的 xz -6 payload 在引擎侧直接失败——
`install_operation_executor.cc(194) writer->Write(...) failed` → `Failed to perform REPLACE_XZ operation 0`
（2455 ms 就终止）。用「只含 my_bigball 一个分区」的 2.2 KB 小样复现同样错误，排除了体积因素；
同一小样换 `bz2` 与 `none` 都 `kSuccess`。结论：这台设备的 `update_engine` 不带 XZ 解压路径，
**发布压缩只能用 bz2**（全量 bz2 -9：8,108,730,778 B / 7.55 GiB，压缩比 0.806，出包 636 s，
真机写入 709 s，`kSuccess`）。xz 只能留给「以后换引擎」时再评估。

## 12. 端到端闭环：设置里点「安装」→ 写另一槽 → 重启落新槽（2026-11-26 15:2x）

两个方向各跑一遍，都是纯 UI 操作（只靠 adb 点按钮和读状态，没有手工写引擎命令）：

- **B → A**：在线检查更新 → 下载 9.11 GB → sha 校验 → 「更新包已就绪」→ 「安装」→ `gk3otad` 取 request →
  `update_engine_client --update --follow` → `rc=0`、`UPDATED_NEED_REBOOT` → 重启落 `_a`。
- **A → B**：同一套点法，重启落 `_b`。两槽最终都是 system `2e224faa`、APK sha `4066ac27…`、`gk3otad.sh` 1699 B。

**这轮抓到的两个真 bug**

1. **`kPayloadHashMismatchError (10)`**：在线下载只落了 `payload.bin`，没落 `payload.bin.properties`，
   `gk3otad` 拿到的 `props=` 是空路径 → 引擎缺 `FILE_HASH`/`METADATA_HASH`/`METADATA_SIZE`，67 ms 就报哈希不符。
   修法：`Downloader.fetch()` 在 sha 校验通过后再拉 `<file>.properties` 存到同目录，缺属性文件就把包删掉并提示；
   服务端必须和 payload 一起发布 properties（`make_payload --zip` 与静态发布都已经是这样）。
2. **`reject: bad payload path`**：App 给的是 `/data/user/0/com.oplus.ota/…`，白名单只写了 `/data/data/…`。
   修法见第 11 节（白名单两条都放行）。

**enforcing 的证据又补了一条**：UI 安装时 logcat 里是
`avc: denied { call } for scontext=u:r:update_engine:s0 tcontext=u:r:su:s0 tclass=binder permissive=1`。
也就是说现在 `gk3otad`（`u:r:su:s0`）调引擎是靠 permissive 放过的，转 enforcing 时必须换成专用域 + 显式 allow。

**一条操作坑**：`adb install` 的 `com.oplus.ota` 会盖住 priv-app 的系统版（`pm path` 指 `/data/app/…`），
且跨槽共享；`pm uninstall` 后才回落 `/system/priv-app/OtaUpdater/OtaUpdater.apk`（flags `SYSTEM`）。
另外 OPPO 的 `pm clear` 对 adb 是禁的（`OplusClearDataProtectManager` 拦截），清数据只能走 uninstall。

## 13. 转 enforcing 的改造清单（草稿，待实施）

目标：`selinux=enforcing` 之后，「设置 → 软件更新 → 安装」这条链路一点不退化。

**要改的三处**

1. **写入服务换域**（`/system/etc/init/gk3otad.rc`）
   - 现在：`seclabel u:r:su:s0`，靠 permissive 放行；enforcing 下 init 找不到可 transition 的 su 域，服务起不来。
   - 改成 `seclabel u:r:gk3otad:s0`，并新增：
     ```
     type gk3otad, domain;
     type gk3otad_exec, exec_type, file_type, system_file_type;
     init_daemon_domain(gk3otad)
     allow gk3otad gk3otad_exec:file { read execute };
     allow gk3otad update_engine:binder { call transfer };
     allow gk3otad system_file:file { read execute };          # 跑 /system/bin/update_engine_client
     allow gk3otad com_oplus_ota_data_file:dir { search open read write add };
     allow gk3otad com_oplus_ota_data_file:file { read write create open };
     ```
   - `file_contexts` 加一行 `/system/bin/gk3otad\.sh u:object_r:gk3otad_exec:s0`。
   - 规则以真机 `audit2allow` 收口：先在全量允许下跑一遍安装，把 `avc: denied` 全部抓出来，再逐条最小化，
     不要一次写 wide-open。
   - `com.oplus.ota` 的私有目录标签要真机确认（可能是 `app_data_file` 而非 OEM 自定义标签），
     用 `ls -Z /data/data/com.oplus.ota/files` 取实际值再写规则。

2. **payload 落点改 `/data/ota_package`**
   - 引擎对 `/data/ota_package` 有默认读写权（AOSP 约定的 `ota_package_file`），App 私有目录没有。
   - App 下完 + 校验过之后，request 里写「源路径」，由 `gk3otad` 负责搬进 `/data/ota_package/<name>.bin`
     再调引擎；成功后清掉。
   - 好处：引擎侧零改动，也不用给 `update_engine` 加「读别人私有目录」的规则（那条规则最危险）。

3. **`com.oplus.ota` 自己也可能被卡**
   - 它要读系统属性（`persist.sys.gk3.ota.url`，走 `property_service` 的读）与 `getprop`，
     现在靠 `system_app`/priv-app 默认规则；enforcing 后要确认这两条没被 denied。
   - 建议同样用 `audit2allow` 打点，别预设。

**验证方式**：把 `ro.boot.selinux` 临时 `setenforce 1` 之后，走一遍完整 UI 安装；`logcat | grep avc` 必须干净，
否则按 denial 补规则，直到一轮安装 0 条 denied。

## 14. 本地包入口 + bz2 发布形态实测（2026-11-26 15:4x）

**「选择本地 OTA 包」跑通了**：把 `update.zip`（7.55 GiB，bz2 payload，store 内嵌）推到
`/sdcard/Download/local_ota_bz2.zip`，在 UI 点「选择本地 OTA 包」→ ColorOS 文件管理器的文档选择器
（不是 AOSP DocumentsUI，界面是「最近 / 搜索文件」那一套）→ 选中 zip。
App 把 zip 复制到私有目录、抽 `payload.bin` 与 `payload_properties.txt` → 显示
「本地包已就绪 7.55 GB ｜ sha 9765a33bc85e…」→ 点「安装」→ 引擎 `rc=0`（214 行日志）、`UPDATED_NEED_REBOOT`。

**bz2 全量在真机上验过了**：这次本地安装走的正是 bz2 压缩包（2407 个 `REPLACE_BZ`），
100% 完成、无 op 报错，说明「bz2 + 4 MiB 分块」这条发布形态在引擎侧成立（xz 已确认不可用）。
因此离线 `verify_payload.py` 对这份包就不必再跑一遍——引擎逐 op 校验每条都过了，比离线重拼更强。

**发布候选已经摆在局域网上**：`work/www/`（`payload.bin` 7.55 GiB + `payload.bin.properties` + `update.zip`）
配 `index.json`：version `OPD2513_11.C.17_1170_202611261530`、sha `9765a33b…`、zip `8108730390 B`。

**又一个 OPPO 限制**：`com.oplus.ota` 现在是纯系统应用（不再有 adb 安装的副本），
`pm uninstall` / `pm uninstall --user 0` 都会被拒（`DELETE_FAILED_INTERNAL_ERROR` / "only root can delete system app"），
所以 App 私有目录里那 7.55 GB 的本地包删不掉——adb 侧没有清数据通道。
要么在 UI 里加一个「清理已下载包」按钮（顺手也能省空间），要么接受它挂在 /data。

## 15. 装成功后自动清理下载包（2026-11-26 16:2x）

**动机**：`/data/data/com.oplus.ota/files/` 里的包（在线 7.55 GB + 本地 7.55 GB 抽出的 `local_payload.bin`）
装完就成垃圾，而 OPPO 禁止 adb 清系统应用数据（`pm clear` 被 `OplusClearDataProtectManager` 拦、
`pm uninstall` 报 only root can delete system app），实测累积到 **16.67 GB** 删不掉。所以清理只能由 App 自己做。

**判定「这次装成了」的三个条件（全中才删）**：
1. `handOff()` 交接前在私有目录写 `pending.json`，记下目标槽（当前槽的另一半）；
2. 冷启动时 `ro.boot.slot_suffix` == `pending.json` 里的目标槽 —— 说明确实从写过的槽起来了；
3. `files/status` 全文里出现过 `kSuccess` —— 说明那次写入是引擎报成功的，不是半路失败。

只满足部分就**不删**、并提示「上次更新没有生效，更新包已保留」：引擎报错、写了但回滚到原槽、
或压根没装过（没有 `pending.json`）都不会误删，重试包还在。

**实现**：`MainActivity.afterBootCheck()`（`onCreate` 里起后台线程跑，主线程只更新文案）+
`cleanCache()`（只删 `files/` 下 `*.bin` / `*.bin.properties` / `*.zip`，`status`、`pending.json`、
`request*` 这类控制文件一律不碰）。另外加了手动入口「清理已下载包（16.67 GB）」按钮，
缓存为 0 时自动隐藏；写入服务还没取走 request 时禁用，避免删掉正在用的 payload。

**为什么只在打开更新页时清，而不是开机广播**：App 要在 `BOOT_COMPLETED` 里删 7.55 GB 需要多一个
receiver + 权限，且删包时机不受控；更新页本来就是用户看结果的地方。等 payload 落点改到
`/data/ota_package` 后，那一步改由 `gk3otad`（init 服务）在开机时清，权限天然更顺。

**实测**：`adb install -r` 新 APK（29,284 B，sha `2a19694d…`）→ 打开页面即显示
「清理已下载包（16.67 GB）」→ 点击 → 「已清理更新包 释放 16.67 GB」，`/data` 可用空间 53 GB，
按钮随之消失。自动清理那条路径要靠下一轮真安装验证（需再跑一次 A→B，约 20 分钟）。

## 16. 进度显示 / 划掉卡片 / 写入耗时定位（2026-11-26 17:1x）

### 16.1 写入进度改成百分比

引擎自己不打百分号，但 client 每收到一次回调会打一行：
`onStatusUpdate(UPDATE_STATUS_DOWNLOADING (3), 0.210037)` —— 是 0..1 的小数。
所以 App 解析这行取小数 ×100，显示成「正在写入 21% ｜ 约 1.6 GB / 7.55 GB」；
拿不到小数时退回「阶段 + 最后一行日志 + 行数」。阶段（`UPDATE_STATUS_*`）翻成
正在写入分区 / 正在校验写入结果 / 正在收尾 / 写入完成，重启生效。

### 16.2 页面被划掉 / App 被杀：不影响，进度会自己接上

写入由 `gk3otad`（init 服务）执行，App 只是读 `status` 文件渲染，所以：
- 划掉任务卡片、`am force-stop`：写入照跑（实测中途 force-stop，2 分钟后引擎仍在工作）；
- 重新打开：`request.done` 存在 → 自动恢复轮询，进度接着跳（实测从 21% 接上）；
- 下载（`Downloader`）跑在 App 线程里，划掉就停，但有 Range 续传，回来点了接着下。

### 16.3 这一轮修掉的三个 bug（都是实机撞出来的）

1. **旧 status 抢跑**：交接后页面第一次刷新读到上一轮的 `rc=0`，直接把轮询停成「写入结束」。
   修法：`handOff()` 先删 `status`，并且只接受 `lastModified ≥ handoff 时刻` 的内容。
2. **中途重开就清掉 pending**：`afterBootCheck()` 在写入未结束时跑了判定，判定"没装成"并删了
   `pending.json`，导致重启后自动清理失效。修法：`runInFlight()`（有 `request`，或 status 里还没有
   `rc=` 结论）时直接返回，不做判定、不动 pending。
3. **误导文案**：写入中重开会提示「上次更新没有生效」。随第 2 条一起消失。

### 16.4 端到端验证（bz2 全量，A → B）

`检查更新 → 下载（~110 s，8.1 GB，74 MB/s 局域网）→ sha 校验 → 安装 → 12 min → rc=0 → 重启`，
落到 `_b`；`gk3otad` running、镜像内 APK 与树一致（`e77e8ebd…`，29,284 B）、`gk3otad.sh` 1888 B。
打开更新页第一眼就是「更新已生效，旧包已清理 ｜ 释放 7.55 GB」，`/data` 45 GB → 53 GB。
**自动清理这条路径通了**，且它不是"打开页面才触发"的补丁式清理，而是判定 = 目标槽 + `kSuccess`
+ 交接时写的 `pending.json`，三条齐全才动手。

### 16.5 为什么"更新太慢"：12 分钟几乎全花在一个核的 bz2 解码上

同一台机器上的实测数字：

| 环节 | 实测 | 说明 |
| --- | --- | --- |
| 下载 8.1 GB（局域网 → 设备） | ~110 s | 74 MB/s，网络不是瓶颈 |
| 写入阶段（`DOWNLOADING` 0→91%） | 665 s | 目标 9.1 GiB ⇒ **13.8 MB/s** |
| 校验阶段（`VERIFYING`） | ~35 s | 引擎把写过的东西读回来逐 op 校验 |
| `/data` 裸写测速（`dd conv=fsync` 2 GB） | 973 MB/s | **存储完全不是瓶颈** |
| 引擎 CPU（`/proc/<pid>/stat` 累计） | 615 s user + 25 s sys / 729 s 墙钟 | **≈88% 单核** |
| 引擎最后落脚的核 | `cpu2`，2.44 GHz（A78 簇） | 单线程，没法并行 |

结构：payload 2407 个 op，全部 `REPLACE_BZ`，每 op 4 MiB 原始块。写入阶段一台 A78 核吃满，
换算成 bz2 解码产出约 13 MB/s —— bz2 解码是单线程、按块串行的老算法，这就是主项；
次项是每 op 的 sha256 校验与 pwrite 小步提交。所以"存储快、网络快、就是慢"不是玄学，
是压缩算法把时间压在了单核上。

可选提速手段（按性价比）：

1. **`--compress none`**：不再解码，只剩校验 + 顺序写。以 973 MB/s 的写速估计整段 1.5~3 min。
   代价是包 9.11 GiB（+2.1 GB 下载）；在局域网/宽带上是明显划算的。
2. **zstd**：引擎二进制里有 `REPLACE_ZSTD` / `ZSTD_initDStream()` 的符号（xz 那条路证实不可用，
   但 zstd 是编译进去的）。zstd 解码速度通常是 bz2 的 3~4 倍，压缩比 0.85 左右。
   需要给 `make_payload.py` 加 zstd 分支，并先拿 2 KB 小样验证 op 编号被接受（和当初验 xz 一样）。
3. **`--chunk 16`**：op 数从 2407 降到约 600，省的是每 op 固定开销，估计 5~10%，单独用收益有限。
4. bz2 压缩等级只影响出包时间与体积，不影响设备端解码速度 —— 想快只能换算法，不是调 `-9/-6`。

结论倾向：**发布默认改 `none`（局域网/宽带）或 zstd（弱网）**，bz2 退居"省流量"选项。

## 17. none 实测提速 + 去预装（附一次卡开机的真因）

### 17.1 `none` 真机写入实测：62~68 秒

同一台机、同一 13 分区、同一 4 MiB chunk：

| 压缩 | payload | 设备端写入（引擎自报 `Command took`） |
| --- | --- | --- |
| bz2 -9 | 8,108,734,542 B（7.55 GiB） | 709~729 s |
| none | 9,554,402,792 B（8.90 GiB） | **62.9 s / 68.2 s** |

差 10 倍以上，坐实第 16 节的判断：慢的是单线程 bz2 解码，不是存储、不是网络。
`make_payload.py --compress` 的默认值本来就是 `none`，发布口径统一到 `none`；
bz2 只留作弱网省流量选项（多花 10 倍写入时间换 1.4 GB 下载）。

### 17.2 去掉 4 个官方预装

清单在 `build/patches/strip-preinstalled.txt`，脚本 `build/patches/p_strip_preinstalled.sh`：

| 应用 | 包名 | 位置 |
| --- | --- | --- |
| OPPO 商城 | `com.oppo.store` | `my_stock/del-app/OPPOStore` |
| 学习空间 | `com.oplus.studycenter` | `my_stock/del-app/StudyCenter` |
| 我的一加 | `com.oneplus.member` | `my_stock/del-app/KeKeUserCenterMember` |
| OS 众测 | `com.oplus.logtrial` | `system_ext/app/LogTrialCommercial`（zh label「OS 众测」） |

删完重打：`my_stock` 3,819,110,400 B、`system_ext` 962,039,808 B，都在分区上限内。
真机（A 槽）复核：4 个包名 `pm list packages` 全部查不到，镜像内目录也不存在。

注意：删镜像只影响**新刷/恢复出厂**后的预装来源；已经装进 `/data/app` 的副本不会自动消失。

### 17.3 一次卡开机的真因：重打分区丢了 SELinux 标签

第一次去预装后写 A 槽，开机卡在 `post-fs-data`：
`vdc checkpoint prepareCheckpoint` 等 56 s 被 SIGKILL（`status 22`）→
`enter_default_mount_ns ... Failed to switch to default mount namespace` →
之后一直 `Waiting for servicemanager.ready`。用开机菜单 `Direct boot (rescue) - slot _a` 也一样，
说明与启动条目无关，是写进去的内容有问题。

逐层排查结论：

* 内容不缺：镜像解包回来与源树逐条 diff **0 行**，条目数 1053 / 3944 都对；
* 真正差异在元数据：`dump.erofs --path=/etc` 显示原厂 `Xattr size: 16`，我们重打的 `Xattr size: 0`
  —— `security.selinux` 全丢了。

两个原因叠加：

1. `fsck.erofs --extract` **默认不导出 xattr**（`--[no-]xattrs` 默认 off），必须显式加 `--xattrs`；
2. 解包目标放在 `/mnt/e`（Windows drvfs）时，xattr、属主、权限都保不住（全变成 `777 1000:1000`）。
   分区树必须落在 WSL 的 ext4 上。

`system` 那条线一直没踩到，是因为它的树本来就在 ext4 上且带标签。

脚本里补了三道闸门：树必须在非 `/mnt` 路径且 `/etc` 带 `security.selinux`；
重打后用 `dump.erofs` 断言 `Xattr size != 0`；再解包与树逐条 diff 必须为 0。
修好后重刷 A 槽：`_a` + `boot_completed=1`，`ls -Zd /my_stock/etc` 回到 `u:object_r:system_file:s0`。

### 17.4 顺带记一笔：WSL 盘写满会静默截断解包

期间 WSL 根盘一度 100%（196 G），`fsck.erofs --extract` 不报错但少解了 `/my_stock/etc` 与 3 个 app。
所以脚本开头查剩余空间（<2 G 直接停），并按写死的条目数校验解包完整性。

## 18. 增量更新（S3）：代码已就位，待稳定版真机验证

### 18.1 原理与硬约束

A/B 的 payload 增量靠 `SOURCE_COPY`：没变的分区不下发任何数据，让引擎从**旧槽**原地复制到目标槽。
`InstallOperation.SOURCE_COPY = 4`，配合每个分区的 `old_partition_info{size, hash}`，
引擎在动手前先校验旧槽内容，对不上就立刻失败（前端据此回退全量），不会写坏一半。

硬约束仍是「**payload 必须覆盖全部 13 个分区**」：少发一个分区，目标槽的那个分区会被重建元数据丢掉。

于是策略定为三级：

1. 最新全量包（`--compress none`）作为「新装 / 救砖 / 增量失败」的兜底；
2. 相邻两版之间的增量包（只带变化分区的数据）；
3. 客户端失败即回退全量，不需要额外逻辑。

### 18.2 代码改动（commit `45dc319`）

- `tools/ota/make_payload.py` 新增 `--source-manifest`：读上一版账本，逐分区比 `bytes + sha256`；
  一致 → 一条 `SOURCE_COPY`（`src_extents`/`dst_extents` 都是 `0..size/blocksize`，不占数据区）；
  不一致 → 照旧走 REPLACE/ZERO 带数据。同时给每个分区补 `old_partition_info`。
- `tools/ota/verify_payload.py` 新增 `--source-manifest`：`SOURCE_COPY` 从旧镜像读回数据参与重拼，
  整体 sha 仍要与 `new_partition_info.hash` 对齐，否则报错。

### 18.3 已完成的验证（离线）

造了一个「源=目标」的零变更增量包，用来单独验证这条路径，不掺杂别的变量：

| 项目 | 结果 |
| --- | --- |
| 包体 | `work/payload_delta_test/payload.bin` **2,214 B**（全量 8.90 GiB） |
| manifest | 13 条 `SOURCE_COPY`，`data_offset` 全 0，数据区 0 B |
| 离线重拼 | 13 分区合计 9.15 GiB，`PAYLOAD_VERIFY_PASSED`，sha 与账本逐个一致 |

### 18.4 待办（稳定版出来后再做）

1. **真机验证全 `SOURCE_COPY`**：写入 B 槽 → `rc=0` → 重启 → 校验 B 槽内容与 A 槽一致。
   测试环境当时已备好（`work/www-delta`，端口 8849，清单版本 `…202611262230`），收工后已关。
2. **混合增量包验证**：改一个分区（例如只动 `system`），出「1 变 + 12 复制」的包再刷一次。
   这才是真实半月更新会遇到的形态，前一步不能替代它。
3. **发布侧登记**：清单里要同时能表达「全量」和「增量」，并让客户端在增量失败时自动回退全量。

### 18.5 顺带记一笔：为什么增量比压缩更值得先做

`none` 全量 8.90 GiB，每次上传/下载都要走满这个量；增量只走变化分区，常态可能只有几百 MB。
用户嫌上行慢、又不想为中间版本重复传 8.9 GB，所以「先做增量、稳定版再上传」的顺序是对的。
