package com.electrophone.scoreapp;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public final class PerformanceConfig {
    private static final int FORMAT_VERSION = 1;

    public final int[] physicalNotes;
    public final List<RemoteKeyConfig> remoteKeys;

    public PerformanceConfig(int[] physicalNotes, List<RemoteKeyConfig> remoteKeys) {
        this.physicalNotes = validatePhysical(physicalNotes);
        this.remoteKeys = Collections.unmodifiableList(validateRemote(remoteKeys));
    }

    public static PerformanceConfig defaults() {
        int[] physical = {0, 1, 2, 3, 4, 5, 6, 7};
        List<RemoteKeyConfig> remote = new ArrayList<>();
        for (int note = 0; note < 8; note++) {
            remote.add(new RemoteKeyConfig("琴键" + (note + 1), note, 20, 0, 0));
        }
        return new PerformanceConfig(physical, remote);
    }

    public static PerformanceConfig validated(
            int[] physicalNotes, List<RemoteKeyConfig> remoteKeys) {
        return new PerformanceConfig(physicalNotes, remoteKeys);
    }

    public PerformanceConfig withRemoteKeyChanged(int index, RemoteKeyConfig changed) {
        if (index < 0 || index >= 8 || changed == null) {
            throw new IllegalArgumentException("虚拟琴键序号无效");
        }
        int oldNote = remoteKeys.get(index).note;
        List<RemoteKeyConfig> keys = new ArrayList<>(remoteKeys);
        if (changed.note != oldNote) {
            for (int other = 0; other < keys.size(); other++) {
                RemoteKeyConfig otherKey = keys.get(other);
                if (other != index && otherKey.note == changed.note) {
                    keys.set(other, new RemoteKeyConfig(
                            otherKey.label,
                            oldNote,
                            otherKey.velocity,
                            otherKey.tone,
                            otherKey.effect));
                    break;
                }
            }
        }
        keys.set(index, changed);
        return validated(physicalNotes, keys);
    }

    public String toJson() {
        try {
            JSONObject root = new JSONObject();
            root.put("version", FORMAT_VERSION);
            JSONArray physical = new JSONArray();
            for (int note : physicalNotes) {
                physical.put(note);
            }
            root.put("physical", physical);
            JSONArray remote = new JSONArray();
            for (RemoteKeyConfig key : remoteKeys) {
                JSONObject item = new JSONObject();
                item.put("label", key.label);
                item.put("note", key.note);
                item.put("velocity", key.velocity);
                item.put("tone", key.tone);
                item.put("effect", key.effect);
                remote.put(item);
            }
            root.put("remote", remote);
            return root.toString();
        } catch (JSONException error) {
            throw new IllegalStateException("无法保存琴键配置", error);
        }
    }

    public static PerformanceConfig fromJson(String json) throws JSONException {
        JSONObject root = new JSONObject(json);
        if (root.optInt("version", -1) != FORMAT_VERSION) {
            throw new JSONException("不支持的琴键配置版本");
        }
        JSONArray physicalJson = root.getJSONArray("physical");
        int[] physical = new int[physicalJson.length()];
        for (int index = 0; index < physicalJson.length(); index++) {
            physical[index] = physicalJson.getInt(index);
        }
        JSONArray remoteJson = root.getJSONArray("remote");
        List<RemoteKeyConfig> remote = new ArrayList<>();
        for (int index = 0; index < remoteJson.length(); index++) {
            JSONObject item = remoteJson.getJSONObject(index);
            remote.add(new RemoteKeyConfig(
                    item.getString("label"),
                    item.getInt("note"),
                    item.getInt("velocity"),
                    item.getInt("tone"),
                    item.getInt("effect")));
        }
        try {
            return validated(physical, remote);
        } catch (IllegalArgumentException error) {
            throw new JSONException(error.getMessage());
        }
    }

    private static int[] validatePhysical(int[] values) {
        if (values == null || values.length != 8) {
            throw new IllegalArgumentException("实体琴键映射必须包含 8 个音高");
        }
        boolean[] used = new boolean[8];
        int[] copy = new int[8];
        for (int index = 0; index < 8; index++) {
            int note = values[index];
            if (note < 0 || note > 7) {
                throw new IllegalArgumentException("实体琴键音高必须在 0 到 7");
            }
            if (used[note]) {
                throw new IllegalArgumentException("实体琴键映射不能重复使用同一个音高");
            }
            used[note] = true;
            copy[index] = note;
        }
        return copy;
    }

    private static List<RemoteKeyConfig> validateRemote(List<RemoteKeyConfig> values) {
        if (values == null || values.size() != 8) {
            throw new IllegalArgumentException("虚拟琴键必须包含 8 个配置");
        }
        boolean[] used = new boolean[8];
        List<RemoteKeyConfig> copy = new ArrayList<>(8);
        for (RemoteKeyConfig key : values) {
            if (key == null) {
                throw new IllegalArgumentException("虚拟琴键配置不能为空");
            }
            if (used[key.note]) {
                throw new IllegalArgumentException("虚拟琴键不能重复使用同一个音高");
            }
            used[key.note] = true;
            copy.add(key);
        }
        return copy;
    }
}
