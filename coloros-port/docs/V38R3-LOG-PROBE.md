# v38r3 一次性启动循环探针

日期：2026-11-21

## v38r2 实测结果

v38r2 已能进入 ColorOS 开机动画，但界面反复显示“ColorOS 焕新中”：

- 约 17%；
- 一秒闪到 100%；
- 数秒后回到起点，循环。

这说明：

1. v38 新增的 `gaokun3-unavailable-features.xml` 是 v38 无动画阶段的直接变量；
2. v38r2 的 SELinux policy 修改本身没有阻止 zygote/system_server 启动；
3. 当前失败位于 framework/zygote/system_server 或启动动画控制链，而不是 init 没有执行。

## v38r3 变更

基于 v38r2 vendor，仅增加一次性取证：

- `/vendor/bin/v38r3_dump.sh`
- `init.gaokun3.rc` 中的 `exec_background` 触发；
- 不新增常驻 service；
- 不新增轮询循环；
- 不修改 system、ODM、boot 或 v38r2 policy。

触发点：

- `init.svc.zygote=running`：5 秒和 25 秒各抓一次；
- `init.svc.bootanim=stopped`：2 秒后抓一次；
- `sys.boot_completed=1`：仅写完成标记。

每次抓取：

- `getprop`
- `ps -A`
- `/proc/mounts`
- `dmesg`
- `logcat -b all`
- `logcat -b crash`
- `/data/tombstones`、`/data/anr`、`/data/system/dropbox` 目录列表

探针标记写入 `/metadata/gk3-v38r3/`，init 触发标记写入：

- `/metadata/gk3-v38r3-zygote-trigger`
- `/metadata/gk3-v38r3-bootanim-trigger`

## 产物

```text
system-v38.erofs
3813a078c8556a46ebd988b2265cd2a32553b7e174c76090f4d1389854624c63

vendor_a_v38r3.img
a1e0cc0ee72da5c5740f6d754985f2b0fd1b82280bd49672bf53056640154fc8

odm_v38.img
8ce0d5722ae76a30a6673581581199a535ae7af9227a2482d24dcc604ae7b00b

super-coloros-v38r3.simg
76b35b9fc486e8cf8e8e47432a918451b997757593b73822371ec371e9bde639

release super.img.zst
8a2d6ec2209b5cb4d6c526392c38c714d122133392e8a55d14b01292a77b5503

boot.img
ec30855ece57548950851ccccfb695f169369a2e3d2e2cacca1ebdcda588193b
```

## 验证

- `zstd -t` 通过；
- `simg2img` + `lpunpack` 成功；
- 13 个分区与构建输入逐字节一致；
- vendor `e2fsck -fn` 通过；
- 探针权限 `0755 root:root`；
- rc 中只使用 `exec_background`，不会阻塞 init。

## 运行后检查顺序

1. 先确认 `/metadata/gk3-v38r3-zygote-trigger` 是否存在；
2. 再确认 `/metadata/gk3-v38r3/zygote-early.done`、`zygote-late.done`；
3. 优先看 `zygote-early-logcat.txt` 和 `zygote-late-crash.txt`；
4. 对比 `ps` 中 `zygote`、`system_server`、`surfaceflinger` 的 PID 是否变化；
5. 若 trigger 存在但目录不存在，说明 init 的 `exec_background` 被 SELinux/路径权限拦住，而不是 framework 日志缺失。