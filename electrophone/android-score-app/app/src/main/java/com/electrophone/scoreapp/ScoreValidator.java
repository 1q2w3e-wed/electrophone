package com.electrophone.scoreapp;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

public final class ScoreValidator {
    private static final int MAX_NOTES = 1024;

    private ScoreValidator() {
    }

    public static final class Result {
        public final List<String> commands;
        public final String normalizedText;
        public final int noteCount;

        Result(List<String> commands) {
            this.commands = Collections.unmodifiableList(commands);
            StringBuilder text = new StringBuilder();
            for (String command : commands) {
                text.append(command).append('\n');
            }
            this.normalizedText = text.toString();
            this.noteCount = commands.size() - 2;
        }
    }

    public static final class FormatException extends Exception {
        public FormatException(String message) {
            super(message);
        }
    }

    public static Result normalize(String input) throws FormatException {
        if (input == null) {
            throw new FormatException("曲谱内容为空");
        }
        String text = input.replace("\uFEFF", "");
        String[] rawLines = text.split("\\r?\\n", -1);
        List<String> notes = new ArrayList<>();

        for (int index = 0; index < rawLines.length; index++) {
            String line = rawLines[index].trim();
            if (line.isEmpty() || line.startsWith("#")) {
                continue;
            }
            String upper = line.toUpperCase(Locale.ROOT);
            if ("SCORE CLEAR".equals(upper) || "PLAY SCORE".equals(upper)) {
                continue;
            }
            if (!upper.startsWith("NOTE ")) {
                throw new FormatException("第 " + (index + 1) + " 行不是支持的 NOTE 命令");
            }
            validateNote(upper.substring(5), index + 1);
            notes.add(upper);
            if (notes.size() > MAX_NOTES) {
                throw new FormatException("NOTE 数量超过 1024 条");
            }
        }

        if (notes.isEmpty()) {
            throw new FormatException("曲谱中没有 NOTE 事件");
        }

        List<String> commands = new ArrayList<>(notes.size() + 2);
        commands.add("SCORE CLEAR");
        commands.addAll(notes);
        commands.add("PLAY SCORE");
        return new Result(commands);
    }

    private static void validateNote(String fieldsText, int lineNumber) throws FormatException {
        String[] fields = fieldsText.split(",", -1);
        if (fields.length != 6) {
            throw new FormatException("第 " + lineNumber + " 行 NOTE 必须包含 6 个数字");
        }
        int[] values = new int[6];
        for (int index = 0; index < fields.length; index++) {
            String field = fields[index].trim();
            if (!field.matches("-?\\d+")) {
                throw new FormatException("第 " + lineNumber + " 行第 " + (index + 1) + " 项不是整数");
            }
            try {
                values[index] = Integer.parseInt(field);
            } catch (NumberFormatException error) {
                throw new FormatException("第 " + lineNumber + " 行数字过大");
            }
        }

        int delta = values[0];
        int duration = values[1];
        int note = values[2];
        int velocity = values[3];
        int tone = values[4];
        int effect = values[5];
        if (delta < 0 || delta > 4095) {
            throw new FormatException("第 " + lineNumber + " 行 delta_ms 必须在 0 到 4095");
        }
        if (duration < 10 || duration > 2550 || duration % 10 != 0) {
            throw new FormatException("第 " + lineNumber + " 行 duration_ms 必须是 10 到 2550 且为 10 的倍数");
        }
        if (note < 0 || note > 7) {
            throw new FormatException("第 " + lineNumber + " 行 note 必须在 0 到 7");
        }
        if (velocity < 0 || velocity > 31) {
            throw new FormatException("第 " + lineNumber + " 行 velocity 必须在 0 到 31");
        }
        if (tone < 0 || tone > 3) {
            throw new FormatException("第 " + lineNumber + " 行 tone 必须在 0 到 3");
        }
        if (effect < 0 || effect > 3) {
            throw new FormatException("第 " + lineNumber + " 行 effect 必须在 0 到 3");
        }
    }
}
