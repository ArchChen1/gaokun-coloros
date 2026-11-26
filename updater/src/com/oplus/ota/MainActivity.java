package com.oplus.ota;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/**
 * 系统更新入口。由 Settings 的「软件更新」偏好以 com.oplus.ota.MAIN 拉起，
 * 默认由 Activity Embedding 内嵌在设置右栏，所以这里只画内容，不画标题栏。
 *
 * 这一版做到「下载 / 校验 / 待安装」为止：App 不碰分区、不申请 root，也不调引擎。
 * 真正的写入由系统侧的写入服务完成（见 docs/OTA-ONLINE-PLAN.md 第 9 节）。
 */
public class MainActivity extends Activity {

    private static final int REQ_PICK = 1001;

    private TextView mStatus;
    private TextView mDetail;
    private TextView mHint;
    private TextView mBtnDownload;
    private TextView mBtnLocal;
    private final Handler mUi = new Handler(Looper.getMainLooper());

    private volatile boolean mBusy;
    private ReleaseSource.Release mRelease;
    /** 已就绪的 payload（校验过 sha 才会被赋值） */
    private File mReadyPayload;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        mStatus = findViewById(R.id.tv_status);
        mDetail = findViewById(R.id.tv_detail);
        mHint = findViewById(R.id.tv_hint);
        mBtnDownload = findViewById(R.id.btn_download);
        mBtnLocal = findViewById(R.id.btn_local);

        mStatus.setText("已是最新版本");
        mDetail.setText("");
        mHint.setText("点「检查更新」从服务端拉取清单；也可以直接选本地 OTA 包。");

        ((TextView) findViewById(R.id.tv_version)).setText(Build.VERSION.RELEASE);
        ((TextView) findViewById(R.id.tv_build)).setText(friendly(getProp("ro.build.version.ota", Build.DISPLAY)));
        ((TextView) findViewById(R.id.tv_slot)).setText(getProp("ro.boot.slot_suffix", "?").replace("_", "").toUpperCase());

        findViewById(R.id.btn_check).setOnClickListener(v -> checkForUpdate());
        mBtnDownload.setOnClickListener(v -> {
            if (mReadyPayload != null) {
                handOff();
            } else if (mRelease != null && mRelease.payload != null) {
                startDownload();
            }
        });
        mBtnLocal.setOnClickListener(v -> pickLocal());

        mBtnDownload.setVisibility(View.GONE);
    }

    // ---------------------------------------------------------------- 在线

    private void checkForUpdate() {
        if (mBusy) {
            return;
        }
        mBusy = true;
        mReadyPayload = null;
        mBtnDownload.setVisibility(View.GONE);
        mStatus.setText("正在检查更新…");
        mDetail.setText("");

        new Thread(() -> {
            String status;
            String detail;
            ReleaseSource.Release rel = null;
            try {
                rel = ReleaseSource.fetch();
                String cur = getProp("ro.build.version.ota", "");
                boolean newer = cur.isEmpty() || !cur.contains(rel.version);
                if (newer) {
                    status = "发现新版本 " + rel.version;
                    if (rel.payload != null) {
                        detail = "更新包 " + fmtGb(rel.payload.size) + " ｜ sha " + rel.payload.sha256.substring(0, 12) + "…";
                    } else {
                        detail = rel.parts.length + " 个分区 ｜ " + fmtGb(rel.totalSize);
                    }
                } else {
                    status = "已是最新版本";
                    detail = "清单版本 " + rel.version;
                }
            } catch (Exception e) {
                status = "检查失败";
                detail = e.getMessage() == null ? e.toString() : e.getMessage();
            }
            final String s = status;
            final String d = detail;
            final ReleaseSource.Release r = rel;
            mUi.post(() -> {
                mBusy = false;
                mRelease = r;
                mStatus.setText(s);
                mDetail.setText(d);
                if (r != null && r.payload != null && !s.equals("已是最新版本")) {
                    mBtnDownload.setText("下载更新包");
                    mBtnDownload.setVisibility(View.VISIBLE);
                    mHint.setText("下载完成后会做 sha256 校验，校验不过自动删掉重来。");
                }
            });
        }, "gk3-ota-check").start();
    }

    private void startDownload() {
        if (mBusy) {
            return;
        }
        final ReleaseSource.Payload pl = mRelease.payload;
        final String url = mRelease.baseUrl + pl.file;
        final File out = new File(getFilesDir(), pl.file);
        if (out.exists() && out.length() == pl.size) {
            mBusy = true;
            mStatus.setText("正在校验已有文件…");
            new Thread(() -> {
                boolean ok;
                try {
                    ok = pl.sha256.equalsIgnoreCase(Downloader.sha256Hex(out));
                } catch (Exception e) {
                    ok = false;
                }
                final boolean fok = ok;
                mUi.post(() -> {
                    mBusy = false;
                    if (fok) {
                        markReady(out, pl);
                    } else {
                        //noinspection ResultOfMethodCallIgnored
                        out.delete();
                        mStatus.setText("本地文件校验不过，已删除");
                        mHint.setText("再点一次「下载更新包」重新下载。");
                    }
                });
            }, "gk3-ota-verify").start();
            return;
        }

        mBusy = true;
        mBtnDownload.setVisibility(View.GONE);
        mStatus.setText("正在下载…");

        new Thread(() -> {
            try {
                String sha = Downloader.download(url, out, pl.size, (done, total) -> {
                    final long dd = done;
                    final long tt = total;
                    mUi.post(() -> {
                        mStatus.setText(String.format("正在下载  %.0f%%", tt > 0 ? dd * 100.0 / tt : 0));
                        mDetail.setText(fmtGb(dd) + " / " + (tt > 0 ? fmtGb(tt) : "?"));
                        mHint.setText(url);
                    });
                });
                final boolean ok = pl.sha256.equalsIgnoreCase(sha);
                mUi.post(() -> {
                    mBusy = false;
                    mDetail.setText("");
                    if (ok) {
                        markReady(out, pl);
                    } else {
                        //noinspection ResultOfMethodCallIgnored
                        out.delete();
                        mStatus.setText("下载完成但校验不过，已删除");
                        mHint.setText("可能是服务器上的包被换过，重试一次。");
                        mBtnDownload.setText("下载更新包");
                        mBtnDownload.setVisibility(View.VISIBLE);
                    }
                });
            } catch (Exception e) {
                mUi.post(() -> {
                    mBusy = false;
                    mStatus.setText("下载中断");
                    mDetail.setText(e.getMessage() == null ? e.toString() : e.getMessage());
                    mHint.setText("再点一次会从断点续传。");
                    mBtnDownload.setText("继续下载");
                    mBtnDownload.setVisibility(View.VISIBLE);
                });
            }
        }, "gk3-ota-download").start();
    }

    // ---------------------------------------------------------------- 本地

    private void pickLocal() {
        Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        i.addCategory(Intent.CATEGORY_OPENABLE);
        i.setType("*/*");
        startActivityForResult(i, REQ_PICK);
    }

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        if (req != REQ_PICK || res != RESULT_OK || data == null || data.getData() == null) {
            return;
        }
        Uri uri = data.getData();
        mStatus.setText("正在导入本地包…");
        mDetail.setText("");
        new Thread(() -> {
            File payload = new File(getFilesDir(), "local_payload.bin");
            String err = null;
            String sha = null;
            try {
                String name = uri.getLastPathSegment() == null ? "" : uri.getLastPathSegment().toLowerCase();
                if (name.endsWith(".zip")) {
                    File tmpZip = new File(getFilesDir(), "local_ota.zip");
                    copyFromUri(uri, tmpZip);
                    try (ZipFile zf = new ZipFile(tmpZip)) {
                        ZipEntry e = zf.getEntry("payload.bin");
                        if (e == null) {
                            throw new Exception("这个 zip 里没有 payload.bin");
                        }
                    }
                    Downloader.extractPayload(tmpZip, payload);
                    //noinspection ResultOfMethodCallIgnored
                    tmpZip.delete();
                } else {
                    copyFromUri(uri, payload);
                }
                sha = Downloader.sha256Hex(payload);
            } catch (Exception e) {
                err = e.getMessage() == null ? e.toString() : e.getMessage();
            }
            final String ferr = err;
            final String fsha = sha;
            final long size = payload.exists() ? payload.length() : 0;
            mUi.post(() -> {
                if (ferr != null) {
                    mStatus.setText("本地包读不了");
                    mDetail.setText(ferr);
                    return;
                }
                markReadyLocal(payload, size, fsha);
            });
        }, "gk3-ota-local").start();
    }

    private void copyFromUri(Uri uri, File dst) throws Exception {
        try (InputStream in = getContentResolver().openInputStream(uri);
             FileOutputStream fos = new FileOutputStream(dst)) {
            if (in == null) {
                throw new Exception("选中的文件打不开");
            }
            byte[] buf = new byte[1 << 20];
            int n;
            while ((n = in.read(buf)) > 0) {
                fos.write(buf, 0, n);
            }
        }
    }

    // ---------------------------------------------------------------- 状态

    private void markReady(File f, ReleaseSource.Payload pl) {
        mReadyPayload = f;
        mStatus.setText("更新包已就绪");
        mDetail.setText(pl.size == 0 ? "" : fmtGb(f.length()) + " ｜ sha " + pl.sha256.substring(0, 12) + "…");
        mBtnDownload.setText("安装");
        mBtnDownload.setVisibility(View.VISIBLE);
        mHint.setText("点「安装」交给系统写入；写入完成后需重启才生效。");
    }

    private void markReadyLocal(File f, long size, String sha) {
        mReadyPayload = f;
        mStatus.setText("本地包已就绪");
        mDetail.setText(fmtGb(size) + " ｜ sha " + (sha == null ? "?" : sha.substring(0, Math.min(12, sha.length()))) + "…");
        mBtnDownload.setText("安装");
        mBtnDownload.setVisibility(View.VISIBLE);
        mHint.setText("这是第三方/本地包，签名由 update_engine 用 otacerts 校验。");
    }

    /**
     * 交给系统侧写入。App 自己没有权限写分区，也不适合直接调引擎，
     * 所以这里只落一份请求文件，由系统写入服务读走后执行。
     */
    private void handOff() {
        File req = new File(getFilesDir(), "request");
        File props = new File(getFilesDir(), mReadyPayload.getName() + ".properties");
        String p = mReadyPayload.getAbsolutePath();
        try (FileOutputStream fos = new FileOutputStream(req)) {
            fos.write(("payload=" + p + "\n").getBytes("UTF-8"));
            fos.write(("props=" + (props.exists() ? props.getAbsolutePath() : "") + "\n").getBytes("UTF-8"));
        } catch (Exception e) {
            mStatus.setText("写入请求失败");
            mDetail.setText(e.toString());
            return;
        }
        if (!new File("/system/bin/gk3otad.sh").exists()) {
            mStatus.setText("已排好队，但写入服务还没装");
            mDetail.setText("当前镜像里没有 gk3otad，需要预装版系统才能直接装。");
            mHint.setText("请求已留在 " + req.getAbsolutePath() + "，预装后会自动执行。");
            return;
        }
        mStatus.setText("已交给系统写入服务");
        mHint.setText("写入在后台进行，进度会显示在这里；完成后提示重启。");
        pollStatus();
    }

    private void pollStatus() {
        final File st = new File(getFilesDir(), "status");
        mUi.postDelayed(new Runnable() {
            @Override
            public void run() {
                if (!st.exists()) {
                    mUi.postDelayed(this, 2000);
                    return;
                }
                try (BufferedReader r = new BufferedReader(new InputStreamReader(
                        new java.io.FileInputStream(st), "UTF-8"))) {
                    String last = null;
                    String line;
                    int lines = 0;
                    while ((line = r.readLine()) != null) {
                        if (line.trim().isEmpty()) {
                            continue;
                        }
                        last = line.trim();
                        lines++;
                    }
                    if (last != null) {
                        mDetail.setText(String.format("%s（%d 行日志）", last, lines));
                        if (last.contains("kSuccess")) {
                            mStatus.setText("写入完成，重启生效");
                        }
                    }
                } catch (Exception ignored) {
                    // 文件正在被写，下一轮再看
                }
                mUi.postDelayed(this, 2000);
            }
        }, 1000);
    }

    private static String fmtGb(long bytes) {
        if (bytes <= 0) {
            return "0";
        }
        if (bytes < 1L << 20) {
            return bytes + " B";
        }
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
