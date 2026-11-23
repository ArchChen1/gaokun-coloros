# 从零构建（clone → 依赖 → 输入 → 出包）

目标：别人 clone 仓库、装依赖、抓输入，就能出一条能刷的 `super.img`。所有路径都可配，脚本里没有写死的主机路径。

## 0. 环境

- **WSL2 Ubuntu 24.04**（或任意 Ubuntu ≥ 22.04，需要 loop 挂载与 root）
- 磁盘 ≥ 25 GB 空闲（单槽 10 GB 的 raw 中间物 + 20 GiB super）
- 不要在 Windows 侧直接跑：脚本依赖 `mount -o loop`、`fsetattr`、`mkfs.erofs`

依赖一键装：

```bash
sudo make deps
```

会装 `erofs-utils`、`e2fsprogs`、`attr`、`android-sdk-libsparse-utils`（`simg2img`）、`zstd`、`python3` 等，并检查 `mkfs.erofs ≥ 1.9` 与 `tools/otatools/bin/lpmake`。

## 1. 输入（8 GB 左右，不入库）

```
$GK3_WORKDIR/in/
├── vendor_base.img      基座 vendor（512 MiB ext4，含 turnip/skiavk 前的原始状态？见下）
├── my_product.erofs     A 槽 my_product
├── my_stock.erofs       A 槽 my_stock
└── src/                 system_ext / product / my_manifest / my_region / my_engineering / my_heytap / my_carrier / my_bigball
```

清单在 `inputs/manifest.txt`（每行 `sha256 bytes name [url]`）。抓取：

```bash
make fetch                                  # 用清单里的 url
GK3_INPUT_BASE_URL=https://your-host/base make fetch   # 或统一前缀
```

**注意**：`vendor_base.img` 必须是**已含黑屏修复**的 512 MiB 基座（驱动 sha `7619b128…1d90`、`debug.hwui.renderer=skiavk`），
不是 donor 的原始 vendor，也不是 1.31 GiB 未缩容版本。`make verify` 会核对这一点。

这些输入是从 donor 提取的中间产物（见 `docs/DONOR.md`），目前未对外托管，需要自己准备：

```
lpunpack super.img out/            # 拆出各分区
fsck.erofs --xattrs --extract out/system/ out/system_a.img   # 得到解包树
```

## 2. 解包树

`$GK3_WORKDIR/trees/` 里放两份“改了补丁之后”的树：

```
trees/system/       # 传给 mkfs.erofs 的根（其下有 system/ 子目录）
trees/odm/          # odm 树的根
```

`system` 树里至少要包含本项目的改动：`etc/firmware/ath11k/WCN6855/hw2.1/` 四个固件、
`etc/init/gaokun3-v43.rc` 的密度触发、`etc/gaokun3-postboot.sh`、`etc/gk3-charge/{SystemUI.apk,empty}`。
`odm` 树的 `lib64/` 里要有 `libjsoncpp.so`、`android.hardware.sensors-V3-ndk.so`、`libhidltransport.so`。

## 3. 配置（可选）

默认所有东西都在 `$HOME/gk3-build/`。要复用已有目录就写一个机器级配置：

```bash
mkdir -p ~/.config/gk3-coloros
cat > ~/.config/gk3-coloros/env <<'EOF'
GK3_STATE=/home/you/coloros-build/current
GK3_TREES=/home/you/v50-build
GK3_INPUTS=/home/you/gk3-inputs
GK3_SRC=/home/you/coloros-build/v49/src
GK3_MKFS_EROFS=/home/you/toolchain/erofs-install/bin/mkfs.erofs
GK3_FSCK_EROFS=/home/you/toolchain/erofs-install/bin/fsck.erofs
GK3_PUBLISH=/mnt/d/gaokun-coloros-release/latest
EOF
```

（用 `sudo` 跑时还会找 `/home/$SUDO_USER/.config/...`；`GK3_ENV_FILE` 可指定任意路径。）

## 4. 构建

```bash
make verify                # 只跑断言，不产出
make parts VERSION=v54     # 固化基座：vendor 打补丁 → 重打 system/odm → 写 manifest
make pack                  # 读 manifest 出 super → 发布到 $GK3_PUBLISH
make all VERSION=v54       # 等价于 parts + pack
```

产物：

- `$GK3_STATE/release/super-v54.img`（同时有 `super.img` 软链）
- `$GK3_STATE/manifest.json`（版本、每个分区真实路径 + bytes + sha256 + 不变量）
- `$GK3_PUBLISH/`：`super.img`、`super.img.sha256.txt`

`make pack` 内部会先跑 `make verify`，断言不过直接 `PACK_ABORTED`，不会产出镜像。

## 5. 刷机

安装器“卸载 → 安装”会清数据，安装目录需要三件：

```
boot.img      # 设备原有、含 dtb 的 boot（64 MiB）
super.img
install-artifacts.sha256    # 两行：<sha256>  super.img / <sha256>  boot.img
```

校验 super 形态（可选的 PC 侧自检）：

```bash
python3 installer/tools/make_release.py --boot boot.img --super super.img
```

## 6. 常见坑

| 现象 | 原因 / 处理 |
|---|---|
| `No space left on device` | 单槽 raw + super 很占地方，先 `make clean` 再重打；WSL 的 196 GB 很容易满 |
| `bad interpreter: ^M` | 仓库已用 `.gitattributes` 强制 `*.sh eol=lf`；若手改过文件，`dos2unix` 一下 |
| `invalid de[0].nameoff` | 本机 `mkfs.erofs 1.9.4` 产出的镜像用 `dump.erofs --path` 查不到路径，用 `grep -a` 在裸镜像里核实文件存在 |
| `Invalid sparse file format at header magic` | `lpmake -S` 的正常提示，不是错误 |
| vendor 挂不上、`bad geometry` | 缩容顺序必须 `resize2fs` 先、`truncate` 后 |
| 断言 `vendor 驱动 sha` 不过 | 基座用错了：必须用打过 turnip/skiavk 的 512 MiB 基座 |
