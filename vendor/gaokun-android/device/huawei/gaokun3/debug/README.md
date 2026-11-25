# 调试专用覆盖层（不要进发布镜像）

发布版 `system.erofs` 已摘掉三样东西：`gk3run` root runner、`gk3clean` 清理 service、
`gk3-logdump` 的 `/metadata` 转储钩子。开发需要 root 或开机现场时，把这一层叠回构建树即可。

## 用法

```bash
# 在 v50-build 树上叠加（root 身份跑）
wsl -u root -d Ubuntu-24.04 -- bash /mnt/e/gk3-coloros/vendor/gaokun-android/device/huawei/gaokun3/debug/apply_debug_overlay.sh
# 之后照常 rebuild_system_patched.sh（白名单已含这几个文件，叠加后 diff 只剩 build.prop / update_engine / snapuserd.rc）
```

取消叠加：把 `snapuserd.rc` 里 `-ublk` 和两段 service 删掉、删掉 `gk3-logdump.*`，即回到发布状态。

## 里面是什么

- `gk3-logdump.rc` / `gk3-logdump.sh` —— `post-fs-data` 起一个 root oneshot，隔 20/25/30 秒各 dump 一次
  dmesg / logcat / getprop / ps / SurfaceFlinger / window 到 `/metadata`，并把 tombstone、ANR 一起拷过去。
  排查"开机几秒就重启"这类问题时是唯一可靠的信息源（正常启动路径 gk3boot 不落盘）。
- `gk3run-service.rc` —— `setprop ctl.start gk3run` 起 `/data/local/tmp/gk3run.sh`（root 执行）。
  注意：脚本必须 `chmod 644` 收尾，否则 shell（uid 2000）读不了 root 写的产物。

两份都在 `/metadata`、`/data/local/tmp` 这类用户可写位置落数据，**不能带进发布镜像**。
