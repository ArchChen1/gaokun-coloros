#!/usr/bin/env python3
"""给 oplus-services.jar 的 OplusBatteryService 打充电标志补丁（B 方案）。

背景：ColorOS 的 vendor.oplus.hardware.charger HAL 依赖 /sys/class/oplus_chg，
本机内核没有这套节点，HAL 永远起不来。于是 getPsyBatteryNotify() 返回 -1，
经 ADDITIONAL/UI_BATTERY_CHANGED 广播的 notifycode=-1 传给 SystemUI。

原版 SystemUI.refreshChargingDerivedState() 的精确语义（取自字节码）：
    isFull          = (status == 5) && !(notifyCode & 1024 || notifyCode & 2048)
    batteryCharging = plugged != 0 && !isFull && !(notifyCode & 2 || notifyCode & 32)
即 bit2/bit32 是「不充电」标志，-1 把所有位都置上，于是插电也不显示充电。

补丁：HAL 不可用（返回 -1）时，用标准电池状态合成等价标志：
    0 = 无故障（未插电 / 充电中 / 已充满）
    2 = 已插电但既未充电也未充满
HAL 可用时原样保留厂商值，不影响真机 OPPO 硬件的行为。
"""
import re
import sys

SRC = "/home/cenmin/apitools/svc/smali/com/android/server/OplusBatteryService.smali"
DST = sys.argv[1] if len(sys.argv) > 1 else \
    "/mnt/e/gk3-coloros/work/charge/svc_patched/smali/com/android/server/OplusBatteryService.smali"

text = open(SRC, encoding="utf-8").read()

METHOD = ".method private getDataFromHalByOldInterface(J)V"
start = text.index(METHOD)
end = text.index(".end method", start)
body = text[start:end]

assert body.count(".locals 7") == 1, "方法寄存器声明不是预期的 .locals 7"
body_new = body.replace(".locals 7", ".locals 9", 1)

OLD = """    invoke-interface {v1}, Lcom/android/server/IOplusBatteryServiceFeature;->getPsyBatteryNotify()I

    move-result v1

    iput v1, p0, Lcom/android/server/OplusBatteryService;->mBatteryNotifyCode:I"""

NEW = """    invoke-interface {v1}, Lcom/android/server/IOplusBatteryServiceFeature;->getPsyBatteryNotify()I

    move-result v1

    # gk3 charge: HAL 缺失时这里返回 -1，原版 SystemUI 会当成厂商故障位掩码，
    # 导致插电也不显示充电。用标准电池状态合成等价标志：
    #   0 = 无故障（未插电 / 充电中 / 已充满）
    #   2 = 已插电但既未充电也未充满（SystemUI 的 bit2 表示不充电）
    const/4 v7, -0x1

    if-ne v1, v7, :gk3_notify_donor

    const/4 v1, 0x0

    iget v7, p0, Lcom/android/server/OplusBatteryService;->mPlugType:I

    if-eqz v7, :gk3_notify_donor

    iget v7, p0, Lcom/android/server/OplusBatteryService;->mBatteryStatus:I

    const/4 v8, 0x2

    if-eq v7, v8, :gk3_notify_donor

    const/4 v8, 0x5

    if-eq v7, v8, :gk3_notify_donor

    const/4 v1, 0x2

    :gk3_notify_donor
    iput v1, p0, Lcom/android/server/OplusBatteryService;->mBatteryNotifyCode:I"""

assert body_new.count(OLD) == 1, "补丁锚点不唯一或不存在"
body_new = body_new.replace(OLD, NEW, 1)

out = text[:start] + body_new + text[end:]
open(DST, "w", encoding="utf-8", newline="\n").write(out)
print("已写出", DST)
print("方法内 .locals 7 -> 9，插入 %d 行" % (body_new.count("\n") - body.count("\n")))