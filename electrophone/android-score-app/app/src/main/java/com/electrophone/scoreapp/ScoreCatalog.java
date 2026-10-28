package com.electrophone.scoreapp;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.net.MalformedURLException;
import java.net.URI;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

public final class ScoreCatalog {
    public static final class ScoreEntry {
        public final String title;
        public final List<String> aliases;
        public final List<String> tags;
        public final String file;

        ScoreEntry(String title, List<String> aliases, List<String> tags, String file) {
            this.title = title;
            this.aliases = Collections.unmodifiableList(aliases);
            this.tags = Collections.unmodifiableList(tags);
            this.file = file;
        }

        public String searchableText() {
            return (title + " " + join(aliases, " ") + " " + join(tags, " "))
                    .toLowerCase(Locale.ROOT);
        }

        public String listLabel() {
            if (tags.isEmpty()) {
                return title;
            }
            return title + "  ·  " + join(tags, " / ");
        }
    }

    public final String sourceUrl;
    public final List<ScoreEntry> entries;

    private ScoreCatalog(String sourceUrl, List<ScoreEntry> entries) {
        this.sourceUrl = sourceUrl;
        this.entries = Collections.unmodifiableList(entries);
    }

    public static ScoreCatalog parse(String json, String sourceUrl) throws JSONException {
        JSONObject root = new JSONObject(json);
        JSONArray scores = root.optJSONArray("scores");
        if (scores == null) {
            throw new JSONException("catalog.json 缺少 scores 数组");
        }
        List<ScoreEntry> entries = new ArrayList<>();
        for (int index = 0; index < scores.length(); index++) {
            JSONObject item = scores.getJSONObject(index);
            String title = item.optString("title", "").trim();
            String file = item.optString("file", "").trim();
            if (title.isEmpty() || file.isEmpty()) {
                continue;
            }
            entries.add(new ScoreEntry(
                    title,
                    readStrings(item.optJSONArray("aliases")),
                    readStrings(item.optJSONArray("tags")),
                    file
            ));
        }
        return new ScoreCatalog(sourceUrl, entries);
    }

    public List<ScoreEntry> search(String query) {
        String needle = query == null ? "" : query.trim().toLowerCase(Locale.ROOT);
        if (needle.isEmpty()) {
            return new ArrayList<>(entries);
        }
        List<ScoreEntry> matches = new ArrayList<>();
        for (ScoreEntry entry : entries) {
            if (entry.searchableText().contains(needle)) {
                matches.add(entry);
            }
        }
        return matches;
    }

    public String resolve(ScoreEntry entry) throws MalformedURLException {
        if (entry.file.startsWith("https://") || entry.file.startsWith("asset:///")) {
            return entry.file;
        }
        if (sourceUrl.startsWith("asset:///")) {
            String directory = sourceUrl.substring(0, sourceUrl.lastIndexOf('/') + 1);
            return directory + entry.file.replaceFirst("^/", "");
        }
        try {
            return URI.create(sourceUrl).resolve(entry.file).toASCIIString();
        } catch (IllegalArgumentException error) {
            throw new MalformedURLException("无法解析曲谱地址：" + entry.file);
        }
    }

    private static List<String> readStrings(JSONArray array) {
        List<String> values = new ArrayList<>();
        if (array == null) {
            return values;
        }
        for (int index = 0; index < array.length(); index++) {
            String value = array.optString(index, "").trim();
            if (!value.isEmpty()) {
                values.add(value);
            }
        }
        return values;
    }

    private static String join(List<String> values, String separator) {
        StringBuilder result = new StringBuilder();
        for (int index = 0; index < values.size(); index++) {
            if (index > 0) {
                result.append(separator);
            }
            result.append(values.get(index));
        }
        return result.toString();
    }
}
