# ColorOS 移植精简（debloat）清单 v1

数据来源：设备实测（2026-11-23，`du -k` + `pm list packages -f`），范围为 `/my_stock/app`、`/my_stock/priv-app`、`/my_stock/del-app`、`/my_product/app`、`/my_product/priv-app`、`/my_product/del-app`，合计 5769 MB。

## 一、先说 Via 的许可结论

Via 浏览器**不是开源软件，也不允许预装分发**。其官方使用协议由上海知为网络科技有限公司发布，明确写明：授予用户 "个人的、不可转让及非排他性的许可"，并且 "未经我们或相关权利人书面同意，您不得为任何商业或非商业目的自行或许可任何第三方实施、利用、转让上述知识产权"。来源：[https://viayoo.com/zh-cn/docs/terms-of-use.html](https://viayoo.com/zh-cn/docs/terms-of-use.html)

结论：**开源发版不要内置 Via 的 APK**。可行做法是 "删掉系统浏览器，不预装任何第三方浏览器"（用户自行安装），这样既省 169 MB，也不涉及分发授权。

## 二、目录体量（单槽）



| 目录                    | 大小 (MB) | 文件数 |
| --------------------- | ------- | --- |
| /my\_product/del-app  | 1574    | 4   |
| /my\_stock/priv-app   | 1558    | 50  |
| /my\_stock/del-app    | 1158    | 24  |
| /my\_stock/app        | 920     | 47  |
| /my\_product/app      | 429     | 10  |
| /my\_product/priv-app | 130     | 6   |

两个 `del-app` 合计 **2732 MB（约 2.67 GiB）**，这部分是 ColorOS 自己标记的 "可卸载预装"，是精简的主要来源。

## 三、清单

### A 档：建议删除（纯商业 / 内容 / 社区入口，无系统依赖）



| APK                      | MB       | 包名                    | 位置                  | 说明                     |
| ------------------------ | -------- | --------------------- | ------------------- | ---------------------- |
| WpsLauncher.apk          | 1374     | com.oplus.wpslauncher | my\_product/del-app | 你说的 "WPS PC"，单项占全机 12% |
| Health.apk               | 144      | com.heytap.health     | my\_product/del-app | 健康，需 HeyTap 账号         |
| OPPOStore.apk            | 94       | com.oppo.store        | my\_stock/del-app   | 软件商店（会推 OTA / 广告）      |
| BrowserVideo.apk         | 89       | com.heytap.yoli       | my\_stock/del-app   | 视频内容                   |
| Music.apk                | 71       | com.heytap.music      | my\_stock/del-app   | 音乐内容                   |
| StudyCenter.apk          | 69       | com.oplus.studycenter | my\_stock/del-app   | 学习中心                   |
| KeKeThemeSpace.apk       | 60       | com.heytap.themestore | my\_stock/del-app   | 主题商店                   |
| Gamecenter.apk           | 38       | com.nearme.gamecenter | my\_stock/del-app   | 游戏中心                   |
| KeKeUserCenterMember.apk | 29       | —                     | my\_stock/del-app   | 会员中心                   |
| OPCommunity.apk          | 26       | com.oneplus.bbs       | my\_stock/del-app   | **一加社区**               |
| Melody.apk               | 16       | —                     | my\_stock/del-app   | 内容推荐                   |
| HotGamesFolder.apk       | 10       | —                     | my\_product/del-app | 热游文件夹                  |
| Tips.apk                 | 9        | —                     | my\_stock/del-app   | 玩机技巧                   |
| PhoneManagerLite.apk     | 1        | —                     | my\_stock/del-app   | 手机管家简化版                |
| **小计**                   | **2130** |                       |                     |                        |

### B 档：可选删除（有功能替代或使用率低）



| APK                         | MB            | 包名                          | 说明                          |
| --------------------------- | ------------- | --------------------------- | --------------------------- |
| OppoGallery2.apk            | 241           | —                           | 相册；删了要看第三方图库是否够用            |
| Browser.apk                 | 169           | —                           | 系统浏览器；删后不预装 Via（许可问题），用户自装  |
| OplusGames.apk              | 98            | —                           | 游戏中心（priv-app 常驻）           |
| OplusDocumentsReader.apk    | 82            | andes.oplus.documentsreader | 文档阅读，可用第三方替代                |
| Instant.apk                 | 74            | —                           | 快应用框架，删后部分网页快应用失效           |
| AIMemory.apk                | 63            | —                           | AI 记忆，需云端                   |
| OcrScanner.apk              | 69            | com.coloros.ocrscanner      | 扫一扫 / OCR                   |
| OppoTranslation.apk         | 64            | com.coloros.translate       | 翻译                          |
| AssistantScreen.apk         | 56            | —                           | 负一屏（智慧助手）                   |
| KeKeMarket.apk              | 51            | —                           | 另一个应用市场                     |
| OPSynergy.apk               | 50            | —                           | 多屏协同（对接 PC/Windows 有用，建议保留） |
| HeytapReader.apk            | 46            | com.heytap.reader           | 阅读                          |
| BackupAndRestore.apk        | 28            | —                           | 备份恢复（本地备份有用，建议保留）           |
| **小计（去掉 Synergy/Backup 后）** | **1069**      |                             |                             |
| **合计可删**                    | **约 3.2 GiB** |                             |                             |

### C 档：建议保留（系统刚需或基础体验）

时钟、日历、天气、计算器、指南针、文件管理、录音机、邮件、短信、联系人、电话、相册（若选 B 档删则需补位）、输入法（Sogou 69 MB）、相机（104 MB）、WebView（162 MB）、语音助手、壁纸、截图、全局搜索。

## 四、尺寸预算（配合 A/B 双槽）



| 项                                  | 单槽        | 双槽       |
| ---------------------------------- | --------- | -------- |
| 现状                                 | 11.55 GiB | 23.1 GiB |
| 删 A 档（2.13 GiB）                    | 9.42 GiB  | 18.8 GiB |
| 再删 B 档部分（约 1.05 GiB）               | 8.37 GiB  | 16.7 GiB |
| 再收紧 vendor 分区（现分配 1.2 G，实占 0.42 G） | 7.6 GiB   | 15.2 GiB |

据此，super 取 **18 GiB** 即可（余量约 2.8 GiB），userdata 从 125 G 降到 **119 G**，只让出约 6 G（而完整不精简需让 14 G）。

## 四·补 最终取舍（2026-11-23 用户定稿）

只删 A 档中的五项，B/C 档不动：

| APK | MB |
|---|---|
| WpsLauncher.apk | 1374 |
| Health.apk | 144 |
| OPCommunity.apk（一加社区） | 26 |
| Tips.apk（玩机技巧） | 9 |
| HotGamesFolder.apk（热游文件夹） | 10 |
| 合计 | 1523（1.49 GiB） |

对应预算：

| 项 | 单槽 | 双槽 |
|---|---|---|
| 现状 | 11.55 GiB | 23.1 GiB |
| 删上述五项 | 10.06 GiB | 20.1 GiB |
| 再把 vendor 按实占收紧（省 0.78 GiB） | 9.28 GiB | 18.6 GiB |

→ super 取 **20 GiB**（余量约 1.4 GiB），userdata 125 G → **117 G**，让出约 8 G。

## 五、风险与回滚



* A 档删完后，负一屏卡片、文件管理器 "文档阅读" 入口、游戏中心图标、主题商店入口会失效或空指向；属可接受的功能损失。

* B 档里的相册 / 浏览器如果删，需要给用户替代方案（否则 "没有浏览器 / 没有图库" 会成为首发第一大 issue）。

* 删 `del-app` 不影响系统签名的完整性（我们本来就要重建镜像并重新做 AVB）。

* 所有删除都在镜像构建阶段完成，脚本保留 "原镜像 + 删除清单"，可一键回滚重出镜像。

## 六、执行方式（待确认后做）



1. 在镜像解包目录按清单删除 APK 及其 oat/vdex（`/my_stock/del-app/xxx/oat`、`/my_product/del-app/xxx/oat`）。

2. 清 overlay / 权限残留：检查 `/my_stock/etc/permissions`、`/my_product/etc/permissions` 里对应 xml（多数无强依赖，需逐项确认）。

3. 重建 EROFS 镜像（尺寸按实占 + 8% 余量），更新 `dynamic_partitions_info.txt` 与 `lpmake` 参数。

4. 出 super 镜像 + 打包 payload，跑一次完整刷机验证开机与功能。