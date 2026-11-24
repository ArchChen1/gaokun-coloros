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

## 1. 输入（托管在 Release `inputs-v1`，9.2 GB 分片 / 落盘 12.8 GB）

不用自己拆 donor 包了。输入是 13 个目标、15 个分片，清单就在仓库里：

```
inputs/targets.txt   <sha256> <bytes> <target>            完整文件的 sha
inputs/slices.txt    <sha256> <bytes> <asset> <target>    每个分片的 sha（GitHub 单资产 ≤2 GB）
```

```bash
sudo -E make fetch     # 下载 → 校验分片 → 拼装 → 校验整体 sha → 解包两棵树
```

`fetch` 幂等：目标已存在且 sha 匹配就跳过。换镜像（内网缓存、自建 HTTP）用 `GK3_INPUT_BASE_URL`：

```bash
GK3_INPUT_BASE_URL=https://mirror.example/gk3-inputs sudo -E make fetch
```

| 目标 | 大小 | 说明 |
|---|---|---|
| `vendor_base.img` | 512 MiB | 已含黑屏修复的基座 vendor（驱动 sha `7619b128…1d90`、`debug.hwui.renderer=skiavk`） |
| `my_product.erofs` / `my_stock.erofs` | 1.0 / 3.9 GiB | 原样进 super |
| `src/*_a.img`（8 个） | 共 ~1.1 GiB | `system_ext`、`product`、`my_manifest`、`my_region`、`my_engineering`、`my_heytap`、`my_carrier`、`my_bigball` |
| `trees/system` | 822 MB（解开 1.6 GB） | 解包后的 system 树，`make parts` 从它重打 `system.erofs` |
| `trees/odm` | 1.62 GB（解开 3.1 GB） | 解包后的 odm 树，重打 `odm.erofs` |

树用 tar.zst 打包：它们含几万个文件与 SELinux 扩展属性，不适合进 git；打包时固定了 mtime / 属主 / 排序，
同一棵树重复打包得到同一份 tar。**`fetch` 必须 root**，否则 `security.selinux` 标签写不进去（脚本会拒绝执行）。

## 2. 解包树

`fetch` 已把两棵树解到 `$GK3_WORKDIR/trees/{system,odm}`，正常流程不用管。只有在要改 system/odm 内容时才动它们，
`make parts` 会从树重打分区：

- `system` 树：`etc/firmware/ath11k/WCN6855/hw2.1/` 四个固件、`etc/init/gaokun3-v43.rc` 的密度触发、
  `etc/gaokun3-postboot.sh`、`etc/gk3-charge/{SystemUI.apk,empty}`
- `odm` 树：`lib64/` 里的 `libjsoncpp.so`、`android.hardware.sensors-V3-ndk.so`、`libhidltransport.so`

`make verify` 会逐条核对上面每一项。

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

CI 里同一条链路由 `.github/workflows/system.yml` 执行：干净运行器上 `fetch` → `build` → `pack`，这就是“拉取就能编译”的验收。

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
| `fetch` 报“需要 root” | 解包树要写 SELinux 标签，用 `sudo -E make fetch` |
| 分片拼装后 sha 不符 | 下载中断，删掉 `$GK3_WORKDIR/.parts` 再跑一次 |
