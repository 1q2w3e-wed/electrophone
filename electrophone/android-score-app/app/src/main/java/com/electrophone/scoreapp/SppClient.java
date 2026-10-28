package com.electrophone.scoreapp;

import android.annotation.SuppressLint;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothSocket;

import java.io.BufferedInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.Set;
import java.util.UUID;

public final class SppClient implements AutoCloseable {
    public interface Listener {
        void onStatus(String message);
    }

    private static final UUID SPP_UUID =
            UUID.fromString("00001101-0000-1000-8000-00805F9B34FB");
    private static final int DUMP_MAGIC_1 = 0xA5;
    private static final int DUMP_MAGIC_2 = 0x5A;

    private BluetoothSocket socket;
    private InputStream input;
    private OutputStream output;
    private ResponseStream responses;
    private int protocolVersion;

    @SuppressLint("MissingPermission")
    public int connect(BluetoothAdapter adapter, BluetoothDevice device, Listener listener)
            throws IOException {
        close();
        listener.onStatus("正在连接 " + safeName(device) + "…");
        socket = device.createRfcommSocketToServiceRecord(SPP_UUID);
        socket.connect();
        input = new BufferedInputStream(socket.getInputStream());
        output = socket.getOutputStream();
        responses = new ResponseStream(input);
        listener.onStatus("连接成功，正在检查设备…");
        try {
            sendLine("PING", Collections.singleton(ResponseStream.PONG));
        } catch (IOException error) {
            throw new IOException("设备未返回 PONG：" + error.getMessage(), error);
        }
        protocolVersion = negotiateVersion();
        if (protocolVersion >= 2) {
            listener.onStatus("设备在线，远程演奏与录音已就绪");
        } else {
            listener.onStatus("设备在线，当前码流仅支持曲谱发送");
        }
        return protocolVersion;
    }

    public void sendScore(ScoreValidator.Result score, Listener listener) throws IOException {
        requireConnection();
        int total = score.commands.size();
        for (int index = 0; index < total; index++) {
            String command = score.commands.get(index);
            String response = sendLine(command, ResponseStream.COMMAND_RESPONSES);
            if (!ResponseStream.OK.equals(response)) {
                throw new IOException("设备返回 " + response + "，停止于第 " + (index + 1) + " 条命令");
            }
            if ((index + 1) % 10 == 0 || index + 1 == total) {
                listener.onStatus("正在发送 " + (index + 1) + "/" + total);
            }
        }
        listener.onStatus("曲谱发送完成，FPGA 已开始播放");
    }

    public void sendRemoteKeyDown(RemoteKeyConfig key) throws IOException {
        requireProtocolTwo();
        expectOk(RemoteProtocol.keyDown(key));
    }

    public void applyPhysicalMapping(int[] notes) throws IOException {
        requireConnection();
        if (notes == null || notes.length != 8) {
            throw new IOException("实体琴键映射必须包含 8 个音高");
        }
        StringBuilder command = new StringBuilder("MAP ");
        for (int index = 0; index < notes.length; index++) {
            if (index > 0) {
                command.append(',');
            }
            command.append(notes[index]);
        }
        expectOk(command.toString());
    }

    public void sendRemoteKeyUp(int note) throws IOException {
        requireProtocolTwo();
        expectOk(RemoteProtocol.keyUp(note));
    }

    public void releaseAllRemoteKeys() throws IOException {
        requireProtocolTwo();
        expectOk(RemoteProtocol.keyAllUp());
    }

    public void startRecording() throws IOException {
        requireProtocolTwo();
        expectOk(RemoteProtocol.recordStart());
    }

    public void stopRecording() throws IOException {
        requireProtocolTwo();
        expectOk(RemoteProtocol.recordStop());
    }

    public void replayRecording() throws IOException {
        requireProtocolTwo();
        expectOk(RemoteProtocol.recordPlay());
    }

    public void setTestMode(boolean enabled) throws IOException {
        requireConnection();
        expectOk(enabled ? RemoteProtocol.test32() : RemoteProtocol.testOff());
    }

    public int readKeyState() throws IOException {
        requireConnection();
        if (protocolVersion < 3) {
            throw new IOException("请先烧录支持曲谱跟弹的新版 FPGA 码流");
        }
        writeLine(RemoteProtocol.keyState());
        String response = responses.readLineOrToken(
                Collections.singleton(ResponseStream.ERR), 1500);
        if (ResponseStream.ERR.equals(response)) {
            throw new IOException("FPGA 拒绝查询按键状态");
        }
        try {
            return RemoteProtocol.parseKeyState(response);
        } catch (IllegalArgumentException error) {
            throw new IOException(error.getMessage(), error);
        }
    }

    public RecordingDumpParser.Result dumpRecording() throws IOException {
        requireProtocolTwo();
        writeLine(RemoteProtocol.recordDump());
        int first = responses.readByteSkippingLineEndings(3000);
        if (first == 'E') {
            responses.readByte(100);
            responses.readByte(100);
            throw new IOException("FPGA 当前不能导出录音，请先停止录音和播放");
        }
        if (first != DUMP_MAGIC_1 || responses.readByte(3000) != DUMP_MAGIC_2) {
            throw new IOException("录音回传帧头无效");
        }
        int count = (responses.readByte(3000) << 8) | responses.readByte(3000);
        if (count > 1024) {
            throw new IOException("录音事件超过 1024 条");
        }

        StringBuilder notes = new StringBuilder();
        for (int index = 0; index < count; index++) {
            long packed = ((long) responses.readByte(3000) << 24)
                    | ((long) responses.readByte(3000) << 16)
                    | ((long) responses.readByte(3000) << 8)
                    | responses.readByte(3000);
            notes.append(RecordedEventDecoder.decodePacked(packed)).append('\n');
        }
        try {
            return new RecordingDumpParser.Result(count, notes.toString());
        } catch (IllegalArgumentException error) {
            throw new IOException("录音回传格式错误：" + error.getMessage(), error);
        }
    }

    public boolean isConnected() {
        return socket != null && socket.isConnected()
                && output != null && input != null && responses != null;
    }

    public int getProtocolVersion() {
        return protocolVersion;
    }

    private String sendLine(String command, Set<String> accepted) throws IOException {
        writeLine(command);
        return responses.readToken(accepted, 1500);
    }

    private void writeLine(String command) throws IOException {
        byte[] bytes = (command + "\r\n").getBytes(StandardCharsets.US_ASCII);
        output.write(bytes);
        output.flush();
    }

    private void expectOk(String command) throws IOException {
        String response = sendLine(command, ResponseStream.COMMAND_RESPONSES);
        if (!ResponseStream.OK.equals(response)) {
            throw new IOException("设备返回 " + response);
        }
    }

    private int negotiateVersion() {
        try {
            writeLine(RemoteProtocol.version());
            String response = responses.readLineOrToken(
                    Collections.singleton(ResponseStream.ERR), 1500);
            return RemoteProtocol.parseVersion(response);
        } catch (IOException ignored) {
            return 0;
        }
    }

    private void requireConnection() throws IOException {
        if (!isConnected()) {
            throw new IOException("蓝牙尚未连接");
        }
    }

    private void requireProtocolTwo() throws IOException {
        requireConnection();
        if (protocolVersion < 2) {
            throw new IOException("请先烧录支持远程演奏的新版 FPGA 码流");
        }
    }

    @SuppressLint("MissingPermission")
    private static String safeName(BluetoothDevice device) {
        String name = device.getName();
        return name == null || name.trim().isEmpty() ? device.getAddress() : name;
    }

    @Override
    public void close() {
        try {
            if (socket != null) {
                socket.close();
            }
        } catch (IOException ignored) {
        } finally {
            socket = null;
            input = null;
            output = null;
            responses = null;
            protocolVersion = 0;
        }
    }
}
