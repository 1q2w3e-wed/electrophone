package com.electrophone.scoreapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.fail;

import java.util.Arrays;

import org.junit.Test;

public final class RecordingDumpParserTest {
    @Test
    public void decodesPackedEventToNoteLine() throws Exception {
        assertEquals(
                "NOTE 0,500,0,20,0,0",
                RecordedEventDecoder.decode("00032140"));
    }

    @Test
    public void parsesCompleteDump() throws Exception {
        RecordingDumpParser.Result result = RecordingDumpParser.parse(Arrays.asList(
                "COUNT 2",
                "EVT 00032140",
                "EVT 1F432344",
                "END"));
        assertEquals(2, result.eventCount);
        assertEquals(
                "NOTE 0,500,0,20,0,0\n"
                        + "NOTE 500,500,1,20,1,0\n",
                result.noteText);
    }

    @Test
    public void acceptsEmptyRecording() throws Exception {
        RecordingDumpParser.Result result = RecordingDumpParser.parse(Arrays.asList(
                "COUNT 0",
                "END"));
        assertEquals(0, result.eventCount);
        assertEquals("", result.noteText);
    }

    @Test
    public void rejectsCountMismatch() {
        assertInvalid(Arrays.asList(
                "COUNT 2",
                "EVT 00032140",
                "END"));
    }

    @Test
    public void rejectsInvalidHex() {
        assertInvalid(Arrays.asList(
                "COUNT 1",
                "EVT XXXXXXXX",
                "END"));
    }

    @Test
    public void rejectsMissingEnd() {
        assertInvalid(Arrays.asList(
                "COUNT 1",
                "EVT 00032140"));
    }

    @Test
    public void rejectsMoreThan1024Events() {
        String[] lines = new String[1026];
        lines[0] = "COUNT 1025";
        for (int index = 0; index < 1025; index++) {
            lines[index + 1] = "EVT 00032140";
        }
        lines[1025] = "END";
        assertInvalid(Arrays.asList(lines));
    }

    private static void assertInvalid(Iterable<String> lines) {
        try {
            RecordingDumpParser.parse(lines);
            fail("Expected recording dump to fail");
        } catch (IllegalArgumentException expected) {
        }
    }
}
