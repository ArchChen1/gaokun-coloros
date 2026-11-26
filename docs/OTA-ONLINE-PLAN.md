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

