#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 vahiru 的 3 条补丁手工移植进 7.2.9-gk3 树（原补丁上下文对不上）。
- ec-usb/0001: 电池 0x82 状态位按位解码 + CAPACITY_LEVEL + ec_raw 诊断
- ec-usb/0016: 电池温度 0x9C 上报（0.1K -> 0.1C，越界 -ENODATA）
- core/0001:   efi-pstore 等 efivar ops 到位再注册（通知链 + workqueue，幂等）
每个替换先断言唯一命中，任何一个不满足就整体不落盘。
"""
import sys

TREE = "/home/cenmin/kbuild/linux-7.2.9-gk3"
BAT = TREE + "/drivers/power/supply/huawei-gaokun-battery.c"
EFI = TREE + "/drivers/firmware/efi/efi-pstore.c"

def apply(path, edits):
    src = open(path, encoding="utf-8").read()
    out = src
    for old, new in edits:
        n = out.count(old)
        assert n == 1, f"{path}: 锚点命中 {n} 次（须 1）:\n{old[:120]}"
        out = out.replace(old, new)
    return src, out

bat_edits = [
    # --- 0001: 状态位掩码
    ("#define EC_BAT_FULL\t\tBIT(3)\n",
     "#define EC_BAT_FULL\t\tBIT(3)\n"
     "#define EC_BAT_STATUS_KNOWN\t(EC_BAT_DISCHARGING | EC_BAT_CHARGING | \\\n"
     "\t\t\t\t EC_BAT_CRITICAL | EC_BAT_FULL)\n"),
    # --- 0016: 0x9C 定义为温度
    ("/* 0x9C: ? */",
     "#define EC_BAT_TEMP\t\t0x9C"),
    # --- 0016: 开尔文换算与合法区间
    ("#define MILLI_TO_MICRO\t\t1000\n",
     "#define MILLI_TO_MICRO\t\t1000\n\n"
     "#define KELVIN_OFFSET\t\t2731\n"
     "#define EC_BAT_TEMP_MIN\t\t(KELVIN_OFFSET - 400)\t/* -40.0 C */\n"
     "#define EC_BAT_TEMP_MAX\t\t(KELVIN_OFFSET + 1200)\t/* 120.0 C */\n"),
    # --- 0001: critical_max_capacity 模块参数
    ("#define DELAY_MODE\t4\n",
     "#define DELAY_MODE\t4\n\n"
     "/*\n"
     " * Escalate EC_BAT_CRITICAL to CAPACITY_LEVEL_CRITICAL only when the reported\n"
     " * capacity is at or below critical_max_capacity so an early EC critical bit\n"
     " * cannot trigger a premature userspace shutdown (0 = only at 0%).\n"
     " */\n"
     "static int critical_max_capacity = 2;\n"
     "module_param(critical_max_capacity, int, 0644);\n"
     "MODULE_PARM_DESC(critical_max_capacity,\n"
     "\t\t \"Report CAPACITY_LEVEL Critical on the EC critical bit only at or below this capacity (%)\");\n"),
    # --- 0016: 状态块字段改名
    ("\t__le16 unknown2;\t/* 0x9C */",
     "\t__le16 temp_now;\t/* 0x9C, 0.1 K */"),
    # --- 0001: 保存原始状态字节
    ("\tint charge_now;\n\tint online;",
     "\tint charge_now;\n\tu8 bat_status_raw;\t/* Last successfully read raw 0x82 byte */\n\tint online;"),
    # --- 0001: 按位解码 + 容量等级
    ("""static void gaokun_psy_update_bat_charge(struct gaokun_psy *ecbat)
{
\tu8 charge;

\tgaokun_ec_psy_read_byte(ecbat->ec, EC_BAT_STATUS, &charge);

\tswitch (charge) {
\tcase EC_BAT_CHARGING:
\t\tecbat->charge_now = POWER_SUPPLY_STATUS_CHARGING;
\t\tbreak;
\tcase EC_BAT_DISCHARGING:
\t\tecbat->charge_now = POWER_SUPPLY_STATUS_DISCHARGING;
\t\tbreak;
\tcase EC_BAT_FULL:
\t\tecbat->charge_now = POWER_SUPPLY_STATUS_FULL;
\t\tbreak;
\tdefault:
\t\tdev_warn(ecbat->dev, "unknown charge state %d\\n", charge);
\t}
}
""",
     """/*
 * Decode register 0x82 bitwise. Bits 0..2 match the ACPI _BST state bitmask
 * (bit 0 discharging, bit 1 charging, bit 2 critical) and bit 3 indicates full.
 * Matching the whole byte with a switch statement left charge_now stale on 0x00
 * (plugged in, not charging) or combined states such as 0x05 (discharging +
 * critical).
 *
 * Prioritize discharging over other bits so a stale charging bit never blocks
 * low-battery shutdown; then check full and charging; if no bit is set, report
 * NOT_CHARGING when on AC power and DISCHARGING otherwise.
 */
static int gaokun_psy_decode_bat_status(struct gaokun_psy *ecbat, u8 raw)
{
\tif (raw & EC_BAT_DISCHARGING)
\t\treturn POWER_SUPPLY_STATUS_DISCHARGING;
\tif (raw & EC_BAT_FULL)
\t\treturn POWER_SUPPLY_STATUS_FULL;
\tif (raw & EC_BAT_CHARGING)
\t\treturn POWER_SUPPLY_STATUS_CHARGING;

\tif (gaokun_psy_get_adp_status(ecbat))
\t\treturn POWER_SUPPLY_STATUS_UNKNOWN;

\treturn ecbat->online ? POWER_SUPPLY_STATUS_NOT_CHARGING :
\t\t\t       POWER_SUPPLY_STATUS_DISCHARGING;
}

static void gaokun_psy_update_bat_charge(struct gaokun_psy *ecbat)
{
\tu8 charge;

\t/* Keep the previous status if the EC read fails */
\tif (gaokun_ec_psy_read_byte(ecbat->ec, EC_BAT_STATUS, &charge))
\t\treturn;

\tif (charge & ~EC_BAT_STATUS_KNOWN)
\t\tdev_warn_once(ecbat->dev, "unknown charge state bits 0x%02x\\n", charge);

\tecbat->bat_status_raw = charge;
\tecbat->charge_now = gaokun_psy_decode_bat_status(ecbat, charge);
}

/*
 * When capacity_level is exposed in sysfs, Android's BatteryService shuts down
 * only when capacity_level == Critical rather than falling back to the legacy
 * "capacity <= 0 && status != Charging" rule:
 *
 *   - Report Critical at 0% unless the EC reports charging and rate_now is
 *     positive, covering the case where a weak USB power source asserts the
 *     charging bit while the battery continues to drain to 0%.
 *   - Report Critical when EC_BAT_CRITICAL is set and capacity is at or below
 *     critical_max_capacity (unless actively gaining charge), leaving a small
 *     safety margin for the EC's own low-battery threshold.
 *
 * Note: rate_now is treated as signed positive when charging (+15..+106 mA
 * observed while charging from a host USB port at 92% SOC). If a future EC
 * firmware revision uses the opposite sign convention, verify both weak-supply
 * drain and charger attach at 0%.
 */
static int gaokun_psy_capacity_level(struct gaokun_psy *ecbat)
{
\tint cap = le16_to_cpu(ecbat->status.percentage_now);
\tint rate = (s16)le16_to_cpu(ecbat->status.rate_now);
\tu8 raw = ecbat->bat_status_raw;
\tbool gaining = (raw & EC_BAT_CHARGING) && !(raw & EC_BAT_DISCHARGING) &&
\t\t       rate > 0;

\tif (!gaining && (cap <= 0 ||
\t\t\t ((raw & EC_BAT_CRITICAL) && cap <= critical_max_capacity)))
\t\treturn POWER_SUPPLY_CAPACITY_LEVEL_CRITICAL;

\tif (ecbat->charge_now == POWER_SUPPLY_STATUS_FULL || cap >= 100)
\t\treturn POWER_SUPPLY_CAPACITY_LEVEL_FULL;

\tif (raw & EC_BAT_CRITICAL)
\t\treturn POWER_SUPPLY_CAPACITY_LEVEL_LOW;

\treturn POWER_SUPPLY_CAPACITY_LEVEL_NORMAL;
}

/*
 * Word 0x9c reports the battery temperature in tenths of a Kelvin. Reject
 * values outside [-40.0 C, 120.0 C] with -ENODATA so an uninitialized (0x0000)
 * or failed (0xffff) read cannot trigger an emergency over-temperature
 * shutdown in userspace.
 */
static int gaokun_psy_get_temp(struct gaokun_psy *ecbat, int *temp)
{
\tu16 raw = le16_to_cpu(ecbat->status.temp_now);

\tif (raw < EC_BAT_TEMP_MIN || raw > EC_BAT_TEMP_MAX)
\t\treturn -ENODATA;

\t*temp = (int)raw - KELVIN_OFFSET;
\treturn 0;
}
"""),
    # --- 0001+0016: get_property 增加两个 case
    ("""	case POWER_SUPPLY_PROP_CAPACITY:
		val->intval = le16_to_cpu(ecbat->status.percentage_now);
		break;

	case POWER_SUPPLY_PROP_MODEL_NAME:""",
     """	case POWER_SUPPLY_PROP_CAPACITY:
		val->intval = le16_to_cpu(ecbat->status.percentage_now);
		break;

	case POWER_SUPPLY_PROP_CAPACITY_LEVEL:
		val->intval = gaokun_psy_capacity_level(ecbat);
		break;

	case POWER_SUPPLY_PROP_TEMP:
		ret = gaokun_psy_get_temp(ecbat, &val->intval);
		if (ret)
			return ret;
		break;

	case POWER_SUPPLY_PROP_MODEL_NAME:"""),
    # --- 0001+0016: props 数组
    ("""	POWER_SUPPLY_PROP_CAPACITY,
	POWER_SUPPLY_PROP_MODEL_NAME,""",
     """	POWER_SUPPLY_PROP_CAPACITY,
	POWER_SUPPLY_PROP_CAPACITY_LEVEL,
	POWER_SUPPLY_PROP_TEMP,
	POWER_SUPPLY_PROP_MODEL_NAME,"""),
    # --- 0001(+0016 改名): ec_raw 诊断属性
    ("static DEVICE_ATTR_RW(smart_charge_delay);\n",
     """static DEVICE_ATTR_RW(smart_charge_delay);

/*
 * ec_raw: read-only diagnostic attribute exposing the raw 0x82 status byte and
 * the three undocumented words already fetched by the driver: 0x98 and 0x9C
 * (from the _BST status block) and 0xA0 (from the _BIX info block), without
 * issuing extra EC transactions.
 */
static ssize_t ec_raw_show(struct device *dev, struct device_attribute *attr,
			   char *buf)
{
	struct power_supply *psy = to_power_supply(dev);
	struct gaokun_psy *ecbat = power_supply_get_drvdata(psy);

	if (!gaokun_psy_bat_present(ecbat))
		return -ENODEV;

	gaokun_psy_get_bat_status(ecbat);

	return sysfs_emit(buf, "status=0x%02x w98=0x%04x w9c=0x%04x wa0=0x%04x\\n",
			  ecbat->bat_status_raw,
			  le16_to_cpu(ecbat->status.unknown1),
			  le16_to_cpu(ecbat->status.temp_now),
			  le16_to_cpu(ecbat->info.unknown3));
}

static DEVICE_ATTR_RO(ec_raw);
"""),
    ("\t&dev_attr_smart_charge_delay.attr,\n",
     "\t&dev_attr_smart_charge_delay.attr,\n\t&dev_attr_ec_raw.attr,\n"),
]

efi_edits = [
    ("#include <linux/ucs2_string.h>\n",
     "#include <linux/ucs2_string.h>\n"
     "#include <linux/notifier.h>\n"
     "#include <linux/workqueue.h>\n"),
    ("static int efivars_pstore_init(void);\nstatic void efivars_pstore_exit(void);\n",
     """static int efivars_pstore_init(void);
static void efivars_pstore_exit(void);

static void efi_pstore_init_work_fn(struct work_struct *work)
{
	efivars_pstore_init();
}
static DECLARE_WORK(efi_pstore_init_work, efi_pstore_init_work_fn);

/*
 * On platforms where the efivar operations are supplied by a driver that
 * probes after this file's initcall -- e.g. sc8280xp laptops, where variable
 * access goes through qcom_qseecom_uefisecapp and efivars is not registered
 * until ~0.76s into boot -- efivars_pstore_init() runs too early, sees
 * efivar_supports_writes() == false and silently gives up forever. Listen on
 * the efivar ops notifier so the backend is registered as soon as variable
 * access becomes available.
 */
static int efi_pstore_ops_notifier(struct notifier_block *nb,
				   unsigned long event, void *data)
{
	switch (event) {
	case EFIVAR_OPS_RDWR:
		/*
		 * Must not register from here: efivars_register() holds
		 * efivars_lock across this notifier call, and pstore_register()
		 * reaches efi_pstore_open() -> efivar_lock(), which takes the
		 * very same semaphore. Defer to process context.
		 */
		schedule_work(&efi_pstore_init_work);
		break;
	default:
		return NOTIFY_DONE;
	}

	return NOTIFY_OK;
}

static struct notifier_block efi_pstore_nb = {
	.notifier_call = efi_pstore_ops_notifier,
};
"""),
    ("static int efivars_pstore_init(void)\n{\n\tif (!efivar_supports_writes())",
     "static int efivars_pstore_init(void)\n{\n\tif (efi_pstore_info.bufsize)\n\t\treturn 0;\n\n\tif (!efivar_supports_writes())"),
    ("module_init(efivars_pstore_init);\nmodule_exit(efivars_pstore_exit);\n",
     """static int __init efi_pstore_module_init(void)
{
	blocking_notifier_chain_register(&efivar_ops_nh, &efi_pstore_nb);

	/* efivars may already be up, in which case the notifier never fires. */
	return efivars_pstore_init();
}

static void __exit efi_pstore_module_exit(void)
{
	blocking_notifier_chain_unregister(&efivar_ops_nh, &efi_pstore_nb);
	cancel_work_sync(&efi_pstore_init_work);
	efivars_pstore_exit();
}

module_init(efi_pstore_module_init);
module_exit(efi_pstore_module_exit);
"""),
]

def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "check"
    results = []
    for path, edits in ((BAT, bat_edits), (EFI, efi_edits)):
        src, out = apply(path, edits)
        results.append((path, src, out))
        print(f"OK {len(edits)} 处替换全部唯一命中: {path}")
    if mode == "write":
        for path, src, out in results:
            open(path, "w", encoding="utf-8", newline="").write(out)
            print(f"已写入 {path}")
    else:
        print("check 模式，未写入。加 write 参数落盘。")

if __name__ == "__main__":
    main()