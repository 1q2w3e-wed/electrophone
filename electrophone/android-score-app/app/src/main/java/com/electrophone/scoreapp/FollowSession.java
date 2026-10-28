package com.electrophone.scoreapp;

public final class FollowSession {
    public enum Status {
        WAITING,
        WRONG,
        CORRECT_HOLD,
        ADVANCED,
        COMPLETED
    }

    public static final class Update {
        public final Status status;
        public final boolean advanced;
        public final boolean completed;
        public final int stepIndex;
        public final int stepCount;
        public final int expectedMask;

        Update(
                Status status,
                boolean advanced,
                boolean completed,
                int stepIndex,
                int stepCount,
                int expectedMask) {
            this.status = status;
            this.advanced = advanced;
            this.completed = completed;
            this.stepIndex = stepIndex;
            this.stepCount = stepCount;
            this.expectedMask = expectedMask;
        }
    }

    private final PracticeScore score;
    private int stepIndex;
    private int previousMask;
    private boolean holdingCorrectStep;
    private boolean completed;

    public FollowSession(PracticeScore score) {
        this.score = score;
        this.completed = score.steps.isEmpty();
    }

    public Update update(int downMask) {
        if (completed) {
            return snapshot(Status.COMPLETED, false);
        }
        PracticeScore.Step step = score.steps.get(stepIndex);
        int expected = step.mask;
        if (!holdingCorrectStep && (downMask & expected) == expected) {
            holdingCorrectStep = true;
            previousMask = downMask;
            return snapshot(Status.CORRECT_HOLD, false);
        }
        if (holdingCorrectStep) {
            if ((downMask & expected) == 0) {
                stepIndex++;
                holdingCorrectStep = false;
                previousMask = downMask;
                if (stepIndex >= score.steps.size()) {
                    completed = true;
                    return snapshot(Status.COMPLETED, true);
                }
                return snapshot(Status.ADVANCED, true);
            }
            previousMask = downMask;
            return snapshot(Status.CORRECT_HOLD, false);
        }

        int newPresses = downMask & ~previousMask;
        previousMask = downMask;
        if ((newPresses & ~expected) != 0) {
            return snapshot(Status.WRONG, false);
        }
        return snapshot(Status.WAITING, false);
    }

    public int getStepIndex() {
        return stepIndex;
    }

    public int getStepCount() {
        return score.steps.size();
    }

    public PracticeScore.Step currentStep() {
        return completed ? null : score.steps.get(stepIndex);
    }

    private Update snapshot(Status status, boolean advanced) {
        int expected = completed ? 0 : score.steps.get(stepIndex).mask;
        return new Update(
                status,
                advanced,
                completed,
                stepIndex,
                score.steps.size(),
                expected);
    }
}
