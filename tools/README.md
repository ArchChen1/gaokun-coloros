# tools

| 文件 | 作用 |
|---|---|
| `otatools/bin/lpmake` | 打 super 用（`-S` 出 sparse）。**静态链接**的 x86_64 单文件（4.6 MB，sha256 `ea077cf9…467a`），随仓库分发以免重装工具链。来源：LonelyFool/lpunpack_and_lpmake 的预编译件（经 Exynos-nigg/lpunpack-lpmake-mirror 分发）。之前放的是 AOSP otatools 的动态版本，离开 `libbase/liblog/liblp/libc++` 就跑不起来，CI 上直接报缺库 |
| `pe_machine.py` | 读 PE 头 Machine 字段，断言安装器产物是 ARM64（`0xAA64`） |
| `sparse_check.py` | 校验 super.img 的 sparse 头：魔数、块大小、展开后是否正好 20 GiB |
| `../build/charger_hal_deps.py` / `../build/charger_hal_deps.sh` | 静态求某个 HAL 二进制的动态库依赖闭包，判断哪些库只能从 system 侧拿到、必须拷进 `odm/lib64` |
| `gk3_hal_probe.sh` | 设备端迭代探针：用 `/data/local/tmp` 当临时库目录，逐个补库直到二进制链接成功，直接给出“还差哪几个” |

`charger_hal_deps.sh` 需要先挂载 vendor/system_ext/product/my_product/my_stock 到 `/mnt/{cv,se,pd,mp,ms}`，
脚本自己会做（只读挂载，退出时卸载）。

`gk3_hal_probe.sh` 用法（不需要 root）：

```powershell
adb push tools/gk3_hal_probe.sh /data/local/tmp/
adb shell sh /data/local/tmp/gk3_hal_probe.sh
```
