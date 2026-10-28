package com.electrophone.scoreapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class FollowSessionTest {
    @Test
    public void advancesAfterExpectedNoteIsReleased() throws Exception {
        FollowSession session = session(
                "NOTE 0,300,0,20,0,0\n"
                        + "NOTE 300,300,1,20,0,0\n");
        assertEquals(FollowSession.Status.CORRECT_HOLD, session.update(0b1).status);
        assertFalse(session.update(0b1).advanced);
        FollowSession.Update update = session.update(0);
        assertEquals(FollowSession.Status.ADVANCED, update.status);
        assertTrue(update.advanced);
        assertEquals(1, update.stepIndex);
    }

    @Test
    public void wrongNoteWarnsWithoutAdvancing() throws Exception {
        FollowSession session = session("NOTE 0,300,0,20,0,0\n");
        FollowSession.Update update = session.update(0b10);
        assertEquals(FollowSession.Status.WRONG, update.status);
        assertFalse(update.advanced);
        assertEquals(0, update.stepIndex);
    }

    @Test
    public void chordRequiresEveryNoteBeforeRelease() throws Exception {
        FollowSession session = session(
                "NOTE 0,300,0,20,0,0\n"
                        + "NOTE 0,300,2,20,0,0\n");
        assertEquals(FollowSession.Status.WAITING, session.update(0b1).status);
        assertEquals(FollowSession.Status.CORRECT_HOLD, session.update(0b101).status);
        assertTrue(session.update(0).completed);
    }

    @Test
    public void repeatedSameNoteRequiresReleaseBetweenSteps() throws Exception {
        FollowSession session = session(
                "NOTE 0,300,0,20,0,0\n"
                        + "NOTE 300,300,0,20,0,0\n");
        assertEquals(FollowSession.Status.CORRECT_HOLD, session.update(0b1).status);
        assertEquals(FollowSession.Status.ADVANCED, session.update(0).status);
        assertEquals(FollowSession.Status.CORRECT_HOLD, session.update(0b1).status);
        assertTrue(session.update(0).completed);
    }

    private static FollowSession session(String text) throws Exception {
        return new FollowSession(PracticeScore.from(ScoreValidator.normalize(text)));
    }
}
