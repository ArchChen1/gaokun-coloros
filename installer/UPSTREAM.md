# 安装器源码（vendored）

本目录 `app/` 是**从上游整棵子树复制进来的源码**，不是子模块。这样本仓库克隆下来就自带安装器源码，
不再依赖另一个仓库存在与否（那种单点一旦被删，clone 就编不了）。

## 来源

| 项 | 值 |
|---|---|
| 上游仓库 | `https://github.com/vahiru/gaokun-android`（GPL-3.0） |
| 派生仓库 | `https://github.com/ArchChen1/ego-gaokun-installer` |
| 复制时的提交 | `685c842`（`fix(installer): 允许 super.img 稀疏镜像并修正 20 GiB 文案`） |
| 复制范围 | 仅 `installer/` 子树（`app/`），404 个文件、3.0 MB |
| 复制时间 | 2026-11-24 |

`app/` 里已经包含本项目的两条改动（提交在派生仓库里，不是另打的补丁）：
- `backend/src/plan.h`：`GK3W_SUPER_MIB` 12288 → **20480**
- 启动项标题 → `ColorOS 17.0.1`

`patches/` 里另有这两条补丁的原文，供将来跟上游 rebase 时参考。

## 许可

上游 GPL-3.0：**本仓库中 `installer/app/` 部分及其衍生物必须继续以 GPL-3.0 分发**。
`installer/app/` 下的源码如与原仓库有 LICENSE 文件，以该文件为准；没有的话按 GPL-3.0 处理。

## 怎么跟上游同步

不要用子模块，直接用一次性的导入脚本（保留本地改动、丢弃上游历史）：

```bash
# 1. 拉一份干净的上游（或派生仓库）到临时目录
git clone --depth 1 https://github.com/ArchChen1/ego-gaokun-installer.git /tmp/ego-inst

# 2. 覆盖式导入，然后人工 review 差异
rsync -a --delete /tmp/ego-inst/installer/ installer/app/

# 3. 记下新的上游提交号
git -C /tmp/ego-inst rev-parse --short HEAD    # 更新本文件的“复制时的提交”

# 4. 构建验证（后端主机单测 + Flutter 构建）
.\build.ps1 -Target installer
```

要求：每次导入都要跑一遍 `.\build.ps1 -Target installer`，只认产物，不认“看起来没冲突”。

## 目录速查

```
installer/
├── app/
│   ├── backend/           C 后端（gk3w、mke2fs 构建、sdboot 取包）
│   ├── common/            共享 Dart 代码 + 字体拉取脚本
│   ├── live/              LiveCD 安装器（暂缓）
│   ├── windows/           Flutter Windows 应用（runner + UI）
│   └── tools/             辅助工具
├── patches/               两条改动补丁原文（rebase 参考）
├── tools/make_release.py  发布目录自检（boot/super/sparse/20 GiB）
├── README.md              本目录说明
└── UPSTREAM.md            本文件：来源、许可、同步流程
```
