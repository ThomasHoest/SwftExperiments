# Command Parser Training Corpus
**Project:** Bang & Olufsen Voice Controller
**Version:** 2.0
**Date:** 2026-05-01
**Languages:** English (en), Danish (da)

---

## Files

| File | Rows | Purpose |
|---|---|---|
| `corpus-clean.csv` | 8,078 | Primary training data — clean, balanced across intents and languages |
| `corpus-noise.csv` | 894 | Noise-robustness split — same labels with realistic ASR perturbations |
| `generate.py` | — | Deterministic generator. Re-run to reproduce both files exactly (seed = 42) |

Combined corpus: 8,972 labelled examples.

---

## Schema

### `corpus-clean.csv`

| Column | Type | Description |
|---|---|---|
| `text` | string | The utterance, post speaker-name strip |
| `label` | string | Intent label (one of 17 — see below) |
| `lang` | string | `en`, `da`, or `both` (for utterances valid in both languages, e.g. `"mute"`) |
| `volumeValue` | int | For `setVolume` — extracted target volume 0–100 |
| `volumeDelta` | int | For `volumeUp`/`volumeDown` — extracted step amount; empty means use default |
| `favoriteNumber` | int | For `playFavoriteByNumber` — extracted favorite slot number |
| `favoriteName` | string | For `playNamed` — extracted favorite name (best-effort; downstream fuzzy matching against live favorites list still required) |

### `corpus-noise.csv`

Same as clean, plus:

| Column | Type | Description |
|---|---|---|
| `noise` | string | The transform applied: `filler`, `dropped_article`, `repetition`, `mistranscription`, `partial_word` |
| `source` | string | The clean utterance the noisy one was derived from — useful for debugging classifier errors |

The noise corpus carries **identical intent labels** to the clean corpus. The model should learn that filler words and dropped articles do not change intent.

---

## Intents (17)

| Intent | Clean rows | Notes |
|---|---|---|
| `stop` | 500 | |
| `pause` | 460 | Naturally bounded vocabulary |
| `resume` | 500 | |
| `playDefault` | 482 | "Play music" without a named favorite |
| `playNamed` | 500 | Slot: `favoriteName` |
| `playFavoriteByNumber` | 500 | Slot: `favoriteNumber` (1–10) — **new in v2, not yet in spec** |
| `listFavorites` | 432 | |
| `setVolume` | 500 | Slot: `volumeValue` (0–100, digit and word forms) |
| `volumeUp` | 500 | Slot: `volumeDelta` (optional) |
| `volumeDown` | 500 | Slot: `volumeDelta` (optional) |
| `mute` | 417 | |
| `unmute` | 418 | |
| `confirm` | 487 | "Yes" variants |
| `cancel` | 383 | "No" / "Cancel" variants |
| `joinSpeaker` | 500 | Multi-room grouping — **new in v2, not yet in spec** |
| `leaveSpeaker` | 500 | Multi-room ungrouping — **new in v2, not yet in spec** |
| `unknown` | 500 | Out-of-domain utterances |

All intents meet or exceed the 200-example minimum from `spec-command-parser-bo-voice-control.md` §T-0305f.

The four intents below 500 (`pause`, `listFavorites`, `mute`, `unmute`, `cancel`) are limited by genuine vocabulary scarcity — there are only so many distinct ways to say "pause the music" that a real speaker would actually use. Padding them further with adverb permutations starts producing implausible phrasings.

---

## Generation Methodology

The generator builds each intent from three layers:

1. **Core templates** — handwritten canonical phrasings in both languages.
2. **Politeness wrappers** — request prefixes ("can you", "would you please", "vil du venligst") combined cartesian-style with verb stems.
3. **Adverb multiplier** — for low-volume intents, each clean example is multiplied with prepended/appended adverbs ("just stop", "stop now", "lige stop"). This pass is conservative: it skips examples that already contain a politeness marker, to avoid stacking softeners ("please could you just stop right away" sounds robotic).

After generation, two collision passes clean the corpus:

- **Same text + same label across languages** → collapsed to one row with `lang=both`. Examples: `mute`, `okay`, `pause`.
- **Same text + different labels** → first-occurrence wins. The classifier handles genuinely ambiguous tokens (e.g. `stop` as both `stop` and `cancel`) better with a single label than with both.

### Slot extraction

For the four slot-bearing intents, the generator performs post-hoc regex extraction:

- **Numeric slots** (`volumeValue`, `volumeDelta`, `favoriteNumber`): match against digit forms first, then word forms in the appropriate language (English: `forty` → 40; Danish: `fyrre` → 40).
- **`favoriteName`**: match the longest verb prefix and take everything after it. Best-effort only — the actual `FavoritesService` resolves the spoken name against the live favorites list via fuzzy matching.

---

## Noise Corpus

The noise corpus applies five transforms to a 20% sample of clean examples per intent (excluding `confirm` / `cancel` — these are too short to noise without becoming ambiguous with each other or with `unknown`):

| Transform | Description | Example |
|---|---|---|
| `filler` | Insert a filler word ("uh", "um", "øh", "altså", "ligesom") at start or middle | `"uh stop the music"` |
| `dropped_article` | Drop a common article ("the", "a", "den", "min") | `"could you turn off music"` |
| `repetition` | Repeat the first word — simulates hesitation | `"could could you list my favorites"` |
| `mistranscription` | Replace a word with a known ASR confusion | `"set valium to 45"` (volume → valium) |
| `partial_word` | Truncate one word to simulate ASR cutoff | `"separate this speak-"` |

Each noisy example carries the same label as its source. This trains the classifier to be robust to perturbations that don't change intent.

---

## Using the Corpus

### For `NLModel` training (Path B fallback parser)

Train against `corpus-clean.csv` with `text` as input and `label` as output. The CSV is shuffled across intents, but you should still hold out a validation split:

```python
import pandas as pd
from sklearn.model_selection import train_test_split

df = pd.read_csv("corpus-clean.csv")
train, val = train_test_split(df, test_size=0.15, stratify=df['label'], random_state=42)
```

Per the spec (T-0305g), the CI accuracy gate fails the build if validation accuracy drops below 85%.

### For noise-robustness evaluation

After training on clean data, run inference against `corpus-noise.csv` separately. Report accuracy per noise type — this surfaces which perturbations the model handles well and which it doesn't.

```python
df_noise = pd.read_csv("corpus-noise.csv")
for noise_type in df_noise['noise'].unique():
    subset = df_noise[df_noise['noise'] == noise_type]
    # ... predict and score
```

### For `FoundationModelParser` (Path A)

The Foundation Models parser doesn't train on this corpus — it's an in-context system. But the corpus is still useful as a **regression suite** for the parser's output: feed each example through `FoundationModelParser.parse()` and assert that `ParsedCommand.intent` matches the label.

This catches drift in either direction: if Apple updates the on-device model and intent classification accuracy drops, the regression suite catches it before users do.

---

## Reproducibility

The generator uses a fixed seed (42). Re-running `python3 generate.py` produces byte-identical output. To regenerate after editing templates:

```bash
cd corpus
python3 generate.py
```

The generator runs in under 5 seconds.

---

## Spec Alignment

This corpus introduces three intents not in the current `functional-spec-bo-voice-control.md` v1.2:

- `playFavoriteByNumber`
- `joinSpeaker`
- `leaveSpeaker`

See `spec-additions-multi-room-and-favorites-by-number.md` for the proposed user stories, acceptance criteria, error states, and parser routing additions that bring the spec in line with the corpus.
