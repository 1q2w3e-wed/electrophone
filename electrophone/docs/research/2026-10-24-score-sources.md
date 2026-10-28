# Online Score Source Research

Date: 2026-10-24

## Purpose

Find sources that can support an online score catalog for the current
electrophone. The FPGA score format accepts at most 1024 events, note indexes
0 through 7, durations up to 2550 ms, and deltas up to 4095 ms.

An ordinary sheet-music download is not directly usable. Sources were therefore
evaluated for both legal reuse and machine-readable notation.

## Ranked Sources

### 1. OpenScore corpora

- OpenScore Lieder mirrors more than 1,200 nineteenth-century songs and states
  that the scores are released under CC0. The repository contains MuseScore
  source files and provides batch conversion to MusicXML or MIDI.
- OpenScore String Quartets follows the same model and is also CC0.

Why it is useful:

- CC0 removes the usual redistribution uncertainty.
- MuseScore files can be batch converted into MIDI or MusicXML.
- The public project requests attribution even though CC0 does not require it.

Caveats:

- The material is mostly multi-part vocal or quartet music.
- It still requires melody extraction, simplification, and listening review for
  the eight-note instrument.

Sources:

- <https://github.com/OpenScore/Lieder>
- <https://musescore.com/openscore-lieder-corpus>
- <https://github.com/OpenScore/StringQuartets>
- <https://musescore.com/openscore-string-quartets>

### 2. Mutopia Project

Mutopia describes itself as about 2,124 pieces that may be downloaded, copied,
distributed, modified, performed, and recorded. Pieces are provided as PDF,
MIDI, and editable LilyPond source. Licenses are public domain or Creative
Commons licenses, with the exact license shown on each piece.

Why it is useful:

- MIDI and LilyPond are suitable for semi-automatic extraction.
- Folk, hymn, song, and classical categories contain simpler melodies.
- Public-domain and attribution-only pieces are suitable for a competition
  catalog.

Caveats:

- Licensing is per piece, not one site-wide license.
- CC BY and CC BY-SA works require explicit attribution, and derivative scores
  must satisfy the license terms.
- Availability appears to have slowed: the latest additions shown on the home
  page are from 2019.

Sources:

- <https://www.mutopiaproject.org/>
- <https://www.mutopiaproject.org/legal.html>

### 3. Project-curated public-domain melodies

The safest and highest-quality option is a small curated catalog of traditional
melodies, arranged specifically for the eight-note instrument. OpenScore and
Mutopia can be used as reference encodings and provenance records.

Candidate categories:

- traditional children's songs;
- public-domain hymns and folk songs;
- classical themes whose compositions are public domain;
- original test melodies written for the project.

Each catalog item should retain title, aliases, composer/source, license,
arranger, note count, estimated duration, and the original reference URL.

### 4. The Session

The Session hosts traditional Irish tunes and can expose tunes as ABC notation,
which is well suited to automated melodic parsing.

Why it is useful:

- ABC is compact and machine-readable.
- The repertoire is mostly monophonic dance melodies.
- Tune pages can provide a stable source reference.

Caveat:

- Do not redistribute user-contributed transcriptions until the applicable
  content license and attribution requirements are explicitly verified.

Source:

- <https://thesession.org/tunes>

### 5. MuseScore, IMSLP, and general sheet-music sites

These are useful for research and manual transcription but are not recommended
as an automatically mirrored catalog:

- MuseScore search results can mix licenses and access restrictions; each work
  must be checked separately.
- IMSLP mostly supplies public-domain scans and PDFs. OMR is expensive and
  error-prone, so it is unsuitable for a lightweight automated pipeline.
- Commercial score sites generally prohibit bulk redistribution.

Sources:

- <https://musescore.com/>
- <https://imslp.org/>

## Recommended Catalog Design

Use a static HTTPS catalog rather than live scraping:

```text
https://scores.example.org/catalog.json
https://scores.example.org/scores/twinkle.txt
https://scores.example.org/scores/ode-to-joy.txt
```

Suggested catalog entry:

```json
{
  "id": "twinkle",
  "title": "小星星",
  "aliases": ["一闪一闪亮晶晶", "Twinkle Twinkle Little Star"],
  "source": "public-domain traditional melody",
  "license": "Public Domain",
  "arranger": "project",
  "score_url": "scores/twinkle.txt",
  "note_count": 42,
  "duration_ms": 18000
}
```

The Android app downloads `catalog.json`, caches the most recent copy, and
searches title/aliases locally. Selecting a result downloads its score file and
validates it before sending. This provides a song-name search experience without
operating a live search backend.

## Conversion Workflow

1. Select a public-domain/CC0 melody and record its source and license.
2. Extract the melody in MIDI, MusicXML, ABC, or LilyPond.
3. Transpose to the instrument's eight-note range.
4. Remove unsupported accidentals or adapt them diatonically.
5. Quantize timing to 10 ms units.
6. Reduce note count to 1024 or fewer and split long performances if needed.
7. Generate the project's `SCORE CLEAR`, `NOTE`, and `PLAY SCORE` commands.
8. Listen to the FPGA playback and correct octave folding, rhythm, and chords.
9. Store the source URL, license, and arranger with the catalog entry.
10. Publish only scores that the project is allowed to redistribute.

## Recommendation

Start with 8 to 12 carefully reviewed songs rather than attempting to import a
large corpus. Use OpenScore and Mutopia as the primary legal, machine-readable
sources, with project-made arrangements and original test melodies. Treat The
Session as a reference until licensing per tune is confirmed. Avoid automatic
mirroring from MuseScore, IMSLP, and commercial sites.
