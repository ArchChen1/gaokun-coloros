package com.oplus.ota;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;

/** 以 root 跑脚本，逐行回调输出。设备已解锁、su 可用（Shell/超级权限）。 */
final class RootShell {

    interface LineSink {
        void onLine(String line);
    }

    static int run(String scriptPath, LineSink sink) throws IOException, InterruptedException {
        Process p = new ProcessBuilder("su", "-c", "sh " + scriptPath).redirectErrorStream(true).start();
        BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
        String line;
        while ((line = r.readLine()) != null) {
            if (sink != null) {
                sink.onLine(line);
            }
        }
        return p.waitFor();
    }

    /** 单条命令，返回 stdout 第一行（用于 update_engine_client 之类）。 */
    static String exec(String cmd) throws IOException, InterruptedException {
        Process p = new ProcessBuilder("su", "-c", cmd).redirectErrorStream(true).start();
        BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
        StringBuilder sb = new StringBuilder();
        String line;
        while ((line = r.readLine()) != null) {
            sb.append(line).append('\n');
        }
        p.waitFor();
        return sb.toString().trim();
    }

    private RootShell() {
    }
}
