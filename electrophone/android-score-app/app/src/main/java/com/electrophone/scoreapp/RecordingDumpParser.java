package com.electrophone.scoreapp;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class RecordingDumpParser {
    private static final int MAX_EVENTS = 1024;
    private static final Pattern COUNT_PATTERN = Pattern.compile("COUNT (\\d{1,4})");
    private static final Pattern EVENT_PATTERN = Pattern.compile("EVT ([0-9A-Fa-f]{8})");

    public static final class Result {
        public final int eventCount;
        public final String noteText;

        Result(int eventCount, String noteText) {
            this.eventCount = eventCount;
            this.noteText = noteText;
        }
    }

    private RecordingDumpParser() {
    }

    public static Result parse(Iterable<String> source) {
        List<String> lines = new ArrayList<>();
        for (String line : source) {
            if (line != null && !line.trim().isEmpty()) {
                lines.add(line.trim());
            }
        }
        if (lines.size() < 2) {
            throw new IllegalArgumentException("录音回传缺少 COUNT 或 END");
        }

        Matcher countMatcher = COUNT_PATTERN.matcher(lines.get(0));
        if (!countMatcher.matches()) {
            throw new IllegalArgumentException("录音回传缺少有效 COUNT");
        }
        int count;
        try {
            count = Integer.parseInt(countMatcher.group(1));
        } catch (NumberFormatException error) {
            throw new IllegalArgumentException("录音事件数量无效", error);
        }
        if (count > MAX_EVENTS) {
            throw new IllegalArgumentException("录音事件超过 1024 条");
        }
        if (lines.size() != count + 2) {
            throw new IllegalArgumentException("录音事件数量与 COUNT 不一致");
        }

        StringBuilder notes = new StringBuilder();
        for (int index = 0; index < count; index++) {
            Matcher eventMatcher = EVENT_PATTERN.matcher(lines.get(index + 1));
            if (!eventMatcher.matches()) {
                throw new IllegalArgumentException("第 " + (index + 1) + " 条录音事件格式错误");
            }
            notes.append(RecordedEventDecoder.decode(eventMatcher.group(1))).append('\n');
        }
        if (!"END".equals(lines.get(lines.size() - 1))) {
            throw new IllegalArgumentException("录音回传缺少 END");
        }
        return new Result(count, notes.toString());
    }
}
