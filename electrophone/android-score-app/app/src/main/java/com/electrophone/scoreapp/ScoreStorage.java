package com.electrophone.scoreapp;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.net.Uri;
import android.os.Environment;
import android.provider.MediaStore;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

public final class ScoreStorage {
    public static final class SavedScore {
        public final String displayLocation;

        SavedScore(String displayLocation) {
            this.displayLocation = displayLocation;
        }
    }

    private ScoreStorage() {
    }

    public static SavedScore save(Context context, String title, String text) throws IOException {
        String fileName = sanitize(title) + ".txt";
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            saveToPublicDownloads(context, fileName, text);
            return new SavedScore("下载/ElectrophoneScores/" + fileName);
        }

        File root = context.getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS);
        if (root == null) {
            root = context.getFilesDir();
        }
        File directory = new File(root, "ElectrophoneScores");
        if (!directory.exists() && !directory.mkdirs()) {
            throw new IOException("无法创建曲谱目录");
        }
        File output = new File(directory, fileName);
        try (FileOutputStream stream = new FileOutputStream(output)) {
            stream.write(text.getBytes(StandardCharsets.UTF_8));
        }
        return new SavedScore(output.getAbsolutePath());
    }

    @android.annotation.TargetApi(29)
    private static void saveToPublicDownloads(Context context, String fileName, String text)
            throws IOException {
        ContentResolver resolver = context.getContentResolver();
        ContentValues values = new ContentValues();
        values.put(MediaStore.MediaColumns.DISPLAY_NAME, fileName);
        values.put(MediaStore.MediaColumns.MIME_TYPE, "text/plain");
        values.put(
                MediaStore.MediaColumns.RELATIVE_PATH,
                Environment.DIRECTORY_DOWNLOADS + "/ElectrophoneScores");
        values.put(MediaStore.MediaColumns.IS_PENDING, 1);
        Uri uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
        if (uri == null) {
            throw new IOException("系统下载目录不可用");
        }
        try {
            try (OutputStream output = resolver.openOutputStream(uri)) {
                if (output == null) {
                    throw new IOException("无法写入下载目录");
                }
                output.write(text.getBytes(StandardCharsets.UTF_8));
            }
            ContentValues complete = new ContentValues();
            complete.put(MediaStore.MediaColumns.IS_PENDING, 0);
            resolver.update(uri, complete, null, null);
        } catch (IOException error) {
            resolver.delete(uri, null, null);
            throw error;
        }
    }

    private static String sanitize(String title) {
        String value = title.replaceAll("[\\\\/:*?\"<>|]", "_").trim();
        return value.isEmpty() ? "曲谱" : value;
    }
}
