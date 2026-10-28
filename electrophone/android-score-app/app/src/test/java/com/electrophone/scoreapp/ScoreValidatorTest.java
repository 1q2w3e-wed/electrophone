package com.electrophone.scoreapp;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

import org.junit.Test;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

public final class ScoreValidatorTest {
    @Test
    public void addsMissingControlCommandsAndPreservesNotes() throws Exception {
        ScoreValidator.Result result = ScoreValidator.normalize(
                "# demo\nNOTE 0,500,2,20,2,0\nNOTE 250,500,3,18,0,1\n");
        assertEquals(2, result.noteCount);
        assertEquals("SCORE CLEAR", result.commands.get(0));
        assertEquals("NOTE 0,500,2,20,2,0", result.commands.get(1));
        assertEquals("NOTE 250,500,3,18,0,1", result.commands.get(2));
        assertEquals("PLAY SCORE", result.commands.get(3));
    }

    @Test
    public void rejectsDurationNotDivisibleByTen() {
        try {
            ScoreValidator.normalize("NOTE 0,505,2,20,0,0\n");
            fail("Expected invalid duration to fail");
        } catch (ScoreValidator.FormatException expected) {
            assertTrue(expected.getMessage().contains("10 的倍数"));
        }
    }

    @Test
    public void rejectsUnknownCommandWithLineNumber() {
        try {
            ScoreValidator.normalize("SCORE CLEAR\nTEMPO 120\n");
            fail("Expected unknown command to fail");
        } catch (ScoreValidator.FormatException expected) {
            assertTrue(expected.getMessage().contains("第 2 行"));
        }
    }

    @Test
    public void searchesCatalogAliasesAndResolvesRelativeFiles() throws Exception {
        String json = "{\"scores\":[{\"title\":\"小星星\","
                + "\"aliases\":[\"Twinkle\"],\"file\":\"scores/x.txt\",\"tags\":[\"儿歌\"]}]}";
        ScoreCatalog catalog = ScoreCatalog.parse(json, "https://example.com/app/catalog.json");
        List<ScoreCatalog.ScoreEntry> chinese = catalog.search("星");
        List<ScoreCatalog.ScoreEntry> english = catalog.search("twinkle");
        assertEquals(1, chinese.size());
        assertEquals(1, english.size());
        assertEquals(
                "https://example.com/app/scores/x.txt",
                catalog.resolve(chinese.get(0)));
    }

    @Test
    public void bundledCatalogAndScoresAreValid() throws Exception {
        Path assets = Path.of("src/main/assets");
        String json = new String(
                Files.readAllBytes(assets.resolve("catalog.json")),
                StandardCharsets.UTF_8);
        ScoreCatalog catalog = ScoreCatalog.parse(json, "asset:///catalog.json");
        assertTrue(catalog.entries.size() >= 7);
        for (ScoreCatalog.ScoreEntry entry : catalog.entries) {
            String relative = entry.file.replaceFirst("^scores/", "");
            String text = new String(
                    Files.readAllBytes(assets.resolve("scores").resolve(relative)),
                    StandardCharsets.UTF_8);
            ScoreValidator.normalize(text);
        }
    }

    @Test
    public void resolvesUnicodeScorePathsToHttpsUrl() throws Exception {
        String json = "{\"scores\":[{\"title\":\"小星星\","
                + "\"file\":\"scores/小星星.txt\"}]}";
        ScoreCatalog catalog = ScoreCatalog.parse(json, "https://example.com/app/catalog.json");
        String resolved = catalog.resolve(catalog.entries.get(0));
        assertTrue(resolved.startsWith("https://example.com/app/scores/"));
        assertTrue(resolved.contains("%E5%B0%8F%E6%98%9F%E6%98%9F"));
    }
}
