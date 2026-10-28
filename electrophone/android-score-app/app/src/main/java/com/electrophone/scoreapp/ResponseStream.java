package com.electrophone.scoreapp;

import java.io.IOException;
import java.io.InputStream;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.TimeUnit;

final class ResponseStream {
    static final String PONG = "PONG";
    static final String OK = "OK";
    static final String ERR = "ERR";
    static final String FULL = "FULL";
    static final Set<String> COMMAND_RESPONSES = Collections.unmodifiableSet(
            new HashSet<>(Arrays.asList(OK, ERR, FULL)));

    private static final int MAX_WINDOW_LENGTH = 32;
    private static final int MAX_LINE_LENGTH = 256;
    private final InputStream input;
    private final StringBuilder window = new StringBuilder();

    ResponseStream(InputStream input) {
        this.input = input;
    }

    String readToken(Set<String> accepted, long timeoutMillis) throws IOException {
        window.setLength(0);
        long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMillis);
        while (System.nanoTime() < deadline) {
            if (input.available() <= 0) {
                try {
                    Thread.sleep(5);
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                    throw new IOException("等待蓝牙回复时被中断");
                }
                continue;
            }

            int value = input.read();
            if (value == -1) {
                throw new IOException("蓝牙连接已断开");
            }
            char character = Character.toUpperCase((char) value);
            if (character >= 'A' && character <= 'Z') {
                window.append(character);
                if (window.length() > MAX_WINDOW_LENGTH) {
                    window.delete(0, window.length() - MAX_WINDOW_LENGTH);
                }
                String current = window.toString();
                for (String token : accepted) {
                    if (current.endsWith(token)) {
                        return token;
                    }
                }
            }
        }
        throw new IOException("等待设备回复超时");
    }

    String readLineOrToken(Set<String> acceptedTokens, long timeoutMillis) throws IOException {
        StringBuilder line = new StringBuilder();
        StringBuilder tokenWindow = new StringBuilder();
        long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMillis);
        while (System.nanoTime() < deadline) {
            if (input.available() <= 0) {
                try {
                    Thread.sleep(5);
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                    throw new IOException("等待蓝牙回复时被中断");
                }
                continue;
            }

            int value = input.read();
            if (value == -1) {
                throw new IOException("蓝牙连接已断开");
            }
            if (value == '\n') {
                String result = line.toString().trim();
                if (!result.isEmpty()) {
                    return result;
                }
                line.setLength(0);
                tokenWindow.setLength(0);
                continue;
            }
            if (value == '\r') {
                continue;
            }
            line.append((char) value);
            if (line.length() > MAX_LINE_LENGTH) {
                throw new IOException("蓝牙回复过长");
            }
            char character = Character.toUpperCase((char) value);
            if (character >= 'A' && character <= 'Z') {
                tokenWindow.append(character);
                if (tokenWindow.length() > MAX_WINDOW_LENGTH) {
                    tokenWindow.delete(0, tokenWindow.length() - MAX_WINDOW_LENGTH);
                }
                String tokenText = tokenWindow.toString();
                for (String token : acceptedTokens) {
                    if (tokenText.endsWith(token)) {
                        return token;
                    }
                }
            }
        }
        throw new IOException("等待设备回复超时");
    }

    int readByte(long timeoutMillis) throws IOException {
        long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMillis);
        while (System.nanoTime() < deadline) {
            if (input.available() <= 0) {
                try {
                    Thread.sleep(5);
                } catch (InterruptedException interrupted) {
                    Thread.currentThread().interrupt();
                    throw new IOException("等待蓝牙数据时被中断");
                }
                continue;
            }
            int value = input.read();
            if (value == -1) {
                throw new IOException("蓝牙连接已断开");
            }
            return value;
        }
        throw new IOException("等待蓝牙数据超时");
    }

    int readByteSkippingLineEndings(long timeoutMillis) throws IOException {
        long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMillis);
        while (System.nanoTime() < deadline) {
            int value = readByte(Math.max(1, TimeUnit.NANOSECONDS.toMillis(
                    deadline - System.nanoTime())));
            if (value != '\r' && value != '\n') {
                return value;
            }
        }
        throw new IOException("等待蓝牙数据超时");
    }
}
