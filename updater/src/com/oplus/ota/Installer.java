package com.oplus.ota;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStreamWriter;
import java.util.ArrayList;
import java.util.List;

/** 生成并执行设备端脚本：写 B 槽 → 回读校验 → 切槽。脚本内容都来自资产里的实测布局。 */
final class Installer {

    static final String WORK = "/data/local/tmp/gk3-ota";
    static final String STAGE = WORK + "/stage";

    interface Progress {
        void onLine(String line);
    }

    /** 资产 b_layout.json 里的一条：name/file/start/sectors。 */
    static final class SlotPart {
        String name;
        String file;
        long start;
        long sectors;
    }

    static List<SlotPart> layout(Context ctx) throws Exception {
        String json = readAsset(ctx, "b_layout.json");
        JSONArray arr = new JSONObject(json).getJSONArray("parts");
        List<SlotPart> out = new ArrayList<>();
        for (int i = 0; i < arr.length(); i++) {
            JSONObject o = arr.getJSONObject(i);
            SlotPart p = new SlotPart();
            p.name = o.getString("name");
            p.file = o.getString("file");
            p.start = o.getLong("start");
            p.sectors = o.getLong("sectors");
            out.add(p);
        }
        return out;
    }

    /** 写 write_b.sh；只写清单里出现过的分区。 */
    static File writeScript(Context ctx, ReleaseSource.Release rel) throws Exception {
        List<SlotPart> slot = layout(ctx);
        StringBuilder sb = new StringBuilder();
        sb.append("#!/system/bin/sh\n");
        sb.append("# 由更新器生成：只写 super 的 B 槽区间，A 槽不动\n");
        sb.append("set -e\n");
        sb.append("SUP=/dev/block/by-name/super\n");
        sb.append("SRC=").append(STAGE).append("\n");
        sb.append("w() {\n  echo \"W $1 @$2 ($3)\"\n");
        sb.append("  dd if=\"$SRC/$1\" of=\"$SUP\" bs=512 seek=\"$2\" count=\"$3\" conv=notrunc 2>/dev/null\n");
        sb.append("}\n");
        int n = 0;
        for (ReleaseSource.Part part : rel.parts) {
            for (SlotPart s : slot) {
                if (s.name.equals(part.name)) {
                    sb.append("w ").append(s.file).append(' ').append(s.start).append(' ').append(s.sectors).append('\n');
                    n++;
                }
            }
        }
        sb.append("sync\necho APPLY_OK\n");
        File f = new File(WORK, "write_b.sh");
        write(f, sb.toString());
        return f;
    }

    /** 写 verify_b.sh：回读每个分区，按清单 sha 比对。 */
    static File verifyScript(Context ctx, ReleaseSource.Release rel) throws Exception {
        List<SlotPart> slot = layout(ctx);
        StringBuilder sb = new StringBuilder();
        sb.append("#!/system/bin/sh\n");
        sb.append("SUP=/dev/block/by-name/super\n");
        sb.append("bad=0\n");
        for (ReleaseSource.Part part : rel.parts) {
            for (SlotPart s : slot) {
                if (!s.name.equals(part.name)) {
                    continue;
                }
                sb.append("got=$(dd if=\"$SUP\" bs=512 skip=").append(s.start)
                        .append(" count=").append(s.sectors)
                        .append(" 2>/dev/null | sha256sum | cut -d\" \" -f1)\n");
                sb.append("if [ \"$got\" = \"").append(part.sha256).append("\" ]; then echo \"V OK ").append(part.name)
                        .append("\"; else echo \"V FAIL ").append(part.name).append(" $got\"; bad=1; fi\n");
            }
        }
        sb.append("[ $bad -eq 0 ] && echo VERIFY_OK || echo VERIFY_FAIL\nexit $bad\n");
        File f = new File(WORK, "verify_b.sh");
        write(f, sb.toString());
        return f;
    }

    static boolean apply(Context ctx, ReleaseSource.Release rel, Progress cb) throws Exception {
        File w = writeScript(ctx, rel);
        File v = verifyScript(ctx, rel);
        boolean ok = false;
        int rc = RootShell.run(w.getAbsolutePath(), line -> {
            cb.onLine(line);
            if (line.contains("APPLY_OK")) {
                cb.onLine("WRITE_OK");
            }
        });
        if (rc != 0) {
            cb.onLine("WRITE_FAIL rc=" + rc);
            return false;
        }
        rc = RootShell.run(v.getAbsolutePath(), cb::onLine);
        ok = rc == 0;
        return ok;
    }

    static String switchSlot() throws IOException, InterruptedException {
        return RootShell.exec("update_engine_client --oplus_switch_slot=true");
    }

    static void reboot() throws IOException, InterruptedException {
        RootShell.exec("reboot");
    }

    static String readAsset(Context ctx, String name) throws IOException {
        StringBuilder sb = new StringBuilder();
        try (InputStream in = ctx.getAssets().open(name);
             BufferedReader r = new BufferedReader(new java.io.InputStreamReader(in, "UTF-8"))) {
            String line;
            while ((line = r.readLine()) != null) {
                sb.append(line).append('\n');
            }
        }
        return sb.toString();
    }

    private static void write(File f, String content) throws IOException {
        File dir = f.getParentFile();
        if (dir != null && !dir.exists()) {
            //noinspection ResultOfMethodCallIgnored
            dir.mkdirs();
        }
        try (OutputStreamWriter w = new OutputStreamWriter(new FileOutputStream(f), "UTF-8")) {
            w.write(content);
        }
    }

    private Installer() {
    }
}
