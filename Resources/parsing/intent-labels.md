# Intent Label Map — Voxio NLModel (T-2402)

Each `CommandIntent` case maps to exactly one NLModel label.
Labels are the `rawValue` strings used in `CommandIntent` enum in `ParsedCommand.swift`.

| Label | VoiceCommand result | Notes |
|---|---|---|
| `stop` | `.stop` | |
| `pause` | `.pause` | |
| `resume` | `.resume` | |
| `playDefault` | `.playDefault` | Bare "play" with no named target |
| `playNamed` | `.playDefault` | Named favorite; `toVoiceCommand` maps to `.playDefault` (no named slot in VoiceCommand) |
| `playFavoriteByNumber` | `.playFavorite(index:)` | Ordinal 1–4; slot extracted by regex post-processing |
| `listFavorites` | `.listFavorites` | |
| `setVolume` | `.setVolume(Int)` | Absolute level 0–100; slot extracted by regex |
| `volumeUp` | `.adjustVolume(+N)` | Delta optional; default 10 if absent |
| `volumeDown` | `.adjustVolume(-N)` | Delta optional; default 10 if absent |
| `mute` | `.mute` | |
| `unmute` | `.unmute` | |
| `confirm` | `.confirm` | "Yes" affirmatives; also caught by Stage 1 regex |
| `cancel` | `.cancel` | "No" negatives; also caught by Stage 1 regex and CancelGrammar |
| `unknown` | `.unknown(String)` | Out-of-domain utterances; teach the model what NOT to match |

## Slot extraction (post-NLModel, T-2411)

NLModel emits only the intent label. Numeric slots are extracted from the raw transcript by regex in `TwoStageFallbackParser`:

- `setVolume` → `/\b(?:set volume to|volume|lydstyrke)\s+(\d{1,3})\b/`
- `volumeUp` with delta → `/\b(?:volume up|louder by|skru op|højere med)\s+(\d{1,3})\b/`
- `volumeDown` with delta → `/\b(?:volume down|quieter by|skru ned|lavere med)\s+(\d{1,3})\b/`
- `playFavoriteByNumber` → word-to-number map: one/en/et=1, two/to=2, three/tre=3, four/fire=4

Slot extraction failure on a Tier 2 hit falls through to Tier 3 (Stage 1 regex).
