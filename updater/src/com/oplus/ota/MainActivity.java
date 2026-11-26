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
    /** 安装交接前记下目标槽位，重启后据此判断「这次装成了没有」。 */
    private static final String PENDING = "pending.json";

    private TextView mStatus;
    private TextView mDetail;
    private TextView mHint;
    private TextView mBtnDownload;
    private TextView mBtnLocal;
    private TextView mBtnClean;
    private final Handler mUi = new Handler(Looper.getMainLooper());

    private volatile boolean mBusy;
    private volatile boolean mPolling;
    private volatile boolean mPollSuppressed;
    private volatile long mHandoffAt;
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
        mBtnClean = findViewById(R.id.btn_clean);

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
        mBtnClean.setOnClickListener(v -> manualClean());

        mBtnDownload.setVisibility(View.GONE);
        mBtnClean.setVisibility(View.GONE);

        // 装完重启进新系统：把上一轮下载的包顺手删掉（判断依据见 afterBootCheck）
        afterBootCheck();
        // 页面被划掉再回来、或 App 被系统杀掉后重启：接着显示写入进度
        if (new File(getFilesDir(), "request.done").exists()) {
            pollStatus();
        }
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
                final File props = new File(getFilesDir(), pl.file + ".properties");
                String perr = null;
                if (ok) {
                    try {
                        Downloader.fetch(url + ".properties", props);
                    } catch (Exception e) {
                        perr = e.toString();
                    }
                }
                final String fperr = perr;
                mUi.post(() -> {
                    mBusy = false;
                    mDetail.setText("");
                    if (ok && fperr == null) {
                        markReady(out, pl);
                    } else if (ok) {
                        //noinspection ResultOfMethodCallIgnored
                        out.delete();
                        props.delete();
                        mStatus.setText("缺 payload 属性文件，已删除");
                        mDetail.setText(fperr);
                        mHint.setText("服务端要一并提供 " + pl.file + ".properties。");
                        mBtnDownload.setText("下载更新包");
                        mBtnDownload.setVisibility(View.VISIBLE);
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
        mHint.setText("写入由系统服务执行：关掉这个页面、划掉卡片都不会中断；完成后提示重启。");
        writePending(currentSlot().equals("a") ? "b" : "a");
        // 上一轮的 status 还留着（内容是上次的 rc=0），不清掉的话页面第一次刷新会显示成
        // 「写入结束」，这一轮的真实进度就再也看不到了。
        //noinspection ResultOfMethodCallIgnored
        new File(getFilesDir(), "status").delete();
        mHandoffAt = System.currentTimeMillis();
        pollStatus();
    }

    private void pollStatus() {
        if (mPolling) {
            return;
        }
        mPolling = true;
        final File st = new File(getFilesDir(), "status");
        mUi.postDelayed(new Runnable() {
            @Override
            public void run() {
                if (mPollSuppressed) {
                    mPolling = false;
                    return;
                }
                if (!st.exists()) {
                    mUi.postDelayed(this, 2000);
                    return;
                }
                if (mHandoffAt > 0 && st.lastModified() + 2000 < mHandoffAt) {
                    // 还是上一轮留下的旧结果，等写入服务把它清空重写
                    mStatus.setText("已交给系统写入服务");
                    mDetail.setText("等系统服务接手…");
                    mUi.postDelayed(this, 2000);
                    return;
                }
                String text = null;
                try {
                    text = readAll(st);
                } catch (Exception ignored) {
                    // 文件正在被写，下一轮再看
                }
                if (text == null || text.trim().isEmpty()) {
                    mUi.postDelayed(this, 2000);
                    return;
                }

                String last = lastLine(text);
                int lines = countLines(text);

                if (hasDoneLine(text)) {
                    mStatus.setText(last != null && last.contains("kSuccess") ? "写入完成，重启生效" : "写入结束");
                    if (last != null) {
                        mDetail.setText(last + "（" + lines + " 行日志）");
                    }
                    mPolling = false;
                    refreshCache();
                    return;
                }

                String pct = lastPercent(text);
                String phase = lastPhase(text);
                if (pct != null) {
                    long total = mReadyPayload == null ? 0 : mReadyPayload.length();
                    mStatus.setText("正在写入 " + pct + "%");
                    String bytes = total > 0
                            ? "约 " + fmtGb((long) (total * Double.parseDouble(pct) / 100.0)) + " / " + fmtGb(total)
                            : "";
                    mDetail.setText(phase == null ? bytes : (bytes.isEmpty() ? phase : bytes + " ｜ " + phase));
                } else {
                    mStatus.setText(phase != null ? phase : "正在写入…");
                    if (last != null) {
                        mDetail.setText(last + "（" + lines + " 行日志）");
                    }
                }
                mUi.postDelayed(this, 2000);
            }
        }, 1000);
    }

    /** 日志里可能带 \r 覆盖式进度，两种换行都当分隔。 */
    private static String readAll(File f) throws Exception {
        StringBuilder sb = new StringBuilder();
        try (BufferedReader r = new BufferedReader(new InputStreamReader(new java.io.FileInputStream(f), "UTF-8"))) {
            char[] buf = new char[4096];
            int n;
            while ((n = r.read(buf)) > 0) {
                sb.append(buf, 0, n);
            }
        }
        return sb.toString();
    }

    private static String[] lines(String text) {
        return text.split("\\r\\n|\\r|\\n");
    }

    private static int countLines(String text) {
        int c = 0;
        for (String s : lines(text)) {
            if (!s.trim().isEmpty()) {
                c++;
            }
        }
        return c;
    }

    private static String lastLine(String text) {
        String last = null;
        for (String s : lines(text)) {
            if (!s.trim().isEmpty()) {
                last = s.trim();
            }
        }
        return last;
    }

    private static boolean hasDoneLine(String text) {
        for (String s : lines(text)) {
            if (s.trim().startsWith("rc=")) {
                return true;
            }
        }
        return false;
    }

    /** 最后一个 ≤100 的百分比；没有就返回 null（引擎不一定会打进度）。 */
    private static String lastPercent(String text) {
        // 引擎的实际输出长这样：onStatusUpdate(UPDATE_STATUS_DOWNLOADING (3), 0.210037)
        // 是 0..1 的小数，不是百分号；优先用它。
        String frac = null;
        java.util.regex.Matcher f = java.util.regex.Pattern.compile(
                "onStatusUpdate\\(UPDATE_STATUS_[A-Z_]+\\s*\\(\\d+\\),\\s*(\\d+\\.\\d+)\\)").matcher(text);
        while (f.find()) {
            frac = f.group(1);
        }
        if (frac != null) {
            double v = Double.parseDouble(frac) * 100.0;
            return v > 100 ? null : String.format(java.util.Locale.US, "%.0f", v);
        }

        String hit = null;
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("(?<![\\d.])(\\d{1,3}(?:\\.\\d{1,2})?)\\s*%").matcher(text);
        while (m.find()) {
            if (Double.parseDouble(m.group(1)) <= 100) {
                hit = m.group(1);
            }
        }
        return hit;
    }

    /** 引擎的 UPDATE_STATUS_* 翻成人话。 */
    private static String lastPhase(String text) {
        String hit = null;
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("UPDATE_STATUS_([A-Z_]+)").matcher(text);
        while (m.find()) {
            hit = m.group(1);
        }
        if (hit == null) {
            return null;
        }
        switch (hit) {
            case "DOWNLOADING":
                return "正在写入分区";
            case "VERIFYING":
                return "正在校验写入结果";
            case "FINALIZING":
                return "正在收尾";
            case "UPDATED_NEED_REBOOT":
                return "写入完成，重启生效";
            case "CLEANUP_PREVIOUS_UPDATE":
                return "正在清理旧槽";
            case "ATTEMPTING_ROLLBACK":
                return "正在回滚";
            default:
                return null;
        }
    }

    // ---------------------------------------------------------------- 清理

    private static String currentSlot() {
        return getProp("ro.boot.slot_suffix", "").replace("_", "");
    }

    private void writePending(String targetSlot) {
        try (FileOutputStream fos = new FileOutputStream(new File(getFilesDir(), PENDING))) {
            fos.write(("{\"target\":\"" + targetSlot + "\"}").getBytes("UTF-8"));
        } catch (Exception ignored) {
            // 记不下来最多是这次不自动清理，不影响安装
        }
    }

    /**
     * 上电进系统后：如果这次真的装成了，就把上一轮的包删掉。
     *
     * 装成了 = 三件事同时成立：交接前记下的目标槽 == 现在跑的这个槽；该槽的写入日志里有
     * kSuccess。任一不成立（引擎报错没写进去、写了但回滚到原槽、根本没装过）都不删，
     * 让人还能重试。
     */
    private void afterBootCheck() {
        new Thread(() -> {
            if (runInFlight()) {
                // 写入还没结束（页面被划掉又打开时就会遇到）：这时候绝不能清 pending，
                // 否则重启进新系统后没人知道这次是「装成了」。
                refreshCache();
                return;
            }
            File pend = new File(getFilesDir(), PENDING);
            final boolean hadPending = pend.exists();
            boolean installed = false;
            long freed = 0;
            if (hadPending) {
                String target = readPendingTarget(pend);
                installed = target != null && target.equals(currentSlot()) && statusHasSuccess();
                if (installed) {
                    freed = cleanCache();
                }
                //noinspection ResultOfMethodCallIgnored
                pend.delete();
            }
            final boolean ok = installed;
            final long f = freed;
            mUi.post(() -> {
                if (ok) {
                    mPollSuppressed = true;
                    mStatus.setText("更新已生效，旧包已清理");
                    mDetail.setText("释放 " + fmtGb(f));
                    mHint.setText("安装完重启进新系统会自动清掉下载的 payload，不再白占空间。");
                } else if (hadPending) {
                    mHint.setText("上次更新没有生效（仍在原槽位），更新包已保留，可以重新安装。");
                }
                refreshCache();
            });
        }, "gk3-ota-clean").start();
    }

    /** 写入还在进行（请求没被取走，或 status 里还没有 rc= 结论）就别做「装成没装成」的判定。 */
    private boolean runInFlight() {
        if (new File(getFilesDir(), "request").exists()) {
            return true;
        }
        File st = new File(getFilesDir(), "status");
        if (!st.exists()) {
            return false;
        }
        try {
            return !hasDoneLine(readAll(st));
        } catch (Exception e) {
            return true;
        }
    }

    private void manualClean() {
        if (mBusy) {
            return;
        }
        if (new File(getFilesDir(), "request").exists()) {
            mHint.setText("写入服务还没取走请求，现在清理会打断安装。");
            return;
        }
        long freed = cleanCache();
        mStatus.setText("已清理更新包");
        mDetail.setText("释放 " + fmtGb(freed));
        mHint.setText("要再装就得重新下载 / 重新选包。");
        refreshCache();
    }

    /** 后台算一下私有目录里还压着多少缓存包，有就显示清理按钮。 */
    private void refreshCache() {
        new Thread(() -> {
            final long size = cacheSize();
            mUi.post(() -> {
                if (size > 0) {
                    mBtnClean.setText("清理已下载包（" + fmtGb(size) + "）");
                    mBtnClean.setVisibility(View.VISIBLE);
                } else {
                    mBtnClean.setVisibility(View.GONE);
                }
            });
        }, "gk3-ota-size").start();
    }

    /** 只删下载缓存；status / pending / request 这些控制文件不碰。 */
    private long cleanCache() {
        File[] fs = getFilesDir().listFiles();
        if (fs == null) {
            return 0;
        }
        long freed = 0;
        for (File f : fs) {
            String n = f.getName();
            if (!(n.endsWith(".bin") || n.endsWith(".bin.properties") || n.endsWith(".zip"))) {
                continue;
            }
            long len = f.length();
            if (f.delete()) {
                freed += len;
            }
        }
        return freed;
    }

    private long cacheSize() {
        File[] fs = getFilesDir().listFiles();
        if (fs == null) {
            return 0;
        }
        long total = 0;
        for (File f : fs) {
            String n = f.getName();
            if (n.endsWith(".bin") || n.endsWith(".bin.properties") || n.endsWith(".zip")) {
                total += f.length();
            }
        }
        return total;
    }

    private static String readPendingTarget(File f) {
        try (BufferedReader r = new BufferedReader(new InputStreamReader(new java.io.FileInputStream(f), "UTF-8"))) {
            String s = r.readLine();
            if (s == null) {
                return null;
            }
            int k = s.indexOf("\"target\"");
            if (k < 0) {
                return null;
            }
            int q = s.indexOf('"', s.indexOf(':', k));
            int q2 = s.indexOf('"', q + 1);
            return (q < 0 || q2 < 0) ? null : s.substring(q + 1, q2);
        } catch (Exception e) {
            return null;
        }
    }

    private boolean statusHasSuccess() {
        File st = new File(getFilesDir(), "status");
        if (!st.exists()) {
            return false;
        }
        try (BufferedReader r = new BufferedReader(new InputStreamReader(new java.io.FileInputStream(st), "UTF-8"))) {
            String line;
            while ((line = r.readLine()) != null) {
                if (line.contains("kSuccess")) {
                    return true;
                }
            }
        } catch (Exception ignored) {
            // 读不到就当没装成，包留着更安全
        }
        return false;
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
