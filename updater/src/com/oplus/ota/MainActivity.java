package com.oplus.ota;

import android.app.Activity;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.widget.ProgressBar;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;

/**
 * 系统更新入口。由 Settings 的「软件更新」偏好以 com.oplus.ota.MAIN 拉起，
 * 默认由 Activity Embedding 内嵌在设置右栏，所以这里只画内容，不画标题栏。
 *
 * 状态机：IDLE → CHECKING → AVAILABLE → DOWNLOADING → VERIFYING → WRITING → SWITCHED
 */
public class MainActivity extends Activity {

    private static final int STEP_NONE = 0;
    private static final int STEP_READY = 1;      // 有新版本，可下载安装
    private static final int STEP_ONLINE = 2;     // 已下载校验通过，待重启生效

    private TextView mStatus;
    private TextView mDetail;
    private TextView mHint;
    private TextView mVersion;
    private TextView mBtn;
    private TextView mLog;
    private ProgressBar mBar;

    private final Handler mUi = new Handler(Looper.getMainLooper());
    private volatile boolean mBusy;
    private volatile boolean mCancelRequested;
    private int mStep = STEP_NONE;
    private ReleaseSource.Release mRelease;
    private final StringBuilder mLogBuf = new StringBuilder();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        mStatus = findViewById(R.id.tv_status);
        mDetail = findViewById(R.id.tv_detail);
        mHint = findViewById(R.id.tv_hint);
        mVersion = findViewById(R.id.tv_version);
        mBtn = findViewById(R.id.btn_check);
        mLog = findViewById(R.id.tv_log);
        mBar = findViewById(R.id.pb);

        mStatus.setText("已是最新版本");
        mDetail.setText("");
        mHint.setText("点「检查更新」从服务端拉取清单。");

        mVersion.setText(Build.VERSION.RELEASE);
        ((TextView) findViewById(R.id.tv_build)).setText(friendly(getProp("ro.build.version.ota", Build.DISPLAY)));
        ((TextView) findViewById(R.id.tv_slot)).setText(getProp("ro.boot.slot_suffix", "?").replace("_", "").toUpperCase());

        mBtn.setOnClickListener(v -> onAction());
    }

    private void onAction() {
        if (mBusy) {
            return;
        }
        switch (mStep) {
            case STEP_READY:
                startInstall();
                break;
            case STEP_ONLINE:
                rebootToApply();
                break;
            default:
                checkForUpdate();
        }
    }

    // ---------- 检查 ----------

    private void checkForUpdate() {
        mBusy = true;
        ui(() -> {
            mStatus.setText("正在检查更新…");
            mDetail.setText("");
            mBar.setVisibility(View.GONE);
            mLog.setVisibility(View.GONE);
        });
        new Thread(() -> {
            try {
                ReleaseSource.Release rel = ReleaseSource.fetch();
                String cur = getProp("ro.build.version.ota", "");
                boolean newer = !cur.contains(rel.version);
                mRelease = newer ? rel : null;
                mStep = newer ? STEP_READY : STEP_NONE;
                mUi.post(() -> {
                    mBusy = false;
                    if (newer) {
                        mStatus.setText("发现新版本 " + rel.version);
                        mDetail.setText(rel.parts.length + " 个分区 ｜ " + fmtGb(rel.totalSize) + " ｜ " + (rel.channel.isEmpty() ? "stable" : rel.channel));
                        mBtn.setText("下载并安装");
                        mHint.setText("下载后写入 B 槽并回读校验，全程不碰当前系统。");
                    } else {
                        mStatus.setText("已是最新版本");
                        mDetail.setText("清单版本 " + rel.version);
                        mBtn.setText("检查更新");
                    }
                });
            } catch (Exception e) {
                mUi.post(() -> {
                    mBusy = false;
                    mStatus.setText("检查失败");
                    mDetail.setText(e.getMessage() == null ? e.toString() : e.getMessage());
                });
            }
        }, "gk3-ota-check").start();
    }

    // ---------- 下载 + 写入 ----------

    private void startInstall() {
        if (mRelease == null) {
            return;
        }
        mBusy = true;
        mCancelRequested = false;
        ui(() -> {
            mStatus.setText("准备中…");
            mDetail.setText("");
            mBar.setVisibility(View.VISIBLE);
            mBar.setProgress(0);
            mLog.setVisibility(View.VISIBLE);
            mLogBuf.setLength(0);
            mBtn.setText("取消");
        });

        new Thread(() -> {
            ReleaseSource.Release rel = mRelease;
            try {
                String mk = RootShell.exec("mkdir -p " + Installer.STAGE + " && chmod 777 " + Installer.WORK + " " + Installer.STAGE);
                File stage = new File(Installer.STAGE);

                Downloader.Result dr = Downloader.downloadAll(rel, stage, new Downloader.Progress() {
                    @Override
                    public void onProgress(long done, long total, String current) {
                        int pct = total <= 0 ? 0 : (int) (done * 100 / total);
                        ui(() -> {
                            mStatus.setText("正在下载 " + pct + "%");
                            mDetail.setText(fmtGb(done) + " / " + fmtGb(total) + " ｜ " + current);
                            mBar.setProgress(pct);
                        });
                    }

                    @Override
                    public boolean isCancelled() {
                        return mCancelRequested;
                    }
                });

                if (!dr.ok) {
                    mUi.post(() -> {
                        mBusy = false;
                        mStatus.setText("下载未完成");
                        mDetail.setText(dr.reason);
                        mStep = STEP_READY;
                        mBtn.setText("重试");
                        mBar.setVisibility(View.GONE);
                    });
                    return;
                }

                ui(() -> {
                    mStatus.setText("正在写入 B 槽…");
                    mDetail.setText("写 super 的 b 区间，约 170 s，别断电");
                });

                boolean ok = Installer.apply(MainActivity.this, rel, line -> appendLog(line));
                if (!ok) {
                    mUi.post(() -> {
                        mBusy = false;
                        mStatus.setText("写入或校验失败");
                        mDetail.setText("当前系统未被修改，可重试");
                        mBtn.setText("重试");
                        mStep = STEP_READY;
                    });
                    return;
                }

                ui(() -> {
                    mStatus.setText("正在切换启动槽…");
                    mDetail.setText("");
                });
                String out = Installer.switchSlot();

                mStep = STEP_ONLINE;
                mUi.post(() -> {
                    mBusy = false;
                    mStatus.setText("已就绪，重启后生效");
                    mDetail.setText(rel.version + " 已写入 B 槽并校验通过");
                    mBtn.setText("重启生效");
                    mHint.setText("重启后进入新版本；如异常，长按电源进 bootloader 或把 /misc 快照 dd 回去即可回 A 槽。");
                    mBar.setVisibility(View.GONE);
                    appendLog(out);
                });
            } catch (Exception e) {
                mUi.post(() -> {
                    mBusy = false;
                    mStatus.setText("出错");
                    mDetail.setText(e.getMessage() == null ? e.toString() : e.getMessage());
                    mBtn.setText("重试");
                });
            }
        }, "gk3-ota-install").start();
    }

    private void rebootToApply() {
        ui(() -> {
            mStatus.setText("正在重启…");
            mBtn.setText("重启生效");
        });
        new Thread(() -> {
            try {
                Installer.reboot();
            } catch (Exception ignored) {
            }
        }, "gk3-ota-reboot").start();
    }

    // ---------- 小工具 ----------

    private void appendLog(String line) {
        mUi.post(() -> {
            int keep = mLogBuf.length() > 600 ? 300 : 0;
            if (keep > 0) {
                mLogBuf.delete(0, keep);
            }
            mLogBuf.append(line).append('\n');
            mLog.setText(mLogBuf.toString());
        });
    }

    private void ui(Runnable r) {
        mUi.post(r);
    }

    private static String fmtGb(long bytes) {
        return String.format("%.2f GB", bytes / 1073741824.0);
    }

    /** 读系统属性：不用隐藏 API，走 getprop。 */
    static String getProp(String key, String fallback) {
        Process p = null;
        try {
            p = new ProcessBuilder("/system/bin/getprop", key).redirectErrorStream(true).start();
            BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
            String line = r.readLine();
            p.waitFor();
            return (line == null || line.trim().isEmpty()) ? fallback : line.trim();
        } catch (Exception e) {
            return fallback;
        } finally {
            if (p != null) {
                p.destroy();
            }
        }
    }

    /** ro.build.version.ota 形如 OPD2513_11.C.17_1170_202611051230，显示成可读的尾段。 */
    private static String friendly(String v) {
        if (v == null || v.isEmpty()) {
            return "";
        }
        int cut = v.indexOf('_');
        return cut > 0 ? v.substring(cut + 1) : v;
    }
}
