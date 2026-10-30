package com.electrophone.scoreapp;

import static org.junit.Assert.assertEquals;

import java.util.Arrays;

import org.junit.Test;

public final class RemoteProtocolTest {
    @Test
    public void buildsCommandsFromEachKeysOwnSettings() {
        RemoteKeyConfig key = new RemoteKeyConfig("主旋律", 6, 27, 3, 1);
        assertEquals("KEY DOWN 6,27,3,1", RemoteProtocol.keyDown(key));
        assertEquals("KEY UP 6", RemoteProtocol.keyUp(6));
        assertEquals("KEY ALL UP", RemoteProtocol.keyAllUp());
        assertEquals("REC START", RemoteProtocol.recordStart());
        assertEquals("REC STOP", RemoteProtocol.recordStop());
        assertEquals("REC DUMP", RemoteProtocol.recordDump());
        assertEquals("REC PLAY", RemoteProtocol.recordPlay());
        assertEquals("TEST 32", RemoteProtocol.test32());
        assertEquals("TEST OFF", RemoteProtocol.testOff());
        assertEquals("KEYSTATE", RemoteProtocol.keyState());
        assertEquals("VERSION", RemoteProtocol.version());
        assertEquals(2, RemoteProtocol.parseVersion("VERSION 2"));
        assertEquals(3, RemoteProtocol.parseVersion("VERSION 3"));
        assertEquals(0, RemoteProtocol.parseVersion("ERR"));
        assertEquals(0xA5, RemoteProtocol.parseKeyState("KS A5"));
    }

    @Test
    public void buildsOneDownPayloadForAWholeChord() {
        RemoteKeyConfig first = new RemoteKeyConfig("低音", 0, 12, 0, 0);
        RemoteKeyConfig second = new RemoteKeyConfig("中音", 2, 20, 1, 2);
        assertEquals(
                "KEY DOWN 0,12,0,0\r\nKEY DOWN 2,20,1,2\r\n",
                RemoteProtocol.keyDownBatch(Arrays.asList(first, second))
        );
    }

    @Test
    public void buildsOneUpPayloadForAWholeChordRelease() {
        assertEquals(
                "KEY UP 0\r\nKEY UP 2\r\nKEY UP 4\r\n",
                RemoteProtocol.keyUpBatch(Arrays.asList(0, 2, 4))
        );
    }
}
