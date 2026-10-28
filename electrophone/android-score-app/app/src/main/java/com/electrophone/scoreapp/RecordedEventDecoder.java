package com.electrophone.scoreapp;

import java.util.Locale;

public final class RecordedEventDecoder {
    private RecordedEventDecoder() {
    }

    public static String decode(String hex) {
        if (hex == null || !hex.matches("[0-9A-Fa-f]{8}")) {
            throw new IllegalArgumentException("录音事件必须是 8 位十六进制");
        }
        long packed;
        try {
            packed = Long.parseLong(hex, 16);
        } catch (NumberFormatException error) {
            throw new IllegalArgumentException("录音事件格式错误", error);
        }
        return decodePacked(packed);
    }

    public static String decodePacked(long packed) {
        if (packed < 0 || packed > 0xFFFFFFFFL) {
            throw new IllegalArgumentException("录音事件超出 32 位范围");
        }
        int delta = (int) ((packed >>> 20) & 0xFFF);
        int duration = (int) ((packed >>> 12) & 0xFF) * 10;
        int note = (int) ((packed >>> 9) & 0x7);
        int velocity = (int) ((packed >>> 4) & 0x1F);
        int tone = (int) ((packed >>> 2) & 0x3);
        int effect = (int) (packed & 0x3);
        if (duration == 0) {
            throw new IllegalArgumentException("录音事件时长必须大于 0");
        }
        return String.format(
                Locale.ROOT,
                "NOTE %d,%d,%d,%d,%d,%d",
                delta,
                duration,
                note,
                velocity,
                tone,
                effect);
    }
}
