package com.electrophone.scoreapp;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.fail;

import org.junit.Test;

import java.util.ArrayList;
import java.util.List;

public final class PerformanceConfigTest {
    @Test
    public void defaultsUseEightUniquePhysicalAndRemoteNotes() throws Exception {
        PerformanceConfig config = PerformanceConfig.defaults();
        assertArrayEquals(new int[]{0, 1, 2, 3, 4, 5, 6, 7}, config.physicalNotes);
        assertEquals(8, config.remoteKeys.size());
        for (int index = 0; index < 8; index++) {
            assertEquals(index, config.remoteKeys.get(index).note);
        }
    }

    @Test
    public void rejectsDuplicatePhysicalNotes() {
        int[] mapping = {0, 1, 2, 3, 4, 5, 6, 6};
        try {
            new PerformanceConfig(mapping, PerformanceConfig.defaults().remoteKeys);
            fail("Expected duplicate physical notes to fail");
        } catch (IllegalArgumentException expected) {
            assertEquals("实体琴键映射不能重复使用同一个音高", expected.getMessage());
        }
    }

    @Test
    public void rejectsDuplicateRemoteNotes() {
        PerformanceConfig defaults = PerformanceConfig.defaults();
        List<RemoteKeyConfig> remote = new ArrayList<>(defaults.remoteKeys);
        remote.set(7, new RemoteKeyConfig("重复", 6, 20, 0, 0));
        try {
            PerformanceConfig.validated(
                    new int[]{0, 1, 2, 3, 4, 5, 6, 7}, remote);
            fail("Expected duplicate remote notes to fail");
        } catch (IllegalArgumentException expected) {
            assertEquals("虚拟琴键不能重复使用同一个音高", expected.getMessage());
        }
    }

    @Test
    public void rejectsOutOfRangeRemoteSettings() {
        try {
            new RemoteKeyConfig("测试", 8, 20, 0, 0);
            fail("Expected invalid note to fail");
        } catch (IllegalArgumentException expected) {
        }
        try {
            new RemoteKeyConfig("测试", 0, 32, 0, 0);
            fail("Expected invalid velocity to fail");
        } catch (IllegalArgumentException expected) {
        }
        try {
            new RemoteKeyConfig("测试", 0, 20, 4, 0);
            fail("Expected invalid tone to fail");
        } catch (IllegalArgumentException expected) {
        }
        try {
            new RemoteKeyConfig("测试", 0, 20, 0, 4);
            fail("Expected invalid effect to fail");
        } catch (IllegalArgumentException expected) {
        }
    }

    @Test
    public void jsonRoundTripPreservesEverySetting() throws Exception {
        PerformanceConfig defaults = PerformanceConfig.defaults();
        List<RemoteKeyConfig> remote = new ArrayList<>(defaults.remoteKeys);
        remote.set(2, new RemoteKeyConfig("主旋律", 6, 27, 3, 1));
        remote.set(6, new RemoteKeyConfig("琴键7", 2, 20, 0, 0));
        defaults.physicalNotes[0] = 6;
        defaults.physicalNotes[6] = 0;
        PerformanceConfig validated = PerformanceConfig.validated(
                defaults.physicalNotes, remote);

        PerformanceConfig restored = PerformanceConfig.fromJson(validated.toJson());

        assertArrayEquals(validated.physicalNotes, restored.physicalNotes);
        assertEquals(validated.remoteKeys, restored.remoteKeys);
    }

    @Test
    public void changingRemotePitchSwapsWithTheOtherKey() throws Exception {
        PerformanceConfig defaults = PerformanceConfig.defaults();
        RemoteKeyConfig changed =
                new RemoteKeyConfig("主旋律", 6, 27, 3, 1);

        PerformanceConfig updated = defaults.withRemoteKeyChanged(2, changed);

        assertEquals(6, updated.remoteKeys.get(2).note);
        assertEquals(2, updated.remoteKeys.get(6).note);
        assertEquals("琴键7", updated.remoteKeys.get(6).label);
        assertEquals(20, updated.remoteKeys.get(6).velocity);
    }
}
