"""Builds data/words/ from the downloaded sources and the reviewed exclusion lists.

Usage:
    build_words.py <sources> candidates <output dir>   writes ranked answer candidates for review
    build_words.py <sources> build                     writes the game data
"""
import json
import os
import random
import sys
import unicodedata

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUTPUT = os.path.join(ROOT, "data", "words")
LENGTHS = (5, 6, 7)
LANGUAGES = ("pt", "en", "es")
KEPT_LETTERS = {"pt": "", "en": "", "es": "ñ"}
CANDIDATES_PER_LIST = 1200
ANSWERS_PER_LIST = 750
MINIMUM_ANSWERS = 365


def plain(word, lang):
    letters = []
    for char in word:
        if char in KEPT_LETTERS[lang]:
            letters.append(char)
        else:
            letters.extend(c for c in unicodedata.normalize("NFD", char) if not unicodedata.combining(c))
    return "".join(letters)


def is_playable(key, lang):
    allowed = set("abcdefghijklmnopqrstuvwxyz" + KEPT_LETTERS[lang])
    return all(char in allowed for char in key)


def read_lines(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return [line.strip() for line in f if line.strip()]


def read_stems(sources, lang):
    """Returns the lowercase stems and, lowercased, the ones the dictionary only has capitalized.

    Both keep their accents, so a place like Choró does not remove the word choro.
    """
    lower, capitalized = set(), set()
    for line in read_lines(os.path.join(sources, lang + "_stems.dic"))[1:]:
        stem = line.split("/")[0].split("\t")[0].strip()
        if not stem:
            continue
        if stem == stem.lower():
            lower.add(stem)
        elif stem[0].isupper():
            capitalized.add(stem.lower())
    return lower, capitalized - lower


PT_PLURAL_SUFFIXES = (("ões", "ão"), ("ães", "ão"), ("ãos", "ão"), ("ns", "m"), ("eis", "il"), ("is", "il"),
                      ("is", "l"), ("es", ""), ("s", ""))
# These plurals can move the accent (papéis/papel, meses/mês), so their singular is compared without accents.
# Doing the same for -s would take pires for the plural of piré.
PT_ACCENT_SHIFT_SUFFIXES = ("is", "es")


def is_pt_plural(word, lexicon, lexicon_keys):
    for suffix, singular in PT_PLURAL_SUFFIXES:
        if word.endswith(suffix):
            stem = word[: -len(suffix)] + singular
            if stem in lexicon or (suffix.endswith(PT_ACCENT_SHIFT_SUFFIXES) and plain(stem, "pt") in lexicon_keys):
                return True
    return False


def pt_base_keys(sources, lexicon):
    # The Hunspell stems miss common nouns that the dictionary derives from verbs or masculine forms
    # (escola, livro, música), so the lexicon is the base. Hunspell only removes the words it knows
    # just capitalized, which catches part of the proper names and also a few common words.
    lexicon_keys = {plain(w, "pt") for w in lexicon}
    _, names = read_stems(sources, "pt")
    base_keys = set()
    for word in lexicon:
        key = plain(word, "pt")
        if len(key) in LENGTHS and word not in names and not is_pt_plural(word, lexicon, lexicon_keys):
            base_keys.add(key)
    return base_keys


def load_language(sources, lang):
    blocked = {plain(w.lower(), lang) for w in read_lines(os.path.join(sources, lang + "_blocklist"))}
    if lang == "pt":
        lexicon = set(read_lines(os.path.join(sources, "pt_lexicon")))
        conjugations = read_lines(os.path.join(sources, "pt_conjugations"))
        blocked |= {plain(w.lower(), lang) for w in read_lines(os.path.join(sources, "pt_negative"))}
        ranked = [line.split(",")[0] for line in read_lines(os.path.join(sources, "pt_icf"))[:60000]]
        base_keys = pt_base_keys(sources, lexicon)
        guesses = lexicon | set(conjugations)
    else:
        ranked = [line.split()[0] for line in read_lines(os.path.join(sources, lang + "_frequency"))]
        stems, _ = read_stems(sources, lang)
        base_keys = {plain(w, lang) for w in stems}
        if lang == "es":
            with open(os.path.join(sources, "es_words.json"), encoding="utf-8") as f:
                guesses = set(json.load(f))
        else:
            guesses = set(read_lines(os.path.join(sources, "en_words")))
    guess_keys = {plain(w, lang) for w in guesses}
    return ranked, base_keys, guess_keys, blocked


def ranked_answers(lang, length, ranked, base_keys, blocked, excluded):
    answers, seen = [], set()
    for word in ranked:
        key = plain(word, lang)
        if len(key) != length or key in seen or not is_playable(key, lang):
            continue
        if key in blocked or key not in base_keys or word in excluded:
            continue
        seen.add(key)
        answers.append(word)
    return answers


def read_excluded(lang):
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "exclude_%s.txt" % lang)
    return set(read_lines(path)) if os.path.exists(path) else set()


def write_lines(path, lines):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def candidates(sources, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for lang in LANGUAGES:
        ranked, base_keys, _, blocked = load_language(sources, lang)
        for length in LENGTHS:
            words = ranked_answers(lang, length, ranked, base_keys, blocked, set())[:CANDIDATES_PER_LIST]
            write_lines(os.path.join(out_dir, "%s_%d.txt" % (lang, length)), words)
            print("%s %d: %d candidatas" % (lang, length, len(words)))


def stable_answers(published, reviewed, excluded, blocked, lang, seed):
    """Keeps the published order, so the word of the day does not change for anyone.

    A published word that is now excluded or blocked gives its place to a new word.
    New words only go to the end of the list, up to ANSWERS_PER_LIST.
    """
    published_keys = {plain(w, lang) for w in published}
    removed = [w in excluded or plain(w, lang) in blocked for w in published]
    fresh = [w for w in reviewed if w not in excluded and plain(w, lang) not in published_keys]
    slots = sum(removed) + max(0, ANSWERS_PER_LIST - len(published))
    new = fresh[:slots]
    random.Random(seed).shuffle(new)
    answers, shifted = [], False
    for word, is_removed in zip(published, removed):
        if not is_removed:
            answers.append(word)
        elif new:
            answers.append(new.pop(0))
        else:
            shifted = True
    answers.extend(new[:max(0, ANSWERS_PER_LIST - len(answers))])
    return answers, shifted


def build(sources):
    failed = False
    for lang in LANGUAGES:
        ranked, base_keys, guess_keys, blocked = load_language(sources, lang)
        excluded = read_excluded(lang)
        lang_dir = os.path.join(OUTPUT, lang)
        os.makedirs(lang_dir, exist_ok=True)
        for length in LENGTHS:
            answers_path = os.path.join(lang_dir, "answers_%d.txt" % length)
            published = read_lines(answers_path) if os.path.exists(answers_path) else []
            # Only the candidates that went through review can become answers.
            reviewed = ranked_answers(lang, length, ranked, base_keys, blocked, set())[:CANDIDATES_PER_LIST]
            words, shifted = stable_answers(published, reviewed, excluded, blocked, lang, "%s-%d" % (lang, length))
            if shifted:
                print("  %s %d: palavras removidas sem substituta, a palavra do dia muda a partir delas" % (lang, length))
            guesses = {k for k in guess_keys if len(k) == length and is_playable(k, lang)}
            guesses |= {plain(w, lang) for w in words}
            write_lines(answers_path, words)
            write_lines(os.path.join(lang_dir, "guesses_%d.txt" % length), sorted(guesses))
            print("%s %d: %d respostas, %d tentativas válidas" % (lang, length, len(words), len(guesses)))
            if len(words) < MINIMUM_ANSWERS:
                print("  poucas respostas: mínimo de %d" % MINIMUM_ANSWERS)
                failed = True
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    if sys.argv[2] == "candidates":
        candidates(sys.argv[1], sys.argv[3])
    else:
        build(sys.argv[1])
