package com.oplus.ota;

import android.app.Activity;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.InputStreamReader;

/**
 * 系统更新入口。由 Settings 的「软件更新」偏好以 com.oplus.ota.MAIN 拉起，
 * 默认由 Activity Embedding 内嵌在设置右栏，所以这里只画内容，不画标题栏。
 */
public class MainActivity extends Activity {

    private TextView mStatus;
    private TextView mDetail;
    private TextView mHint;
    private TextView mVersion;
    private final Handler mUi = new Handler(Looper.getMainLooper());
    private volatile boolean mBusy;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        mStatus = findViewById(R.id.tv_status);
        mDetail = findViewById(R.id.tv_detail);
        mHint = findViewById(R.id.tv_hint);
        mVersion = findViewById(R.id.tv_version);

        mStatus.setText("已是最新版本");
        mDetail.setText("");
        mHint.setText("点「检查更新」从服务端拉取清单。");

        mVersion.setText(Build.VERSION.RELEASE);
        ((TextView) findViewById(R.id.tv_build)).setText(friendly(getProp("ro.build.version.ota", Build.DISPLAY)));
        ((TextView) findViewById(R.id.tv_slot)).setText(getProp("ro.boot.slot_suffix", "?").replace("_", "").toUpperCase());

        findViewById(R.id.btn_check).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                checkForUpdate();
            }
        });
    }

    private void checkForUpdate() {
        if (mBusy) {
            return;
        }
        mBusy = true;
        mStatus.setText("正在检查更新…");
        mDetail.setText("");

        new Thread(new Runnable() {
            @Override
            public void run() {
                String status;
                String detail;
                try {
                    ReleaseSource.Release rel = ReleaseSource.fetch();
                    String cur = getProp("ro.build.version.ota", "");
                    boolean newer = !rel.version.isEmpty() && !cur.contains(rel.version);
                    status = newer ? "发现新版本 " + rel.version : "已是最新版本";
                    detail = "清单版本 " + rel.version
                            + " ｜ " + (rel.parts == null ? 0 : rel.parts.length) + " 个分区"
                            + " ｜ " + String.format("%.2f GB", rel.totalSize / 1073741824.0);
                } catch (Exception e) {
                    status = "检查失败";
                    detail = e.getMessage() == null ? e.toString() : e.getMessage();
                }
                final String s = status;
                final String d = detail;
                mUi.post(new Runnable() {
                    @Override
                    public void run() {
                        mBusy = false;
                        mStatus.setText(s);
                        mDetail.setText(d);
                    }
                });
            }
        }, "gk3-ota-check").start();
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
