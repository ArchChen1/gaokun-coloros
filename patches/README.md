# 补丁索引

补丁的“语义”写在这里，字节级细节与生成脚本放在对应子目录。

| 补丁 | 位置 | 落点 | 验证方式 |
|---|---|---|---|
| SystemUI 充电状态补丁（smali diff） | `systemui-charge/v43-systemui-standard-charge.patch` | `com.android.systemui` 的 `OplusAddBatteryStatus`：`notifyCode==-1` 时改从附加广播读真实插拔/充电状态（`refreshChargingDerivedState`、`updateChargingStateFromUiIntent`） | 运行时经 zygote 命名空间 bind 挂载后观察控制中心电池图标；HAL 修好后应验证能否撤掉 |
| vendor 黑屏修复（turnip + skiavk） | 无补丁文件，执行脚本见 `../build/legacy/v51_vendor_patch.sh` | `/vendor/lib64/hw/vulkan.freedreno.so` 两处单字节 `1→2`（原 sparse 偏移 2460610728 / 2460610752）；`/vendor/build.prop` 的 `debug.hwui.renderer=skiavk` | 驱动 sha256 必须 `7619b1286b7d0b2d697e0c48b6a471ab7f439eee0523ce1820fee6ba612b1d90`；由 `build/current_verify.sh` 断言 |
| ath11k 固件前移 + rc 非阻塞 | 固件随 system 分发，rc 改动随 vendor 分发 | `/system/etc/firmware/ath11k/WCN6855/hw2.1/` 四个文件；`/vendor/etc/init/hw/init.gaokun3.rc` 的同步 `write` 改 `exec_background` | 断言固件存在；开机看 `boot_progress_start` 是否 < 20 s |
| 显示密度属性触发 | `/system/etc/init/gaokun3-v43.rc` | `on property:persist.sys.display.density=480` → `setprop … 320` | 断言 rc 含该触发；真机 `wm density` = 320 |
| 充电库补齐 | `odm/lib64` | `libjsoncpp.so`、`android.hardware.sensors-V3-ndk.so`、`libhidltransport.so` | 断言 libjsoncpp 存在；`service list \| grep ICharger` 能查到；`dumpsys battery` 的 `PlugType` 随插拔变化 |
| 首启 provisioning | `/system/etc/gaokun3-postboot.sh` | `device_provisioned=1`、`user_setup_complete=1`、刷新率设置 | 首次开机直落桌面 |

## 规矩

- 补丁必须能回答三个问题：**改了哪个文件**、**为什么**、**怎么验证**。答不全的不进这里。
- 每加一条补丁，同步在 `build/current_verify.sh` 里加一条断言（若可静态验证）。
- 修好的补丁如果可能让旧绕过手段失去必要性（例如 HAL 修好后 SystemUI 补丁），写一条“可撤验证”待办。
