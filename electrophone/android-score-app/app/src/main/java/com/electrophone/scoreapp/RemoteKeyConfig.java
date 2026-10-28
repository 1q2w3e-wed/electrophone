package com.electrophone.scoreapp;

import java.util.Objects;

public final class RemoteKeyConfig {
    public final String label;
    public final int note;
    public final int velocity;
    public final int tone;
    public final int effect;

    public RemoteKeyConfig(String label, int note, int velocity, int tone, int effect) {
        String normalizedLabel = label == null ? "" : label.trim();
        if (normalizedLabel.isEmpty() || normalizedLabel.length() > 12) {
            throw new IllegalArgumentException("虚拟琴键名称必须为 1 到 12 个字符");
        }
        if (note < 0 || note > 7) {
            throw new IllegalArgumentException("虚拟琴键音高必须在 0 到 7");
        }
        if (velocity < 0 || velocity > 31) {
            throw new IllegalArgumentException("虚拟琴键力度必须在 0 到 31");
        }
        if (tone < 0 || tone > 3) {
            throw new IllegalArgumentException("虚拟琴键音色必须在 0 到 3");
        }
        if (effect < 0 || effect > 3) {
            throw new IllegalArgumentException("虚拟琴键效果必须在 0 到 3");
        }
        this.label = normalizedLabel;
        this.note = note;
        this.velocity = velocity;
        this.tone = tone;
        this.effect = effect;
    }

    @Override
    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof RemoteKeyConfig)) {
            return false;
        }
        RemoteKeyConfig key = (RemoteKeyConfig) other;
        return note == key.note
                && velocity == key.velocity
                && tone == key.tone
                && effect == key.effect
                && label.equals(key.label);
    }

    @Override
    public int hashCode() {
        return Objects.hash(label, note, velocity, tone, effect);
    }
}
