package com.oplus.ota;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;

/**
 * 断点续传下载 + sha256 校验。
 *
 * 之所以自己写而不用 DownloadManager：我们要能续传、能拿到已下载字节数、
 * 而且下完必须在落盘后立刻校验（校验不过就删掉重下）。
 */
final class Downloader {

    interface Progress {
        void onProgress(long done, long total);
    }

    /** 下载到 out；已存在部分文件时从现有长度续传。返回落盘文件的 sha256（十六进制小写）。 */
    static String download(String url, File out, long expectedSize, Progress cb) throws Exception {
        long start = out.exists() ? out.length() : 0;
        if (expectedSize > 0 && start == expectedSize) {
            return sha256Hex(out);
        }
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setConnectTimeout(10000);
        c.setReadTimeout(30000);
        if (start > 0) {
            c.setRequestProperty("Range", "bytes=" + start + "-");
        }
        try {
            int code = c.getResponseCode();
            if (code != 200 && code != 206) {
                throw new IOException("下载失败（HTTP " + code + "）");
            }
            long total = expectedSize > 0 ? expectedSize : c.getContentLength();
            FileOutputStream fos = new FileOutputStream(out, start > 0 && code == 206);
            try {
                InputStream in = c.getInputStream();
                byte[] buf = new byte[1 << 20];
                long done = (code == 206) ? start : 0;
                if (code == 200 && start > 0) {
                    // 服务端不支持续传，从头写
                    done = 0;
                }
                int n;
                while ((n = in.read(buf)) > 0) {
                    fos.write(buf, 0, n);
                    done += n;
                    if (cb != null) {
                        cb.onProgress(done, total);
                    }
                }
            } finally {
                fos.close();
            }
        } finally {
            c.disconnect();
        }
        return sha256Hex(out);
    }

    /** 拉一个小文件（OTA 的 payload_properties.txt）。引擎要 FILE_HASH / METADATA_HASH / METADATA_SIZE，缺一个就 kPayloadHashMismatch。 */
    static void fetch(String url, File out) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setConnectTimeout(10000);
        c.setReadTimeout(15000);
        try {
            int code = c.getResponseCode();
            if (code != 200) {
                throw new IOException("属性文件下载失败（HTTP " + code + "）");
            }
            try (InputStream in = c.getInputStream();
                 FileOutputStream fos = new FileOutputStream(out)) {
                byte[] buf = new byte[4096];
                int n;
                while ((n = in.read(buf)) > 0) {
                    fos.write(buf, 0, n);
                }
            }
        } finally {
            c.disconnect();
        }
    }

    static String sha256Hex(File f) throws Exception {
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        try (InputStream in = new java.io.FileInputStream(f)) {
            byte[] buf = new byte[8 << 20];
            int n;
            while ((n = in.read(buf)) > 0) {
                md.update(buf, 0, n);
            }
        }
        StringBuilder sb = new StringBuilder(64);
        for (byte b : md.digest()) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }

    /** 把 zip 里的 payload.bin 抽到 out（标准 OTA zip 的 payload 是 store，等价于顺序拷贝）。 */
    static void extractPayload(File zip, File out) throws Exception {
        java.util.zip.ZipFile zf = new java.util.zip.ZipFile(zip);
        try {
            java.util.zip.ZipEntry e = zf.getEntry("payload.bin");
            if (e == null) {
                throw new IOException("zip 里没有 payload.bin");
            }
            try (InputStream in = zf.getInputStream(e);
                 FileOutputStream fos = new FileOutputStream(out)) {
                byte[] buf = new byte[1 << 20];
                int n;
                while ((n = in.read(buf)) > 0) {
                    fos.write(buf, 0, n);
                }
            }
            java.util.zip.ZipEntry pe = zf.getEntry("payload_properties.txt");
            // 属性文件名跟 payload 走（<payload>.properties），写入服务就按这个约定取
            File props = new File(out.getParentFile(), out.getName() + ".properties");
            if (pe != null) {
                try (InputStream in = zf.getInputStream(pe);
                     FileOutputStream fos = new FileOutputStream(props)) {
                    byte[] buf = new byte[4096];
                    int n;
                    while ((n = in.read(buf)) > 0) {
                        fos.write(buf, 0, n);
                    }
                }
            }
            // 顺手做个完整性检查：store 模式下条目大小应与解出的字节数一致
            if (e.getSize() > 0 && out.length() != e.getSize()) {
                throw new IOException("payload 解出大小不符");
            }
        } finally {
            zf.close();
        }
    }

    private Downloader() {
    }
}
