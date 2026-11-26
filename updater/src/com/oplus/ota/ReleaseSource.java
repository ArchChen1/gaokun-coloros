package com.oplus.ota;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;

/**
 * 拉取服务端 index.json（在线更新清单）。字段见 docs/OTA-ONLINE-PLAN.md。
 *
 * 两种清单都认：
 *   引擎路线 —— payload 单条目 {file,size,sha256,file_hash,metadata_size[,zip]}
 *   dd 路线   —— parts 数组（同样的 13 个分区镜像）
 */
final class ReleaseSource {

    static final String DEFAULT_URL = "https://ota.cenmin.cn/gk3-ota/stable/index.json";

    static final class Part {
        String name;
        String file;
        long size;
        String sha256;
    }

    /** 引擎吃的那个 payload（可选带一份标准 OTA zip）。 */
    static final class Payload {
        String file;
        long size;
        String sha256;
        String fileHash;
        long metadataSize;
        String zipFile;
        long zipSize;
        String zipSha256;
    }

    static final class Release {
        String version;
        String channel;
        long totalSize;
        String baseUrl;
        Part[] parts;
        Payload payload;
    }

    static Release fetch() throws Exception {
        String url = MainActivity.getProp("persist.sys.gk3.ota.url", DEFAULT_URL);
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setConnectTimeout(8000);
        c.setReadTimeout(15000);
        c.setRequestProperty("Accept", "application/json");
        try {
            int code = c.getResponseCode();
            if (code != 200) {
                throw new IOException2("清单取不到（HTTP " + code + "）");
            }
            StringBuilder sb = new StringBuilder();
            try (BufferedReader r = new BufferedReader(new InputStreamReader(c.getInputStream(), "UTF-8"))) {
                String line;
                while ((line = r.readLine()) != null) {
                    sb.append(line);
                }
            }
            return parse(sb.toString());
        } finally {
            c.disconnect();
        }
    }

    static Release parse(String json) throws Exception {
        JSONObject o = new JSONObject(json);
        Release rel = new Release();
        rel.version = o.optString("version", "");
        rel.channel = o.optString("channel", "stable");
        rel.totalSize = o.optLong("total_size", 0);
        rel.baseUrl = o.optString("base_url", "");
        if (!rel.baseUrl.isEmpty() && !rel.baseUrl.endsWith("/")) {
            rel.baseUrl = rel.baseUrl + "/";
        }

        JSONObject p = o.optJSONObject("payload");
        if (p != null) {
            Payload pl = new Payload();
            pl.file = p.optString("file", "");
            pl.size = p.optLong("size", 0);
            pl.sha256 = p.optString("sha256", "");
            pl.fileHash = p.optString("file_hash", "");
            pl.metadataSize = p.optLong("metadata_size", 0);
            JSONObject z = p.optJSONObject("zip");
            if (z != null) {
                pl.zipFile = z.optString("file", "");
                pl.zipSize = z.optLong("size", 0);
                pl.zipSha256 = z.optString("sha256", "");
            }
            if (pl.file.isEmpty() || pl.sha256.isEmpty()) {
                throw new IOException2("payload 条目缺 file / sha256");
            }
            rel.payload = pl;
            if (rel.totalSize <= 0) {
                rel.totalSize = pl.size;
            }
        }

        JSONArray arr = o.optJSONArray("parts");
        if (arr != null && arr.length() > 0) {
            rel.parts = new Part[arr.length()];
            for (int i = 0; i < arr.length(); i++) {
                try {
                    JSONObject q = arr.getJSONObject(i);
                    Part part = new Part();
                    part.name = q.getString("name");
                    part.file = q.optString("file", part.name + ".img");
                    part.size = q.optLong("size", 0);
                    part.sha256 = q.optString("sha256", "");
                    rel.parts[i] = part;
                } catch (JSONException e) {
                    throw new IOException2("清单里第 " + i + " 个分区条目坏了");
                }
            }
        }
        if (rel.version.isEmpty()) {
            throw new IOException2("清单缺少 version 字段");
        }
        if (rel.payload == null && (rel.parts == null || rel.parts.length == 0)) {
            throw new IOException2("清单里既没有 payload 也没有分区");
        }
        return rel;
    }

    /** 带中文说明的异常，直接显示在 UI 上。 */
    static final class IOException2 extends Exception {
        IOException2(String m) {
            super(m);
        }
    }

    private ReleaseSource() {
    }
}
