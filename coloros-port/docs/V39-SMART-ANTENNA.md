# v39：关闭 OPlus Smart Antenna（system_server 崩溃主因）

日期：2026-11-21

## v38r3 实测结论

v38r3 的探针成功执行，metadata 中有：

- `/metadata/gk3-v38r3-zygote-trigger`
- `/metadata/gk3-v38r3-bootanim-trigger`
- `/metadata/gk3-v38r3/zygote-early-*`
- `/metadata/gk3-v38r3/zygote-late-*`
- `/metadata/gk3-v38r3/bootanim-*`

关键崩溃：

```text
FATAL EXCEPTION IN SYSTEM PROCESS: OplusWifiCPUThread
java.lang.NullPointerException:
Attempt to read from field
'...OplusWifiTxRxCodecCoverter$MyUEventObserver
...OplusWifiTxRxCodecCoverter.mUEventObserver'
on a null object reference
in OplusWifiStbcMrcSolution.handleBootCompleted()
```

时间点约 `00:01:45.888`，随后 system_server 被杀死，zygote 重新拉起，开机动画回到起点。这个崩溃足以解释“17% → 闪 100% → 重新开始”的循环。

同时还有：

- `com.qti.phone` 的 `ImsSubController` 数组越界；
- `com.android.phone` 的 `CarrierConfigManager` 空指针；
- `com.coloros.bootreg` / `com.android.systemui` 的 `drawRenderNode called on a context with no surface!`。

这些是并行问题，但 system_server 的 OPlus Wi‑Fi 空指针是确定会重启整个 framework 的致命问题。

## 代码定位

`oplus-wifi-service.jar` 中：

```text
com/oplus/server/wifi/antswap/OplusWifiSmartAntenna.isFeatureSupported()
```

只检查两个 feature：

```text
oplus.software.wlan.ant_swap
oplus.software.wlan.smart_antenna
```

当前 `my_product` 的：

```text
/etc/permissions/oplus.features.connectivity.xml
```

声明了：

```xml
<oplus-feature name="oplus.software.wlan.smart_antenna" />
```

因此 WSA 被初始化；但本机没有对应的 WSA/UEvent 硬件初始化，`mUEventObserver` 保持 null，boot completed 回调直接崩溃。

## v39 变更

只从 `my_product` 的 `oplus.features.connectivity.xml` 删除：

```xml
<oplus-feature name="oplus.software.wlan.smart_antenna" />
```

保留：

- v38r2 SELinux policy；
- v38r3 一次性日志探针；
- WFD 关闭；
- 图形、音频、工程师服务、ContextHub 修复；
- boot.img 不变。

不修改 `services.jar`，不修改 IMS，不同时引入第二个变量。

## 产物

```text
system-v38.erofs
3813a078c8556a46ebd988b2265cd2a32553b7e174c76090f4d1389854624c63

vendor_a_v38r3.img
a1e0cc0ee72da5c5740f6d754985f2b0fd1b82280bd49672bf53056640154fc8

odm_v38.img
8ce0d5722ae76a30a6673581581199a535ae7af9227a2482d24dcc604ae7b00b

my_product_a_v39.img
69dbe55ee04628ab4302b6054574deeda8b6305da02b965f271fe393b3a6e0b3

super-coloros-v39.simg
ba2589a4a27b1bb66ab17901f2d0ff72f9289632389544efd18ba72c60aa96d9

release super.img.zst
0bbd3455956212892cb1062c86258e915280bc175dc849e81e6b292fd8ff181d

boot.img
ec30855ece57548950851ccccfb695f169369a2e3d2e2cacca1ebdcda588193b
```

## 验证

- 13 个分区与输入逐字节一致；
- `zstd -t` 通过；
- system、my_product `fsck.erofs` 通过；
- 修改后的 feature XML 仍保留 `security.selinux=u:object_r:system_file:s0`；
- 修改后的 my_product 中不再包含 `oplus.software.wlan.smart_antenna`；
- v38r3 探针仍在 vendor 中。

## 预期与下一观察点

如果 v39 越过当前循环，说明 OPlus Wi‑Fi WSA 是主因。

如果仍循环，优先看新的 `zygote-late-crash.txt`：

- 若 system_server 空指针消失，但出现新的 system_server 异常，继续按新堆栈定位；
- 若只剩 `com.qti.phone` / `com.android.phone`，下一步单独关闭无 modem 的 IMS/telephony 路径；
- 若 `drawRenderNode ... no surface` 仍早于 system_server 崩溃出现，再单独审计 SurfaceFlinger/displayconfig。