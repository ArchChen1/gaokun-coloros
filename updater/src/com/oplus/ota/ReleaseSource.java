package com.oplus.ota;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;

/** 拉取服务端 index.json（在线更新清单）。字段见 docs/OTA-ONLINE-PLAN.md。 */
final class ReleaseSource {

    static final String DEFAULT_URL = "http://192.168.1.152:8001/ota/index.json";

    static final class Part {
        String name;
        long size;
        String sha256;
    }

    static final class Release {
        String version;      // 例：17.0.2 / OPD2513_17.0.2.100(CN01)
        String channel;      // stable / beta
        long totalSize;
        Part[] parts;
    }

    static Release fetch() throws Exception {
        String url = MainActivity.getProp("persist.sys.gk3.ota.url", DEFAULT_URL);
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setConnectTimeout(8000);
        c.setReadTimeout(15000);
        c.setRequestProperty("Accept", "application/json");
        try {
            if (c.getResponseCode() != 200) {
                throw new IOException2("HTTP " + c.getResponseCode());
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
        JSONArray arr = o.optJSONArray("parts");
        if (arr != null) {
            rel.parts = new Part[arr.length()];
            for (int i = 0; i < arr.length(); i++) {
                JSONObject p = arr.getJSONObject(i);
                Part part = new Part();
                part.name = p.getString("name");
                part.size = p.optLong("size", 0);
                part.sha256 = p.optString("sha256", "");
                rel.parts[i] = part;
            }
        }
        if (rel.version.isEmpty()) {
            throw new IOException2("清单缺少 version 字段");
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
