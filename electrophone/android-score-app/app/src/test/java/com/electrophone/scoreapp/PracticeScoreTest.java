package com.electrophone.scoreapp;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

import java.util.Arrays;

public final class PracticeScoreTest {
    @Test
    public void groupsZeroDeltaNotesIntoChordSteps() throws Exception {
        ScoreValidator.Result score = ScoreValidator.normalize(
                "NOTE 0,500,0,20,0,0\n"
                        + "NOTE 0,500,2,20,0,0\n"
                        + "NOTE 500,500,4,20,0,0\n"
                        + "NOTE 0,500,6,20,0,0\n");

        PracticeScore practice = PracticeScore.from(score);

        assertEquals(2, practice.steps.size());
        assertEquals(Arrays.asList(0, 2), practice.steps.get(0).notes);
        assertEquals(Arrays.asList(4, 6), practice.steps.get(1).notes);
        assertEquals(0b00000101, practice.steps.get(0).mask);
        assertEquals(0b01010000, practice.steps.get(1).mask);
        assertEquals(0, practice.steps.get(0).startMs);
        assertEquals(500, practice.steps.get(1).startMs);
    }
}
