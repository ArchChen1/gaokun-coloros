# 安装器源码（vendored）

安装器不是子模块，源码**整棵仓库**直接放在 `vendor/gaokun-android/`：克隆本仓库就自带安装器，
不依赖另一个仓库是否还存在（那种单点一旦被删或转私有，clone 就编不了）。

## 来源

| 项 | 值 |
|---|---|
| 上游仓库 | `https://github.com/vahiru/gaokun-android`（GPL-3.0） |
| 派生仓库 | `https://github.com/ArchChen1/ego-gaokun-installer` |
| 复制时的提交 | `685c842`（`fix(installer): 允许 super.img 稀疏镜像并修正 20 GiB 文案`） |
| 复制范围 | 仓库根除 `.git` 外全部：`installer/`、`tools/`（含 `gk3boot/core`）、`scripts/`、`device/`、`manifests/`、`patches/`、`docs/`、`.github/`、`installer-ego/` |
| 规模 | 1,397 个文件、17.5 MB |
| 复制时间 | 2026-11-24 |

为什么要整棵：后端 Makefile 里 `CORE := ../../tools/gk3boot/core`，各脚本用 `../../..` 当仓库根，
只搬 `installer/` 会立刻断链（实测 `No rule to make target '../../tools/gk3boot/core/include/gk3core.h'`）。

## 已含的本项目改动

- `installer/backend/src/plan.h`：`GK3W_SUPER_MIB` 12288 → **20480**
- 启动项标题 → `ColorOS 17.0.1`

补丁原文另存 `patches/`，供将来与上游 rebase 时对照。

## 许可

GPL-3.0。`vendor/gaokun-android/` 及其衍生物必须继续以 GPL-3.0 分发；若原仓带 `LICENSE`，以该文件为准。

## 与上游同步

```bash
git clone --depth 1 https://github.com/ArchChen1/ego-gaokun-installer.git /tmp/ego-inst
rsync -a --delete --exclude .git /tmp/ego-inst/ vendor/gaokun-android/
git -C /tmp/ego-inst rev-parse --short HEAD      # 更新本文档的“复制时的提交”
```

导入后必须跑构建验证，不认“看起来没冲突”：

```powershell
.\build.ps1 -Target installer
wsl make -C vendor/gaokun-android/installer/backend test   # 至少后端单测
```

## 目录

```
vendor/gaokun-android/
├── installer/
│   ├── backend/     C 后端（gk3w.exe、mke2fs、sdboot）；`make -C installer/backend test|win-x64`
│   ├── common/      共享 Dart + fetch-fonts.py
│   ├── windows/     Flutter Windows 应用
│   ├── live/        LiveCD 安装器（暂缓）
│   └── tools/
├── tools/gk3boot/core/   后端依赖的共享 C 核心（GPT/CRC32/boot.img/misc 盘上格式）
├── scripts/ device/ manifests/ patches/ docs/ .github/
└── installer-ego/  安装器适配说明与补丁
```

本单位置的 `installer/` 只放本项目自己的东西：`UPSTREAM.md`、`patches/`、`tools/make_release.py`。
