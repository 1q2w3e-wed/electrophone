package com.electrophone.scoreapp;

import java.util.List;

public final class RemoteProtocol {
    private RemoteProtocol() {
    }

    public static String version() {
        return "VERSION";
    }

    public static int parseVersion(String response) {
        if (response == null || !response.matches("VERSION [23]")) {
            return 0;
        }
        return Integer.parseInt(response.substring("VERSION ".length()));
    }

    public static String keyState() {
        return "KEYSTATE";
    }

    public static int parseKeyState(String response) {
        if (response == null || !response.matches("KS [0-9A-Fa-f]{2}")) {
            throw new IllegalArgumentException("按键状态格式错误：" + response);
        }
        return Integer.parseInt(response.substring(3), 16);
    }

    public static String keyDown(RemoteKeyConfig key) {
        return "KEY DOWN " + key.note + "," + key.velocity + ","
                + key.tone + "," + key.effect;
    }

    public static String keyDownBatch(List<RemoteKeyConfig> keys) {
        StringBuilder commands = new StringBuilder();
        for (RemoteKeyConfig key : keys) {
            commands.append(keyDown(key)).append("\r\n");
        }
        return commands.toString();
    }

    public static String keyUp(int note) {
        return "KEY UP " + note;
    }

    public static String keyUpBatch(List<Integer> notes) {
        StringBuilder commands = new StringBuilder();
        for (Integer note : notes) {
            commands.append(keyUp(note)).append("\r\n");
        }
        return commands.toString();
    }

    public static String keyAllUp() {
        return "KEY ALL UP";
    }

    public static String recordStart() {
        return "REC START";
    }

    public static String recordStop() {
        return "REC STOP";
    }

    public static String recordDump() {
        return "REC DUMP";
    }

    public static String recordPlay() {
        return "REC PLAY";
    }

    public static String test32() {
        return "TEST 32";
    }

    public static String testOff() {
        return "TEST OFF";
    }
}
