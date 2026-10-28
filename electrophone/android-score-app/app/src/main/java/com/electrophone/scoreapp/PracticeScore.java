package com.electrophone.scoreapp;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public final class PracticeScore {
    public static final class Step {
        public final List<Integer> notes;
        public final int startMs;
        public final int durationMs;
        public final int mask;

        Step(List<Integer> notes, int startMs, int durationMs) {
            List<Integer> sorted = new ArrayList<>(notes);
            Collections.sort(sorted);
            this.notes = Collections.unmodifiableList(sorted);
            this.startMs = startMs;
            this.durationMs = durationMs;
            int value = 0;
            for (int note : sorted) {
                value |= 1 << note;
            }
            this.mask = value;
        }
    }

    public final List<Step> steps;

    private PracticeScore(List<Step> steps) {
        this.steps = Collections.unmodifiableList(steps);
    }

    public static PracticeScore from(ScoreValidator.Result score) {
        List<Step> result = new ArrayList<>();
        List<Integer> chord = null;
        int chordDuration = 0;
        int chordStart = 0;
        int timelineMs = 0;
        for (String command : score.commands) {
            if (!command.startsWith("NOTE ")) {
                continue;
            }
            String[] fields = command.substring(5).split(",");
            int delta = Integer.parseInt(fields[0]);
            int duration = Integer.parseInt(fields[1]);
            int note = Integer.parseInt(fields[2]);
            if (chord == null || delta > 0) {
                if (chord != null) {
                    result.add(new Step(chord, chordStart, chordDuration));
                }
                timelineMs += delta;
                chord = new ArrayList<>();
                chordDuration = duration;
                chordStart = timelineMs;
            } else {
                chordDuration = Math.max(chordDuration, duration);
            }
            if (!chord.contains(note)) {
                chord.add(note);
            }
        }
        if (chord != null && !chord.isEmpty()) {
            result.add(new Step(chord, chordStart, chordDuration));
        }
        return new PracticeScore(result);
    }
}
