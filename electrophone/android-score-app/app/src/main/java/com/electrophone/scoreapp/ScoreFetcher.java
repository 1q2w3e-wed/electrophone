package com.electrophone.scoreapp;

import android.content.Context;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLConnection;
import java.nio.charset.StandardCharsets;

import javax.net.ssl.HttpsURLConnection;

public final class ScoreFetcher {
    private static final int MAX_BYTES = 256 * 1024;
    private final Context context;

    public ScoreFetcher(Context context) {
        this.context = context.getApplicationContext();
    }

    public String fetch(String address) throws IOException {
        if (address.startsWith("asset:///")) {
            String assetPath = address.substring("asset:///".length());
            try (InputStream input = context.getAssets().open(assetPath)) {
                return readText(input, assetPath);
            }
        }

        URL url = new URL(address);
        if (!"https".equalsIgnoreCase(url.getProtocol())) {
            throw new IOException("只允许 HTTPS 地址");
        }
        URLConnection connection = url.openConnection();
        connection.setConnectTimeout(8000);
        connection.setReadTimeout(10000);
        connection.setRequestProperty("Accept", "application/json,text/plain,*/*");
        if (!(connection instanceof HttpsURLConnection)) {
            throw new IOException("HTTPS 连接创建失败");
        }
        HttpsURLConnection https = (HttpsURLConnection) connection;
        https.setInstanceFollowRedirects(true);
        int status = https.getResponseCode();
        if (status < 200 || status >= 300) {
            https.disconnect();
            throw new IOException("HTTP " + status);
        }
        if (!"https".equalsIgnoreCase(https.getURL().getProtocol())) {
            https.disconnect();
            throw new IOException("重定向到了非 HTTPS 地址");
        }
        try (InputStream input = https.getInputStream()) {
            return readText(input, url.getPath());
        } finally {
            https.disconnect();
        }
    }

    private static String readText(InputStream input, String sourceName) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int total = 0;
        int read;
        while ((read = input.read(buffer)) != -1) {
            total += read;
            if (total > MAX_BYTES) {
                throw new IOException(sourceName + " 超过 256 KiB");
            }
            output.write(buffer, 0, read);
        }
        String text = new String(output.toByteArray(), StandardCharsets.UTF_8);
        return text.replace("\uFEFF", "");
    }
}
