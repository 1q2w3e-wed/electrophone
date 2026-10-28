package com.electrophone.scoreapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.fail;

import org.junit.Test;

public final class RecordedEventDecoderTest {
    @Test
    public void decodesPackedBinaryEvent() {
        assertEquals(
                "NOTE 0,500,0,20,0,0",
                RecordedEventDecoder.decodePacked(0x00032140L));
    }

    @Test
    public void rejectsPackedValueOutsideThirtyTwoBits() {
        try {
            RecordedEventDecoder.decodePacked(0x1_00000000L);
            fail("Expected oversized event to fail");
        } catch (IllegalArgumentException expected) {
        }
    }
}
