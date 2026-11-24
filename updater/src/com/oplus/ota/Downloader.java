package com.oplus.ota;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.RandomAccessFile;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;

/** 逐分区下载到暂存目录，支持断点续传（HTTP Range），下完即校验 sha256。 */
final class Downloader {

    interface Progress {
        /** @param done 已完成字节（全部分区合计） @param total 全部分区合计 */
        void onProgress(long done, long total, String current);

        boolean isCancelled();
    }

    static final class Result {
        boolean ok;
        String reason;
    }

    static Result downloadAll(ReleaseSource.Release rel, File stage, Progress cb) {
        long total = 0;
        for (ReleaseSource.Part p : rel.parts) {
            total += p.size;
        }
        long done = 0;
        for (ReleaseSource.Part p : rel.parts) {
            if (cb.isCancelled()) {
                Result r = new Result();
                r.reason = "已取消";
                return r;
            }
            File out = new File(stage, p.file);
            try {
                long have = out.exists() ? out.length() : 0;
                if (have < p.size) {
                    fetch(rel.baseUrl + p.file, out, have, p.size, cb, done, total);
                }
                String sha = sha256(out);
                if (!sha.equalsIgnoreCase(p.sha256)) {
                    Result r = new Result();
                    r.reason = p.name + " 校验失败（期望 " + p.sha256.substring(0, 12) + "… 实际 " + sha.substring(0, 12) + "…）";
                    out.delete();
                    return r;
                }
                done += p.size;
                cb.onProgress(done, total, p.name);
            } catch (Exception e) {
                Result r = new Result();
                r.reason = p.name + " 下载失败：" + (e.getMessage() == null ? e.toString() : e.getMessage());
                return r;
            }
        }
        Result r = new Result();
        r.ok = true;
        return r;
    }

    private static void fetch(String url, File out, long offset, long size, Progress cb, long baseDone, long total) throws IOException {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setConnectTimeout(10000);
        c.setReadTimeout(30000);
        if (offset > 0) {
            c.setRequestProperty("Range", "bytes=" + offset + "-");
        }
        int code = c.getResponseCode();
        if (code != 200 && code != 206) {
            throw new IOException("HTTP " + code);
        }
        // 服务端不支持 Range 时只能重下
        if (offset > 0 && code == 200) {
            offset = 0;
            out.delete();
        }
        RandomAccessFile raf = new RandomAccessFile(out, "rw");
        try {
            raf.seek(offset);
            InputStream in = c.getInputStream();
            byte[] buf = new byte[256 * 1024];
            long written = offset;
            long lastTick = 0;
            int n;
            while ((n = in.read(buf)) > 0) {
                if (cb.isCancelled()) {
                    throw new IOException("cancelled");
                }
                raf.write(buf, 0, n);
                written += n;
                long now = System.currentTimeMillis();
                if (now - lastTick > 400) {
                    lastTick = now;
                    cb.onProgress(baseDone + written, total, out.getName());
                }
            }
            if (written != size) {
                throw new IOException("长度不符 " + written + "/" + size);
            }
        } finally {
            raf.close();
            c.disconnect();
        }
    }

    static String sha256(File f) throws Exception {
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        try (InputStream in = new java.io.FileInputStream(f)) {
            byte[] buf = new byte[1024 * 1024];
            int n;
            while ((n = in.read(buf)) > 0) {
                md.update(buf, 0, n);
            }
        }
        StringBuilder sb = new StringBuilder();
        for (byte b : md.digest()) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }

    private Downloader() {
    }
}
