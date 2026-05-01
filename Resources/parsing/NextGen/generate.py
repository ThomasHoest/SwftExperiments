"""
Corpus generator for the B&O Voice Controller command parser.

Strategy:
- For each intent, define a set of phrase templates with slot variables.
- Each slot has a list of lexical variants (synonyms, fillers, articles).
- Combinatorial expansion produces clean examples; we sample down to
  the target per intent.
- A separate noise-variant pass takes a subset of clean examples and
  applies realistic ASR / spoken-language perturbations.

Two outputs:
- corpus-clean.csv     (text, label, lang)        — primary training data
- corpus-noise.csv     (text, label, lang, noise) — noise-robustness split
"""

import csv
import itertools
import random
import re
from pathlib import Path

random.seed(42)

TARGET_PER_INTENT = 500
NOISE_FRACTION = 0.20  # of TARGET_PER_INTENT — so ~100 noise examples per intent

OUT_DIR = Path("/home/claude/corpus")
OUT_DIR.mkdir(exist_ok=True)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def expand(templates, slots):
    """Cartesian expansion of templates with slot fillers.

    `templates` is a list of strings with {slot} placeholders.
    `slots` is a dict mapping slot name -> list of fillers.
    """
    out = []
    for tmpl in templates:
        slot_names = re.findall(r"\{(\w+)\}", tmpl)
        if not slot_names:
            out.append(tmpl)
            continue
        value_lists = [slots[name] for name in slot_names]
        for combo in itertools.product(*value_lists):
            mapping = dict(zip(slot_names, combo))
            out.append(tmpl.format(**mapping))
    return out


def normalise(s):
    """Collapse whitespace and strip; lowercase nothing (preserve names)."""
    return re.sub(r"\s+", " ", s).strip()


def dedupe_preserve(seq):
    seen = set()
    out = []
    for s in seq:
        s = normalise(s)
        key = s.lower()
        if key in seen or not s:
            continue
        seen.add(key)
        out.append(s)
    return out


def sample_to(target, examples):
    """Sample `target` examples; if fewer exist, return all of them."""
    if len(examples) <= target:
        return examples
    return random.sample(examples, target)


def multiply_with_adverbs(examples, lang, max_adverbs_per_example=2):
    """For each base example, produce additional variants with adverbs
    inserted in natural positions. Helps low-volume intents reach the
    target without inventing implausible phrasings.

    Adverbs go either at the start ('just stop') or at the end ('stop now').
    Skip examples that would produce awkward output:
    - Already long (>6 tokens)
    - Already start or end with an adverb
    - Already contain a politeness phrase like 'please' or 'venligst'
      (stacking softeners produces robotic output)
    """
    adverbs = EN_ADVERBS if lang == "en" else DA_ADVERBS
    politeness_markers = (
        ["please", "kindly", "would you", "could you", "can you"]
        if lang == "en"
        else ["venligst", "vær venlig", "kan du", "vil du", "kunne du", "ville du"]
    )

    out = list(examples)
    for ex in examples:
        toks = ex.split()
        if len(toks) > 6 or len(toks) < 1:
            continue
        first_tok = toks[0].lower()
        last_tok = toks[-1].lower()
        if first_tok in adverbs or last_tok in adverbs:
            continue
        # Skip if it already has a politeness marker — stacking sounds robotic
        ex_lower = " " + ex.lower() + " "
        if any(f" {m} " in ex_lower for m in politeness_markers):
            continue
        chosen = random.sample(adverbs, min(max_adverbs_per_example, len(adverbs)))
        for adv in chosen:
            # Prefer prepending — "just stop" sounds more natural than "stop just"
            out.append(f"{adv} {ex}")
            # Only append if the adverb naturally fits at the end ("now",
            # "right away", "med det samme", "nu" — all work; "just"
            # doesn't, "lige" doesn't).
            if adv in ("now", "right now", "right away", "real quick",
                       "nu", "med det samme", "hurtigt"):
                out.append(f"{ex} {adv}")
    return out


# ---------------------------------------------------------------------------
# Shared lexical variants
# ---------------------------------------------------------------------------

# Politeness / question prefixes — Danish
DA_POLITE = [
    "kan du", "vil du", "kunne du", "ville du",
    "vær venlig at", "kan du venligst", "vil du venligst",
    "kunne du venligst", "ville du venligst",
    "må jeg bede dig om at", "jeg vil gerne have at du",
    "jeg vil bede dig om at", "vær så venlig at",
]

# Politeness / question prefixes — English
EN_POLITE = [
    "can you", "could you", "would you", "please",
    "can you please", "could you please", "would you please",
    "i want you to", "i'd like you to", "i need you to",
    "would you mind to", "could you kindly", "kindly",
    "i would like you to", "go ahead and",
]

# Adverbs that can intensify or soften commands without changing intent
DA_ADVERBS = ["lige", "bare", "venligst", "nu", "hurtigt", "med det samme"]
EN_ADVERBS = ["just", "quickly", "right now", "now", "real quick", "right away"]

# Numbers 0–100, both digit form and Danish/English word form.
# We don't need every value — covering boundaries, common round numbers,
# and a representative spread is sufficient.
VOL_DIGITS = [
    "0", "1", "5", "10", "15", "20", "25", "30", "35", "40", "45",
    "50", "55", "60", "65", "70", "75", "80", "85", "90", "95", "99", "100",
]

VOL_WORDS_EN = {
    "0": "zero", "5": "five", "10": "ten", "15": "fifteen", "20": "twenty",
    "25": "twenty-five", "30": "thirty", "40": "forty", "50": "fifty",
    "60": "sixty", "70": "seventy", "75": "seventy-five", "80": "eighty",
    "90": "ninety", "100": "one hundred",
}

VOL_WORDS_DA = {
    "0": "nul", "5": "fem", "10": "ti", "15": "femten", "20": "tyve",
    "25": "femogtyve", "30": "tredive", "40": "fyrre", "50": "halvtreds",
    "60": "tres", "70": "halvfjerds", "75": "femoghalvfjerds",
    "80": "firs", "90": "halvfems", "100": "hundrede",
}

# Step amounts for relative volume — small numbers are most natural
VOL_STEPS = ["5", "10", "15", "20", "25", "30"]
VOL_STEPS_EN = {"5": "five", "10": "ten", "15": "fifteen", "20": "twenty", "25": "twenty-five", "30": "thirty"}
VOL_STEPS_DA = {"5": "fem", "10": "ti", "15": "femten", "20": "tyve", "25": "femogtyve", "30": "tredive"}

# Favorite numbers 1–10 (B&O speakers typically expose ~10 favorite slots)
FAV_NUMS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
FAV_NUM_WORDS_EN = {
    "1": "one", "2": "two", "3": "three", "4": "four", "5": "five",
    "6": "six", "7": "seven", "8": "eight", "9": "nine", "10": "ten",
}
FAV_NUM_WORDS_DA = {
    "1": "et", "2": "to", "3": "tre", "4": "fire", "5": "fem",
    "6": "seks", "7": "syv", "8": "otte", "9": "ni", "10": "ti",
}

# Sample favorite names — used for playNamed. These should look like real
# music, podcasts, and radio stations a Danish-speaking B&O household might use.
FAVORITE_NAMES = [
    # Radio (real Danish stations)
    "P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8 Jazz",
    "Radio 24syv", "Radio 100", "Nova FM", "The Voice", "Pop FM",
    # International radio
    "BBC Radio 1", "BBC Radio 4", "NPR", "Jazz FM", "Classic FM",
    # Artists
    "The Beatles", "Daft Punk", "Pink Floyd", "Coldplay", "Adele",
    "Taylor Swift", "Kendrick Lamar", "Bob Dylan", "Miles Davis",
    "Kim Larsen", "Lukas Graham", "MØ", "Mew", "Volbeat",
    # Genres / playlists
    "jazz", "classical", "rock", "pop", "hip hop", "electronic",
    "ambient music", "morning playlist", "workout mix", "study music",
    "klassisk musik", "klassisk", "rolig musik", "morgenmusik",
    "fest playlisten", "afslapningsmusik",
    # Podcasts
    "The Daily", "This American Life", "Genstart", "Mads og Monopolet",
]

# Speaker names mentioned in joinSpeaker / leaveSpeaker examples
ROOM_NAMES_EN = [
    "the kitchen", "the living room", "the bedroom", "the bathroom",
    "the dining room", "the office", "the patio", "the garden",
    "the hallway", "the basement", "the upstairs speaker",
]
ROOM_NAMES_DA = [
    "køkkenet", "stuen", "soveværelset", "badeværelset",
    "spisestuen", "kontoret", "terrassen", "haven",
    "entréen", "kælderen", "ovenpå",
]


# ---------------------------------------------------------------------------
# Per-intent generators
# ---------------------------------------------------------------------------

def gen_stop():
    en_core = [
        "stop", "stop it", "stop the music", "stop playing",
        "stop the audio", "stop now", "stop already", "just stop",
        "stop right now", "stop right there", "stop the song",
        "stop the track", "stop this", "stop that",
        "kill it", "kill the music", "kill the sound", "kill the audio",
        "shut it off", "shut it down", "shut off the music",
        "turn it off", "turn off the music", "turn the music off",
        "turn off the audio", "turn off the speaker",
        "end playback", "end the music", "end it", "end the song",
        "cease playback", "cease the music",
        "i want it to stop", "i want it off", "i want silence",
        "make it stop", "make the music stop",
        "that's enough", "enough music", "enough already",
        "no more music", "no more playing",
    ]
    en_polite = [f"{p} stop" for p in EN_POLITE] + \
                [f"{p} stop the music" for p in EN_POLITE] + \
                [f"{p} stop playing" for p in EN_POLITE] + \
                [f"{p} turn off the music" for p in EN_POLITE] + \
                [f"{p} kill the music" for p in EN_POLITE] + \
                [f"{p} end the music" for p in EN_POLITE]

    da_core = [
        "stop", "stop det", "stop musikken", "stop afspilningen",
        "stop den", "stop nu", "stop bare", "bare stop",
        "stop med det samme", "stop helt", "stop sangen", "stop nummeret",
        "hold op", "hold op nu", "hold op med at spille",
        "hold op med musikken", "hold op med det",
        "sluk", "sluk musikken", "sluk for musikken",
        "sluk afspilningen", "sluk for det", "sluk for sangen",
        "afslut afspilningen", "afslut musikken", "afslut sangen",
        "stands musikken", "stands afspilningen", "stands sangen",
        "stop al musik", "stop al lyd",
        "jeg vil have det til at stoppe", "jeg vil have ro",
        "få det til at stoppe", "få musikken til at stoppe",
        "det er nok", "nok musik", "nok nu",
        "ikke mere musik", "ikke mere afspilning",
    ]
    da_polite = [f"{p} stoppe" for p in DA_POLITE] + \
                [f"{p} stoppe musikken" for p in DA_POLITE] + \
                [f"{p} slukke for musikken" for p in DA_POLITE] + \
                [f"{p} stoppe afspilningen" for p in DA_POLITE] + \
                [f"{p} holde op" for p in DA_POLITE] + \
                [f"{p} afslutte musikken" for p in DA_POLITE]

    en = en_core + en_polite
    da = da_core + da_polite
    return [(t, "en") for t in dedupe_preserve(en)] + \
           [(t, "da") for t in dedupe_preserve(da)]


def gen_pause():
    en_core = [
        "pause", "pause it", "pause the music", "pause playback",
        "pause the audio", "pause for a moment", "pause for now",
        "pause the song", "pause the track", "pause this",
        "pause the speaker", "pause everything",
        "hold on", "hold the music", "hold the audio",
        "hold the song", "hold playback",
        "freeze it", "freeze the music", "freeze playback",
        "halt the music", "halt playback", "halt it",
        "wait", "wait a moment", "wait a second", "wait there",
        "take a break", "give it a rest", "break the music",
        "i need a pause", "i want to pause", "let's pause",
    ]
    en_polite = [f"{p} pause" for p in EN_POLITE] + \
                [f"{p} pause the music" for p in EN_POLITE] + \
                [f"{p} pause it" for p in EN_POLITE] + \
                [f"{p} hold the music" for p in EN_POLITE] + \
                [f"{p} freeze the music" for p in EN_POLITE]

    da_core = [
        "pause", "pause den", "pause musikken", "pause afspilningen",
        "pause sangen", "pause nummeret", "pause det",
        "sæt på pause", "sæt det på pause", "sæt den på pause",
        "sæt musikken på pause", "sæt afspilningen på pause",
        "sæt sangen på pause", "sæt nummeret på pause",
        "hold pause", "tag en pause", "lav en pause",
        "afbryd kort", "afbryd lige", "afbryd musikken",
        "vent lidt", "vent et øjeblik", "vent et sekund", "vent her",
        "stop midlertidigt", "midlertidig stop",
        "jeg vil pause", "lad os pause", "lad os tage en pause",
        "giv mig en pause",
    ]
    da_polite = [f"{p} pause" for p in DA_POLITE] + \
                [f"{p} sætte på pause" for p in DA_POLITE] + \
                [f"{p} pause musikken" for p in DA_POLITE] + \
                [f"{p} holde pause" for p in DA_POLITE] + \
                [f"{p} pause afspilningen" for p in DA_POLITE]

    en = en_core + en_polite
    da = da_core + da_polite
    return [(t, "en") for t in dedupe_preserve(en)] + \
           [(t, "da") for t in dedupe_preserve(da)]


def gen_resume():
    en_core = [
        "resume", "resume playback", "resume the music", "resume playing",
        "resume the song", "resume the track", "resume from where it stopped",
        "continue", "continue playing", "continue the music", "continue the song",
        "keep playing", "keep going", "keep the music going",
        "play again", "play it again", "start playing again",
        "pick up where you left off", "pick it back up",
        "unpause", "unpause it", "unpause the music",
        "carry on", "carry on playing", "go on", "go on playing",
        "back to playing", "back to music", "get back to it",
        "let it play", "let the music play", "let it resume",
        "i want it back on", "play more", "more music",
    ]
    en_polite = [f"{p} resume" for p in EN_POLITE] + \
                [f"{p} continue" for p in EN_POLITE] + \
                [f"{p} keep playing" for p in EN_POLITE] + \
                [f"{p} unpause" for p in EN_POLITE] + \
                [f"{p} resume the music" for p in EN_POLITE] + \
                [f"{p} carry on" for p in EN_POLITE]

    da_core = [
        "genoptag", "genoptag afspilningen", "genoptag musikken",
        "genoptag sangen", "genoptag nummeret",
        "fortsæt", "fortsæt afspilningen", "fortsæt musikken",
        "fortsæt sangen", "fortsæt med musikken",
        "spil videre", "spil videre tak", "fortsæt med at spille",
        "spil igen", "spil det igen", "start igen",
        "kør videre", "fortsæt hvor du slap", "tag tråden op igen",
        "ophæv pause", "fjern pause", "tag pausen af",
        "afslut pausen", "stop pausen",
        "lad det spille videre", "lad musikken køre videre",
        "tilbage til musikken", "tilbage til afspilningen",
        "jeg vil have musikken tilbage", "mere musik", "spil mere",
    ]
    da_polite = [f"{p} fortsætte" for p in DA_POLITE] + \
                [f"{p} genoptage" for p in DA_POLITE] + \
                [f"{p} spille videre" for p in DA_POLITE] + \
                [f"{p} fortsætte musikken" for p in DA_POLITE] + \
                [f"{p} ophæve pausen" for p in DA_POLITE]

    en = en_core + en_polite
    da = da_core + da_polite
    return [(t, "en") for t in dedupe_preserve(en)] + \
           [(t, "da") for t in dedupe_preserve(da)]


def gen_play_default():
    en_templates = [
        "play", "play music", "play some music", "play something",
        "play anything", "play whatever you want",
        "start music", "start the music", "start playing", "start playback",
        "start something", "begin playing", "begin the music",
        "put on music", "put on some music", "put something on",
        "put on anything", "put on a song",
        "play the usual", "play my usual", "play what i was listening to",
        "play the last thing", "play whatever was on",
        "resume my music", "play my music", "play my songs",
        "music please", "some music please", "i want music",
        "i want to listen to music", "i'd like some music",
        "let's hear some music", "give me some music", "fire up some music",
        "kick off some music", "queue up music",
        "throw on some tunes", "put on some tunes", "play some tunes",
    ]
    en_polite = [f"{p} play music" for p in EN_POLITE] + \
                [f"{p} put on some music" for p in EN_POLITE] + \
                [f"{p} start playing" for p in EN_POLITE] + \
                [f"{p} play something" for p in EN_POLITE] + \
                [f"{p} put on a song" for p in EN_POLITE]

    da_templates = [
        "spil", "afspil", "spil musik", "afspil musik",
        "spil noget musik", "afspil noget musik", "spil noget",
        "afspil noget", "spil hvad som helst",
        "start musikken", "start afspilningen", "begynd at spille",
        "start noget", "start lidt musik",
        "sæt musik på", "sæt noget musik på", "sæt noget på",
        "sæt en sang på", "sæt lidt musik på",
        "spil det sædvanlige", "spil det jeg hørte sidst",
        "spil mit sædvanlige", "spil mine sange",
        "fortsæt med musikken", "musik tak", "lidt musik tak",
        "jeg vil høre musik", "jeg vil gerne høre musik",
        "lad os høre musik", "giv mig noget musik",
        "smid noget musik på", "kør noget musik",
    ]
    da_polite = [f"{p} spille musik" for p in DA_POLITE] + \
                [f"{p} afspille musik" for p in DA_POLITE] + \
                [f"{p} sætte musik på" for p in DA_POLITE] + \
                [f"{p} starte musikken" for p in DA_POLITE] + \
                [f"{p} spille noget" for p in DA_POLITE]

    en = en_templates + en_polite
    da = da_templates + da_polite
    return [(t, "en") for t in dedupe_preserve(en)] + \
           [(t, "da") for t in dedupe_preserve(da)]


def gen_list_favorites():
    en_core = [
        "what are my favorites", "what are my favourites",
        "list my favorites", "list my favourites",
        "list favorites", "list favourites", "list the favorites",
        "show favorites", "show favourites",
        "show my favorites", "show my favourites", "show me my favorites",
        "show me the favorites", "show me what's saved",
        "tell me my favorites", "tell me my favourites",
        "tell me what's in favorites", "name my favorites",
        "what favorites do i have", "what favourites do i have",
        "which favorites are there", "which favourites do i have",
        "which favorites are saved", "what's saved as a favorite",
        "read out my favorites", "read my favorites", "read the favorites",
        "what's in my favorites", "what's on my favorites list",
        "what's on the favorites list", "what's on the favourites list",
        "favorites list", "favourites list", "the favorites list",
        "what presets do i have", "list my presets", "show my presets",
        "what stations are saved", "what stations do i have",
    ]
    en_polite = [f"{p} list my favorites" for p in EN_POLITE] + \
                [f"{p} show me my favorites" for p in EN_POLITE] + \
                [f"{p} tell me my favorites" for p in EN_POLITE] + \
                [f"{p} read out my favorites" for p in EN_POLITE]

    da_core = [
        "vis mine favoritter", "vis favoritter", "vis favoritterne",
        "vis hele listen", "vis listen",
        "list mine favoritter", "list favoritter", "list favoritterne",
        "list mine presets", "list mine stationer",
        "hvad er mine favoritter", "hvad har jeg som favoritter",
        "hvad har jeg gemt som favoritter", "hvad har jeg på listen",
        "hvilke favoritter har jeg", "hvilke favoritter er der",
        "hvilke favoritter er gemt", "hvilke stationer har jeg",
        "vis mig mine favoritter", "vis mig favoritlisten",
        "vis mig hvad der er gemt",
        "fortæl mig mine favoritter", "fortæl mig favoritlisten",
        "fortæl mig hvad der er på listen", "nævn mine favoritter",
        "læs mine favoritter op", "læs favoritterne op",
        "læs listen op", "læs hele listen op",
        "hvad står der på min favoritliste", "min favoritliste",
        "favoritlisten", "hele favoritlisten",
        "hvilke presets har jeg", "vis mine presets",
        "hvad er gemt som favoritter", "hvad har jeg gemt",
    ]
    da_polite = [f"{p} liste mine favoritter" for p in DA_POLITE] + \
                [f"{p} vise mine favoritter" for p in DA_POLITE] + \
                [f"{p} læse mine favoritter op" for p in DA_POLITE] + \
                [f"{p} fortælle mig mine favoritter" for p in DA_POLITE]

    en = en_core + en_polite
    da = da_core + da_polite
    return [(t, "en") for t in dedupe_preserve(en)] + \
           [(t, "da") for t in dedupe_preserve(da)]


def gen_mute():
    en_core = [
        "mute", "mute it", "mute the speaker", "mute the music",
        "mute the audio", "mute everything", "mute the song",
        "mute this", "mute that", "mute now",
        "silence", "silence it", "silence the speaker",
        "silence the music", "silence the audio",
        "go silent", "go quiet", "be quiet", "be silent", "shut up",
        "no sound", "kill the sound", "kill the audio",
        "cut the sound", "cut the audio", "cut audio",
        "sound off", "audio off", "silent mode", "silent please",
        "i want silence", "i need silence", "i want it muted",
        "drop the sound", "drop the audio",
    ]
    en_polite = [f"{p} mute" for p in EN_POLITE] + \
                [f"{p} mute the speaker" for p in EN_POLITE] + \
                [f"{p} silence it" for p in EN_POLITE] + \
                [f"{p} kill the sound" for p in EN_POLITE]

    da_core = [
        "mute", "lydløs", "sæt på lydløs", "slå på lydløs",
        "sæt højttaleren på lydløs", "sæt musikken på lydløs",
        "slå lyden fra", "sluk lyden", "sluk for lyden",
        "sluk for al lyd", "fjern lyden", "fjern al lyd",
        "ingen lyd", "nul lyd", "ingen lyd tak",
        "tavs", "vær tavs", "vær stille", "stille",
        "dæmp helt", "dæmp lyden", "dæmp musikken", "lyd fra",
        "jeg vil have stilhed", "jeg vil have ro",
        "luk for lyden", "luk lyden", "luk for musikken",
    ]
    da_polite = [f"{p} mute" for p in DA_POLITE] + \
                [f"{p} slå lyden fra" for p in DA_POLITE] + \
                [f"{p} sætte på lydløs" for p in DA_POLITE] + \
                [f"{p} slukke for lyden" for p in DA_POLITE] + \
                [f"{p} dæmpe lyden" for p in DA_POLITE]

    en = en_core + en_polite
    da = da_core + da_polite
    return [(t, "en") for t in dedupe_preserve(en)] + \
           [(t, "da") for t in dedupe_preserve(da)]


def gen_unmute():
    en_core = [
        "unmute", "unmute it", "unmute the speaker", "unmute the music",
        "unmute the audio", "unmute everything", "unmute now",
        "sound on", "audio on", "sound back on", "audio back on",
        "turn the sound back on", "turn the audio back on",
        "turn on the sound", "turn on the audio",
        "bring back the sound", "bring the sound back", "bring sound back",
        "restore sound", "restore the sound", "restore the volume", "restore audio",
        "restore the audio", "give me the sound back",
        "i want sound back", "i want sound", "give me sound back",
        "remove mute", "exit silent mode", "exit mute",
        "stop the mute", "end mute", "end silent mode",
        "lift the mute", "lift mute",
    ]
    en_polite = [f"{p} unmute" for p in EN_POLITE] + \
                [f"{p} turn the sound back on" for p in EN_POLITE] + \
                [f"{p} restore the sound" for p in EN_POLITE] + \
                [f"{p} bring back the sound" for p in EN_POLITE]

    da_core = [
        "unmute", "tænd lyden", "tænd for lyden", "tænd lyden igen",
        "tænd for musikken", "tænd for højttaleren",
        "fjern lydløs", "fjern dæmpning", "fjern dæmpningen",
        "ophæv lydløs", "ophæv dæmpningen", "ophæv mute",
        "lyd til", "lyd på", "lyd igen", "lyd tilbage",
        "giv mig lyden tilbage", "giv mig lyden igen",
        "tilbage til lyd", "tilbage til at have lyd",
        "fjern mute", "stop lydløs", "afslut lydløs",
        "sluk lydløs", "sluk for lydløs",
        "jeg vil have lyden tilbage", "jeg vil høre noget igen",
        "tilbage til normal lyd", "normal lyd igen",
    ]
    da_polite = [f"{p} tænde for lyden" for p in DA_POLITE] + \
                [f"{p} fjerne lydløs" for p in DA_POLITE] + \
                [f"{p} ophæve dæmpningen" for p in DA_POLITE] + \
                [f"{p} fjerne dæmpningen" for p in DA_POLITE] + \
                [f"{p} tænde lyden igen" for p in DA_POLITE]

    en = en_core + en_polite
    da = da_core + da_polite
    return [(t, "en") for t in dedupe_preserve(en)] + \
           [(t, "da") for t in dedupe_preserve(da)]


def gen_leave_speaker():
    en_core = [
        "leave the group", "leave group", "leave the speakers",
        "leave the others", "leave", "leave the cluster",
        "disconnect", "disconnect from group", "disconnect from the group",
        "disconnect from the speakers", "disconnect from everyone",
        "disconnect from the others", "disconnect now",
        "separate", "separate from group", "separate from the others",
        "separate the speaker", "separate this speaker",
        "split from the group", "split off", "split this speaker off",
        "ungroup", "ungroup the speakers", "ungroup this speaker",
        "unpair", "unpair this speaker", "unsync", "unsync this", "unlink",
        "play alone", "play by yourself", "play solo",
        "play just here", "play only here",
        "stop grouping", "stop syncing", "stop sharing",
        "go solo", "go independent", "go alone",
        "remove from group", "remove me from the group",
        "remove this from the group", "remove this speaker",
        "take this speaker out of the group",
    ]
    en_polite = [f"{p} leave the group" for p in EN_POLITE] + \
                [f"{p} disconnect" for p in EN_POLITE] + \
                [f"{p} ungroup" for p in EN_POLITE] + \
                [f"{p} separate this speaker" for p in EN_POLITE]

    da_core = [
        "forlad gruppen", "forlad", "forlad højttalerne",
        "forlad de andre", "forlad klyngen",
        "frakobl", "frakobl gruppen", "frakobl fra gruppen",
        "frakobl højttaleren", "frakobl denne højttaler",
        "afbryd forbindelsen", "afbryd fra gruppen",
        "afbryd forbindelsen til gruppen",
        "adskil", "adskil fra gruppen", "adskil dig",
        "adskil denne højttaler", "adskil højttaleren",
        "del fra gruppen", "split fra gruppen", "split højttaleren",
        "ophæv gruppen", "ophæv grupperingen",
        "fjern gruppering", "fjern gruppe",
        "afsynkroniser", "afsynkroniser højttaleren", "afkobl",
        "spil alene", "spil for dig selv", "spil solo",
        "spil kun her", "spil bare her",
        "stop gruppering", "stop synkronisering", "stop deling",
        "gå solo", "gå alene",
        "fjern fra gruppen", "fjern mig fra gruppen",
        "fjern denne højttaler fra gruppen",
        "tag højttaleren ud af gruppen",
    ]
    da_polite = [f"{p} forlade gruppen" for p in DA_POLITE] + \
                [f"{p} frakoble" for p in DA_POLITE] + \
                [f"{p} ophæve grupperingen" for p in DA_POLITE] + \
                [f"{p} adskille højttaleren" for p in DA_POLITE]

    en = en_core + en_polite
    da = da_core + da_polite
    return [(t, "en") for t in dedupe_preserve(en)] + \
           [(t, "da") for t in dedupe_preserve(da)]


def gen_confirm():
    en = [
        "yes", "yeah", "yep", "yup", "ya", "yes please", "yeah sure",
        "yes thanks", "yeah okay", "yes do it", "yeah do it",
        "sure", "sure thing", "sure why not", "absolutely",
        "absolutely yes", "definitely", "definitely yes",
        "of course", "of course yes",
        "okay", "ok", "okay sure", "ok sure", "okay yes",
        "alright", "all right", "alright then", "all right then",
        "fine", "fine by me", "fine yes",
        "go ahead", "go for it", "do it", "yes do it", "please do",
        "please proceed", "proceed",
        "confirm", "confirmed", "i confirm",
        "correct", "that's right", "that is right",
        "that's correct", "that is correct",
        "right", "exactly", "exactly right", "indeed",
        "affirmative", "agreed", "agreed yes",
        "sounds good", "sounds right", "sounds great",
        "go for it", "let's do it", "yes let's", "let's go",
        "make it so", "do that", "yes please do",
        "perfect", "great", "good",
    ]
    da = [
        "ja", "jo", "jeps", "jow", "ja tak", "ja gerne",
        "ja sikkert", "ja det er fint",
        "selvfølgelig", "naturligvis", "absolut", "bestemt",
        "klart", "klart ja", "klart det",
        "fint", "fint nok", "fint ja", "okay", "ok",
        "okay tak", "ok tak", "i orden", "i orden ja",
        "gør det", "ja gør det", "gør det bare",
        "værsgo", "værsgod", "kør på", "kør bare på",
        "bekræft", "bekræftet", "jeg bekræfter",
        "korrekt", "rigtigt", "helt rigtigt",
        "det er rigtigt", "det stemmer", "det passer",
        "præcis", "nemlig", "netop", "lige præcis",
        "enig", "helt enig",
        "lyder godt", "lyder rigtigt", "lyder fint",
        "kom i gang", "lad os gøre det", "ja lad os",
        "gør det sådan", "ja det er fint",
        "perfekt", "skønt", "godt",
    ]
    return [(t, "en") for t in dedupe_preserve(en)] + \
           [(t, "da") for t in dedupe_preserve(da)]


def gen_cancel():
    en = [
        "no", "nope", "nah", "naw", "no thanks", "no thank you",
        "no please don't", "no don't",
        "cancel", "cancel that", "cancel it", "cancel please",
        "cancel the action", "never mind", "nevermind",
        "never mind that", "forget it", "forget that", "forget about it",
        "skip it", "skip that", "skip the action",
        "stop that", "stop right there", "don't", "don't do it", "do not",
        "don't do that", "do not do that",
        "abort", "abort it", "abort that", "abort the action",
        "wait no", "actually no", "actually never mind",
        "on second thought no", "scratch that",
        "i changed my mind", "changed my mind",
        "not now", "not anymore", "not this time",
        "negative", "wrong", "incorrect", "that's wrong",
        "that's not right", "no that's wrong",
        "back out", "back out of that", "let's not",
    ]
    da = [
        "nej", "nej tak", "nix", "næ", "nej det vil jeg ikke",
        "nej ikke nu", "nej lad være",
        "annuller", "annuller det", "annuller venligst",
        "afbryd", "afbryd det", "afbryd handlingen",
        "glem det", "glem alt om det", "glem den ting",
        "drop det", "drop den ide",
        "fortryd", "fortryd det", "fortryd venligst",
        "stop det der", "stop den handling",
        "gør det ikke", "lad være", "lad være med det",
        "ikke gør det", "ikke gør det der",
        "afbryd nu", "afbryd alt",
        "vent nej", "faktisk nej", "faktisk glem det",
        "jeg har skiftet mening", "skift mening",
        "ikke nu", "ikke alligevel", "ikke denne gang",
        "det er forkert", "negativ", "forkert",
        "det er ikke rigtigt", "nej det er forkert",
        "træd tilbage", "træk tilbage", "lad os ikke",
    ]
    return [(t, "en") for t in dedupe_preserve(en)] + \
           [(t, "da") for t in dedupe_preserve(da)]


def gen_play_named():
    """Play a specific favorite by name. We expand across many favorites
    and many phrasings to teach the classifier that 'play X' is the pattern,
    regardless of what X is."""
    en_verbs = ["play", "put on", "start", "i want to hear", "let's hear",
                "give me", "fire up"]
    en_templates = (
        [f"{v} {{name}}" for v in en_verbs] +
        [f"{v} the {{name}}" for v in en_verbs] +
        [f"{p} play {{name}}" for p in EN_POLITE] +
        [f"{p} put on {{name}}" for p in EN_POLITE] +
        [f"play {{name}} for me", f"start {{name}}", f"i'd like to hear {{name}}"]
    )

    da_verbs = ["spil", "afspil", "sæt", "start", "jeg vil høre"]
    da_templates = (
        [f"{v} {{name}}" for v in da_verbs] +
        [f"{v} {{name}} på" for v in ["sæt"]] +
        [f"{p} spille {{name}}" for p in DA_POLITE] +
        [f"{p} afspille {{name}}" for p in DA_POLITE] +
        [f"{p} sætte {{name}} på" for p in DA_POLITE] +
        [f"spil {{name}} for mig", f"afspil {{name}} tak"]
    )

    en = expand(en_templates, {"name": FAVORITE_NAMES})
    da = expand(da_templates, {"name": FAVORITE_NAMES})
    return [(t, "en") for t in dedupe_preserve(en)] + \
           [(t, "da") for t in dedupe_preserve(da)]


def gen_play_favorite_by_number():
    en_templates = [
        "play favorite {n}", "play favourite {n}",
        "play favorite number {n}", "play favourite number {n}",
        "play number {n}", "play preset {n}",
        "favorite {n}", "favourite {n}", "preset {n}",
        "play my {n} favorite", "play my favorite {n}",
        "start favorite {n}", "put on favorite {n}",
    ]
    en_polite = [f"{p} play favorite {{n}}" for p in EN_POLITE] + \
                [f"{p} play number {{n}}" for p in EN_POLITE]

    da_templates = [
        "spil favorit {n}", "afspil favorit {n}",
        "spil favorit nummer {n}", "afspil favorit nummer {n}",
        "favorit {n}", "favorit nummer {n}",
        "spil nummer {n}", "afspil nummer {n}",
        "start favorit {n}", "sæt favorit {n} på",
        "spil min favorit {n}", "spil favorit {n} tak",
    ]
    da_polite = [f"{p} spille favorit {{n}}" for p in DA_POLITE] + \
                [f"{p} afspille favorit nummer {{n}}" for p in DA_POLITE]

    # Generate with both digit and word forms
    en_examples = []
    for tmpl in en_templates + en_polite:
        for n in FAV_NUMS:
            en_examples.append(tmpl.format(n=n))
            en_examples.append(tmpl.format(n=FAV_NUM_WORDS_EN[n]))

    da_examples = []
    for tmpl in da_templates + da_polite:
        for n in FAV_NUMS:
            da_examples.append(tmpl.format(n=n))
            da_examples.append(tmpl.format(n=FAV_NUM_WORDS_DA[n]))

    return [(t, "en") for t in dedupe_preserve(en_examples)] + \
           [(t, "da") for t in dedupe_preserve(da_examples)]



def gen_set_volume():
    """Absolute volume — both digit and word forms in both languages."""
    en_templates = [
        "set volume to {v}", "set the volume to {v}",
        "volume {v}", "volume to {v}", "volume at {v}",
        "set it to {v}", "set the level to {v}",
        "make the volume {v}", "change volume to {v}",
        "put the volume at {v}", "i want volume {v}",
        "volume level {v}", "level {v}",
    ]
    en_polite = [f"{p} set volume to {{v}}" for p in EN_POLITE] + \
                [f"{p} change the volume to {{v}}" for p in EN_POLITE] + \
                [f"{p} put the volume at {{v}}" for p in EN_POLITE]

    da_templates = [
        "sæt lydstyrken til {v}", "sæt volumen til {v}",
        "lydstyrke {v}", "lydstyrke til {v}", "lydstyrken på {v}",
        "indstil lydstyrken til {v}", "indstil volumen til {v}",
        "skift lydstyrken til {v}", "skift til lydstyrke {v}",
        "sæt det til {v}", "jeg vil have lydstyrke {v}",
        "lydniveau {v}", "niveau {v}",
    ]
    da_polite = [f"{p} sætte lydstyrken til {{v}}" for p in DA_POLITE] + \
                [f"{p} indstille lydstyrken til {{v}}" for p in DA_POLITE] + \
                [f"{p} ændre lydstyrken til {{v}}" for p in DA_POLITE]

    en_examples = []
    for tmpl in en_templates + en_polite:
        for v in VOL_DIGITS:
            en_examples.append(tmpl.format(v=v))
        for v_digit, v_word in VOL_WORDS_EN.items():
            en_examples.append(tmpl.format(v=v_word))

    da_examples = []
    for tmpl in da_templates + da_polite:
        for v in VOL_DIGITS:
            da_examples.append(tmpl.format(v=v))
        for v_digit, v_word in VOL_WORDS_DA.items():
            da_examples.append(tmpl.format(v=v_word))

    return [(t, "en") for t in dedupe_preserve(en_examples)] + \
           [(t, "da") for t in dedupe_preserve(da_examples)]


def gen_volume_up():
    en_no_amount = [
        "volume up", "louder", "turn it up", "turn up the volume",
        "turn the volume up", "make it louder", "raise the volume",
        "raise it", "increase the volume", "increase volume",
        "crank it up", "pump it up", "bump the volume", "bump it up",
        "more volume", "more sound", "a bit louder",
    ]
    en_with_amount_d = [f"volume up {n}" for n in VOL_STEPS] + \
                       [f"louder by {n}" for n in VOL_STEPS] + \
                       [f"turn it up by {n}" for n in VOL_STEPS] + \
                       [f"raise the volume by {n}" for n in VOL_STEPS] + \
                       [f"increase volume by {n}" for n in VOL_STEPS]
    en_with_amount_w = [f"volume up {VOL_STEPS_EN[n]}" for n in VOL_STEPS] + \
                       [f"louder by {VOL_STEPS_EN[n]}" for n in VOL_STEPS] + \
                       [f"turn it up by {VOL_STEPS_EN[n]}" for n in VOL_STEPS]
    en_polite = [f"{p} turn it up" for p in EN_POLITE] + \
                [f"{p} make it louder" for p in EN_POLITE] + \
                [f"{p} increase the volume" for p in EN_POLITE]

    da_no_amount = [
        "skru op", "højere", "lidt højere", "skru lidt op",
        "skru op for lyden", "skru op for musikken",
        "gør det højere", "gør det lidt højere", "gør lyden højere",
        "mere lyd", "mere volumen", "mere lydstyrke",
        "hæv lydstyrken", "hæv volumen", "skru op for det",
    ]
    da_with_amount_d = [f"skru op med {n}" for n in VOL_STEPS] + \
                       [f"højere med {n}" for n in VOL_STEPS] + \
                       [f"hæv lydstyrken med {n}" for n in VOL_STEPS] + \
                       [f"skru op {n}" for n in VOL_STEPS]
    da_with_amount_w = [f"skru op med {VOL_STEPS_DA[n]}" for n in VOL_STEPS] + \
                       [f"højere med {VOL_STEPS_DA[n]}" for n in VOL_STEPS] + \
                       [f"hæv lydstyrken med {VOL_STEPS_DA[n]}" for n in VOL_STEPS]
    da_polite = [f"{p} skrue op" for p in DA_POLITE] + \
                [f"{p} gøre det højere" for p in DA_POLITE] + \
                [f"{p} hæve lydstyrken" for p in DA_POLITE] + \
                [f"{p} skrue op for lyden" for p in DA_POLITE]

    en = en_no_amount + en_with_amount_d + en_with_amount_w + en_polite
    da = da_no_amount + da_with_amount_d + da_with_amount_w + da_polite
    return [(t, "en") for t in dedupe_preserve(en)] + \
           [(t, "da") for t in dedupe_preserve(da)]


def gen_volume_down():
    en_no_amount = [
        "volume down", "lower", "quieter", "softer",
        "turn it down", "turn down the volume", "turn the volume down",
        "make it quieter", "make it softer", "lower the volume",
        "lower it", "decrease the volume", "decrease volume",
        "tone it down", "less volume", "a bit quieter", "a bit lower",
    ]
    en_with_amount_d = [f"volume down {n}" for n in VOL_STEPS] + \
                       [f"quieter by {n}" for n in VOL_STEPS] + \
                       [f"turn it down by {n}" for n in VOL_STEPS] + \
                       [f"lower the volume by {n}" for n in VOL_STEPS] + \
                       [f"decrease volume by {n}" for n in VOL_STEPS]
    en_with_amount_w = [f"volume down {VOL_STEPS_EN[n]}" for n in VOL_STEPS] + \
                       [f"quieter by {VOL_STEPS_EN[n]}" for n in VOL_STEPS] + \
                       [f"turn it down by {VOL_STEPS_EN[n]}" for n in VOL_STEPS]
    en_polite = [f"{p} turn it down" for p in EN_POLITE] + \
                [f"{p} make it quieter" for p in EN_POLITE] + \
                [f"{p} lower the volume" for p in EN_POLITE]

    da_no_amount = [
        "skru ned", "lavere", "lidt lavere", "skru lidt ned",
        "skru ned for lyden", "skru ned for musikken",
        "gør det lavere", "gør det lidt lavere", "gør lyden lavere",
        "mindre lyd", "mindre volumen", "mindre lydstyrke",
        "sænk lydstyrken", "sænk volumen", "skru ned for det",
        "dæmp lidt", "lidt mere stille",
    ]
    da_with_amount_d = [f"skru ned med {n}" for n in VOL_STEPS] + \
                       [f"lavere med {n}" for n in VOL_STEPS] + \
                       [f"sænk lydstyrken med {n}" for n in VOL_STEPS] + \
                       [f"skru ned {n}" for n in VOL_STEPS]
    da_with_amount_w = [f"skru ned med {VOL_STEPS_DA[n]}" for n in VOL_STEPS] + \
                       [f"lavere med {VOL_STEPS_DA[n]}" for n in VOL_STEPS] + \
                       [f"sænk lydstyrken med {VOL_STEPS_DA[n]}" for n in VOL_STEPS]
    da_polite = [f"{p} skrue ned" for p in DA_POLITE] + \
                [f"{p} gøre det lavere" for p in DA_POLITE] + \
                [f"{p} sænke lydstyrken" for p in DA_POLITE] + \
                [f"{p} skrue ned for lyden" for p in DA_POLITE]

    en = en_no_amount + en_with_amount_d + en_with_amount_w + en_polite
    da = da_no_amount + da_with_amount_d + da_with_amount_w + da_polite
    return [(t, "en") for t in dedupe_preserve(en)] + \
           [(t, "da") for t in dedupe_preserve(da)]






def gen_join_speaker():
    en_templates = [
        "join {room}", "join the speaker", "join the speakers",
        "join with {room}", "connect to {room}", "connect with {room}",
        "group with {room}", "sync with {room}", "sync to {room}",
        "pair with {room}", "link to {room}", "link with {room}",
        "play together with {room}", "play with {room}",
        "merge with {room}", "join the group with {room}",
        "add me to {room}", "add {room} to the group",
    ]
    en_no_room = [
        "join the speaker", "join the speakers", "join the group",
        "connect to the group", "join the others",
        "group the speakers", "sync the speakers", "play together",
        "play in sync", "play everywhere", "play in all rooms",
    ]
    en_polite = [f"{p} join {{room}}" for p in EN_POLITE] + \
                [f"{p} group with {{room}}" for p in EN_POLITE]

    da_templates = [
        "tilslut {room}", "tilslut til {room}", "forbind med {room}",
        "forbind til {room}", "tilføj {room}", "grupper med {room}",
        "synkroniser med {room}", "spil sammen med {room}",
        "spil samtidig med {room}", "join {room}",
        "kobl sammen med {room}", "tilknyt {room}",
    ]
    da_no_room = [
        "tilslut højttaleren", "tilslut højttalerne", "tilslut gruppen",
        "join gruppen", "spil sammen", "spil overalt",
        "spil i alle rum", "synkroniser højttalerne",
        "grupper højttalerne", "kobl højttalerne sammen",
    ]
    da_polite = [f"{p} tilslutte {{room}}" for p in DA_POLITE] + \
                [f"{p} forbinde med {{room}}" for p in DA_POLITE] + \
                [f"{p} gruppere med {{room}}" for p in DA_POLITE]

    en = expand(en_templates + en_polite, {"room": ROOM_NAMES_EN}) + en_no_room
    da = expand(da_templates + da_polite, {"room": ROOM_NAMES_DA}) + da_no_room
    return [(t, "en") for t in dedupe_preserve(en)] + \
           [(t, "da") for t in dedupe_preserve(da)]



def gen_unknown():
    """Out-of-domain utterances. These should look like things a user
    might accidentally say to the device but that don't map to any
    speaker control intent."""
    en = [
        # Weather and time
        "what's the weather today", "what's the weather like",
        "is it going to rain tomorrow", "what's the temperature outside",
        "will it snow this weekend", "how cold is it",
        "what time is it", "what's today's date", "what day is it",
        "when is sunset", "when does the sun rise",
        # Personal queries
        "tell me a joke", "tell me a story", "sing a song",
        "say something funny", "make me laugh",
        "how are you", "how old are you", "what's your name",
        "who made you", "who are you", "what can you do",
        "are you a robot", "do you sleep", "do you have feelings",
        # Help and instruction
        "help me with my homework", "explain quantum physics",
        "what's two plus two", "what's twelve times eight",
        "calculate the tip", "convert ten dollars to euros",
        "how do i bake a cake", "what's a good recipe for pasta",
        "how do you spell necessary", "what's the capital of france",
        # Productivity
        "set a timer for ten minutes", "set an alarm for seven am",
        "remind me to buy milk", "add eggs to my shopping list",
        "what's on my calendar", "schedule a meeting for tomorrow",
        "send a message to john", "call mom", "text my wife",
        "read my latest email", "any new messages",
        # Navigation
        "navigate home", "directions to the airport",
        "find a restaurant nearby", "where's the closest pharmacy",
        "how far is copenhagen", "show me a map of paris",
        # Translation and language
        "translate hello to french", "how do you say thank you in spanish",
        "what does bonjour mean", "translate this to german",
        # News and sports
        "what's the news", "read me the headlines", "any breaking news",
        "what's the score of the game", "who won last night",
        "how did the lakers do", "any sports updates",
        # Games and entertainment
        "play a game", "let's play chess", "roll a dice",
        "flip a coin", "pick a random number", "trivia question",
        "tell me a fun fact", "give me a riddle",
        # Food and shopping
        "make me a sandwich", "order pizza", "where's the nearest grocery",
        "what should i eat for dinner", "find me a coffee shop",
        # Smart home (other devices)
        "turn on the lights", "turn off the heating", "lock the door",
        "set the thermostat to seventy", "open the garage",
        "is the front door locked", "what's my home temperature",
        # Random
        "i love you", "thank you", "goodbye", "good morning",
        "good night", "how was your day", "what should i do today",
    ]
    da = [
        # Weather and time
        "hvad er vejret i dag", "hvordan er vejret",
        "regner det i morgen", "hvad er temperaturen udenfor",
        "kommer der sne i weekenden", "hvor koldt er det",
        "hvad er klokken", "hvad er datoen i dag", "hvilken dag er det",
        "hvornår er det solnedgang", "hvornår står solen op",
        # Personal queries
        "fortæl en vittighed", "fortæl en historie", "syng en sang",
        "sig noget sjovt", "få mig til at grine",
        "hvordan har du det", "hvor gammel er du", "hvad hedder du",
        "hvem har lavet dig", "hvem er du", "hvad kan du",
        "er du en robot", "sover du", "har du følelser",
        # Help and instruction
        "hjælp mig med min lektie", "forklar kvantefysik",
        "hvad er to plus to", "hvad er tolv gange otte",
        "udregn drikkepengene", "konverter ti dollar til kroner",
        "hvordan bager jeg en kage", "har du en god opskrift på pasta",
        "hvordan staves nødvendig", "hvad er hovedstaden i frankrig",
        # Productivity
        "sæt en timer til ti minutter", "sæt en alarm til klokken syv",
        "mind mig om at købe mælk", "tilføj æg til min indkøbsliste",
        "hvad står der i min kalender", "planlæg et møde i morgen",
        "send en besked til peter", "ring til mor", "send en sms til min kone",
        "læs min seneste email op", "har jeg nogen nye beskeder",
        # Navigation
        "naviger hjem", "vis vej til lufthavnen",
        "find en restaurant i nærheden", "hvor er det nærmeste apotek",
        "hvor langt er der til københavn", "vis mig et kort over paris",
        # Translation and language
        "oversæt hej til fransk", "hvordan siger man tak på spansk",
        "hvad betyder bonjour", "oversæt dette til tysk",
        # News and sports
        "hvad er nyhederne", "læs overskrifterne op", "er der breaking news",
        "hvad er stillingen i kampen", "hvem vandt i går",
        "hvordan klarede fck sig", "har du sportsopdateringer",
        # Games and entertainment
        "lad os spille et spil", "spil skak", "kast en terning",
        "kast plat eller krone", "vælg et tilfældigt tal",
        "stil et quizspørgsmål", "fortæl mig en sjov kendsgerning",
        "giv mig en gåde",
        # Food and shopping
        "lav en sandwich til mig", "bestil pizza", "hvor er det nærmeste supermarked",
        "hvad skal jeg spise til aften", "find en kaffebar",
        # Smart home
        "tænd lyset", "sluk varmen", "lås døren",
        "indstil termostaten til toogtyve grader", "åbn garageporten",
        "er hoveddøren låst", "hvad er temperaturen hjemme",
        # Random
        "jeg elsker dig", "tak", "farvel", "godmorgen",
        "godnat", "hvordan var din dag", "hvad skal jeg lave i dag",
        "hvor er mine nøgler", "hvor er min telefon",
    ]
    return [(t, "en") for t in dedupe_preserve(en)] + \
           [(t, "da") for t in dedupe_preserve(da)]


# ---------------------------------------------------------------------------
# Run all generators
# ---------------------------------------------------------------------------

INTENT_GENERATORS = {
    "stop": gen_stop,
    "pause": gen_pause,
    "resume": gen_resume,
    "playDefault": gen_play_default,
    "playNamed": gen_play_named,
    "playFavoriteByNumber": gen_play_favorite_by_number,
    "listFavorites": gen_list_favorites,
    "setVolume": gen_set_volume,
    "volumeUp": gen_volume_up,
    "volumeDown": gen_volume_down,
    "mute": gen_mute,
    "unmute": gen_unmute,
    "confirm": gen_confirm,
    "cancel": gen_cancel,
    "joinSpeaker": gen_join_speaker,
    "leaveSpeaker": gen_leave_speaker,
    "unknown": gen_unknown,
}


def build_clean_corpus():
    """Generate the clean corpus, balanced per intent and per language."""
    rows = []
    stats = {}
    for intent, gen in INTENT_GENERATORS.items():
        examples = gen()  # list of (text, lang)
        en_texts = [t for t, l in examples if l == "en"]
        da_texts = [t for t, l in examples if l == "da"]

        # Multiply low-volume intents using adverb augmentation. We allow
        # this for ALL intents (including unknown) since adverb-padded
        # phrases reflect natural speech and ASR output.
        if len(en_texts) < TARGET_PER_INTENT // 2:
            en_texts = dedupe_preserve(multiply_with_adverbs(en_texts, "en"))
        if len(da_texts) < TARGET_PER_INTENT // 2:
            da_texts = dedupe_preserve(multiply_with_adverbs(da_texts, "da"))

        en = [(t, "en") for t in en_texts]
        da = [(t, "da") for t in da_texts]

        per_lang = TARGET_PER_INTENT // 2
        en_sample = sample_to(per_lang, en)
        da_sample = sample_to(per_lang, da)

        # If one language is short, fill from the other
        deficit_en = per_lang - len(en_sample)
        deficit_da = per_lang - len(da_sample)
        if deficit_en > 0 and len(da) > len(da_sample):
            extra = sample_to(min(deficit_en, len(da) - len(da_sample)),
                              [x for x in da if x not in da_sample])
            da_sample.extend(extra)
        if deficit_da > 0 and len(en) > len(en_sample):
            extra = sample_to(min(deficit_da, len(en) - len(en_sample)),
                              [x for x in en if x not in en_sample])
            en_sample.extend(extra)

        chosen = en_sample + da_sample
        for text, lang in chosen:
            rows.append({"text": text, "label": intent, "lang": lang})

        stats[intent] = {
            "total_generated": len(en) + len(da),
            "en_used": len(en_sample),
            "da_used": len(da_sample),
            "final": len(chosen),
        }
    return rows, stats


# ---------------------------------------------------------------------------
# Noise variant generation
# ---------------------------------------------------------------------------

# Filler words spoken naturally during commands
FILLERS_EN = ["uh", "um", "er", "uhh", "hmm", "like", "you know"]
FILLERS_DA = ["øh", "øhh", "altså", "hmm", "ehm", "ligesom"]

# Common ASR mistranscriptions — phoneme-level confusions we've seen for
# the speaker name "Beosound" and other audio terms
MISTRANSCRIPTION_MAP = {
    # English mistranscriptions
    "play": ["plate", "plays"],
    "pause": ["paws", "pose", "pause it"],
    "resume": ["assume", "presume"],
    "volume": ["valium", "column"],
    "louder": ["loader", "lauder"],
    "quieter": ["quitter", "quieted"],
    "mute": ["moot", "mood"],
    "favorite": ["favored", "favorited"],
    # Danish mistranscriptions
    "spil": ["bil", "fil"],
    "stop": ["top", "shop"],
    "lydstyrke": ["lystyrke", "lydstyrken"],
    "favorit": ["favoret", "faborit"],
    "højere": ["højde", "højre"],
    "lavere": ["laveret", "låvere"],
}


def add_filler(text, lang):
    """Insert one filler word at the start or middle."""
    fillers = FILLERS_EN if lang == "en" else FILLERS_DA
    filler = random.choice(fillers)
    tokens = text.split()
    if random.random() < 0.5 or len(tokens) == 1:
        return f"{filler} {text}"
    pos = random.randint(1, len(tokens) - 1)
    tokens.insert(pos, filler)
    return " ".join(tokens)


def drop_article(text, lang):
    """Drop a common article — simulates clipped speech."""
    if lang == "en":
        articles = [" the ", " a ", " an ", " my "]
    else:
        articles = [" den ", " det ", " en ", " et ", " min "]
    for art in articles:
        if art in f" {text} ":
            return text.replace(art, " ", 1).strip()
    return text


def add_repetition(text, lang):
    """Repeat the first word — simulates hesitation."""
    tokens = text.split()
    if not tokens:
        return text
    return f"{tokens[0]} {text}"


def add_mistranscription(text, lang):
    """Replace a word with a known mistranscription."""
    tokens = text.split()
    for i, tok in enumerate(tokens):
        key = tok.lower().rstrip(".,!?")
        if key in MISTRANSCRIPTION_MAP:
            tokens[i] = random.choice(MISTRANSCRIPTION_MAP[key])
            return " ".join(tokens)
    return text  # No replaceable word; return unchanged


def add_partial_word(text, lang):
    """Truncate one word to simulate ASR cutoff."""
    tokens = text.split()
    if len(tokens) < 2:
        return text
    idx = random.randint(0, len(tokens) - 1)
    word = tokens[idx]
    if len(word) > 4:
        tokens[idx] = word[:len(word) - 2] + "-"
    return " ".join(tokens)


NOISE_TRANSFORMS = [
    ("filler", add_filler),
    ("dropped_article", drop_article),
    ("repetition", add_repetition),
    ("mistranscription", add_mistranscription),
    ("partial_word", add_partial_word),
]


def build_noise_corpus(clean_rows):
    """Take a fraction of clean examples per intent and apply noise transforms.

    Each noise example carries the same label as its source — the model
    should learn that filler words and dropped articles don't change intent.
    """
    target_per_intent = int(TARGET_PER_INTENT * NOISE_FRACTION)
    by_intent = {}
    for row in clean_rows:
        by_intent.setdefault(row["label"], []).append(row)

    noise_rows = []
    for intent, rows in by_intent.items():
        # Skip noise for confirm/cancel — they're so short noise often makes
        # them ambiguous with each other or with unknown.
        if intent in ("confirm", "cancel"):
            continue

        sample = sample_to(target_per_intent, rows)
        for src in sample:
            noise_name, transform = random.choice(NOISE_TRANSFORMS)
            noisy_text = transform(src["text"], src["lang"])
            noisy_text = normalise(noisy_text)
            if noisy_text and noisy_text.lower() != src["text"].lower():
                noise_rows.append({
                    "text": noisy_text,
                    "label": intent,
                    "lang": src["lang"],
                    "noise": noise_name,
                    "source": src["text"],
                })
    return noise_rows


# ---------------------------------------------------------------------------
# Write outputs
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Slot extraction — for intents that carry numeric or named slots
# ---------------------------------------------------------------------------

WORD_TO_INT_EN = {
    "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
    "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    "fifteen": 15, "twenty": 20, "twenty-five": 25, "thirty": 30,
    "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
    "seventy-five": 75, "eighty": 80, "ninety": 90, "one hundred": 100,
}
WORD_TO_INT_DA = {
    "nul": 0, "et": 1, "to": 2, "tre": 3, "fire": 4, "fem": 5,
    "seks": 6, "syv": 7, "otte": 8, "ni": 9, "ti": 10,
    "femten": 15, "tyve": 20, "femogtyve": 25, "tredive": 30,
    "fyrre": 40, "halvtreds": 50, "tres": 60, "halvfjerds": 70,
    "femoghalvfjerds": 75, "firs": 80, "halvfems": 90, "hundrede": 100,
}


def extract_slots(text, label, lang):
    """Return slot values for the given intent. Empty dict if intent has no slots."""
    slots = {}
    word_map = WORD_TO_INT_EN if lang == "en" else WORD_TO_INT_DA

    if label == "setVolume":
        m = re.search(r"\b(\d{1,3})\b", text)
        if m:
            slots["volumeValue"] = int(m.group(1))
        else:
            for word, val in sorted(word_map.items(), key=lambda x: -len(x[0])):
                if re.search(rf"\b{re.escape(word)}\b", text, re.IGNORECASE):
                    slots["volumeValue"] = val
                    break

    elif label in ("volumeUp", "volumeDown"):
        m = re.search(r"\b(\d{1,3})\b", text)
        if m:
            slots["volumeDelta"] = int(m.group(1))
        else:
            for word, val in sorted(word_map.items(), key=lambda x: -len(x[0])):
                if re.search(rf"\b{re.escape(word)}\b", text, re.IGNORECASE):
                    slots["volumeDelta"] = val
                    break

    elif label == "playFavoriteByNumber":
        m = re.search(r"\b(\d{1,2})\b", text)
        if m:
            slots["favoriteNumber"] = int(m.group(1))
        else:
            for word, val in sorted(word_map.items(), key=lambda x: -len(x[0])):
                if re.search(rf"\b{re.escape(word)}\b", text, re.IGNORECASE):
                    slots["favoriteNumber"] = val
                    break

    elif label == "playNamed":
        verbs = ["i'd like to hear", "i want to hear", "let's hear", "fire up",
                 "give me", "put on", "play", "start",
                 "jeg vil høre", "afspil", "spil", "sæt", "start"]
        for verb in verbs:
            pattern = rf"\b{re.escape(verb)}\b\s+(?:the\s+)?(.+?)(?:\s+(?:for me|tak|på))?$"
            m = re.search(pattern, text, re.IGNORECASE)
            if m:
                slots["favoriteName"] = m.group(1).strip()
                break

    return slots


def collapse_collisions(rows):
    """Handle two collision types:

    1. Same text + same label across languages (e.g. 'mute' is valid in both
       EN and DA): collapse to one row with lang='both'.
    2. Same text + different labels (e.g. 'stop' as both stop and cancel):
       keep only the first; the dominant label wins. The classifier handles
       genuinely ambiguous tokens better with a single label than with both.
    """
    by_text_label = {}
    for r in rows:
        key = (r["text"].lower(), r["label"])
        by_text_label.setdefault(key, []).append(r)

    collapsed = []
    seen_text = {}
    for key, group in by_text_label.items():
        text_lower, label = key
        langs = sorted({r["lang"] for r in group})
        merged_lang = "both" if len(langs) > 1 else langs[0]
        rep = dict(group[0])
        rep["lang"] = merged_lang
        if text_lower in seen_text and seen_text[text_lower] != label:
            continue
        seen_text[text_lower] = label
        collapsed.append(rep)
    return collapsed


def main():
    print("Generating clean corpus...")
    clean_rows, stats = build_clean_corpus()

    print(f"Before collision handling: {len(clean_rows)} rows")
    clean_rows = collapse_collisions(clean_rows)
    print(f"After collision handling:  {len(clean_rows)} rows")

    # Add slot annotations
    for r in clean_rows:
        slot_lang = r["lang"] if r["lang"] != "both" else "en"
        slots = extract_slots(r["text"], r["label"], slot_lang)
        if r["lang"] == "both" and not slots:
            slots = extract_slots(r["text"], r["label"], "da")
        r["volumeValue"] = slots.get("volumeValue", "")
        r["volumeDelta"] = slots.get("volumeDelta", "")
        r["favoriteNumber"] = slots.get("favoriteNumber", "")
        r["favoriteName"] = slots.get("favoriteName", "")

    random.shuffle(clean_rows)

    clean_path = OUT_DIR / "corpus-clean.csv"
    with open(clean_path, "w", newline="", encoding="utf-8") as f:
        fields = ["text", "label", "lang", "volumeValue", "volumeDelta",
                  "favoriteNumber", "favoriteName"]
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(clean_rows)

    print(f"\nClean corpus: {clean_path}")
    print(f"Total rows: {len(clean_rows)}")
    print("\nPer-intent breakdown:")
    print(f"  {'intent':<25} {'final':>6} {'en':>4} {'da':>4} {'(pool size)':>12}")
    for intent, s in stats.items():
        print(f"  {intent:<25} {s['final']:>6} {s['en_used']:>4} {s['da_used']:>4} {s['total_generated']:>12}")

    print("\nGenerating noise corpus...")
    noise_rows = build_noise_corpus(clean_rows)
    random.shuffle(noise_rows)

    noise_path = OUT_DIR / "corpus-noise.csv"
    with open(noise_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["text", "label", "lang", "noise", "source"])
        writer.writeheader()
        writer.writerows(noise_rows)

    print(f"Noise corpus: {noise_path}")
    print(f"Total noise rows: {len(noise_rows)}")

    # Noise breakdown
    from collections import Counter
    noise_counter = Counter((r["label"], r["noise"]) for r in noise_rows)
    print("\nNoise breakdown (intent x transform):")
    intents_in_noise = sorted({k[0] for k in noise_counter})
    transforms = [t for t, _ in NOISE_TRANSFORMS]
    print(f"  {'intent':<25}" + "".join(f"{t:>17}" for t in transforms))
    for intent in intents_in_noise:
        row = f"  {intent:<25}"
        for t in transforms:
            row += f"{noise_counter.get((intent, t), 0):>17}"
        print(row)


if __name__ == "__main__":
    main()
