"""Builds data/words/ from the downloaded sources and the reviewed approved and excluded lists.

Usage:
    build_words.py <sources> candidates <output dir>   writes ranked answer candidates
    build_words.py <sources> pending <output dir>      writes the candidates not reviewed yet
    build_words.py <sources> build                     writes the game data
"""
import datetime
import json
import os
import random
import subprocess
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
OUTPUT = os.path.join(ROOT, "data", "words")
LENGTHS = (5, 6, 7)
LANGUAGES = ("pt", "en", "es")
KEPT_LETTERS = {"pt": "", "en": "", "es": "ñ"}
CANDIDATES_PER_LIST = 1200
ANSWERS_PER_LIST = 750
MINIMUM_ANSWERS = 365
# The word of the day is answers[day % len + 1], so a list may only change length while it is longer than
# the day number for a good while: after it wraps, a new length changes the word of every following day.
LENGTH_CHANGE_MARGIN_DAYS = 365
EPOCH = datetime.date(2026, 1, 1)


def plain(word, lang):
    letters = []
    for char in word:
        if char in KEPT_LETTERS[lang]:
            letters.append(char)
        else:
            letters.extend(c for c in unicodedata.normalize("NFD", char) if not unicodedata.combining(c))
    return "".join(letters)


def reachable(words, lang):
    """The words the player can type, asked to the game keyboard itself (tools/words/reachable.lua)."""
    words = sorted(set(words))
    result = subprocess.run(["luajit", os.path.join(HERE, "reachable.lua"), lang], input="\n".join(words) + "\n",
                            capture_output=True, text=True, encoding="utf-8", check=True)
    answers = result.stdout.split("\n")[:len(words)]
    if len(answers) != len(words):
        sys.exit("reachable.lua respondeu %d de %d palavras" % (len(answers), len(words)))
    return {word for word, answer in zip(words, answers) if answer == "1"}


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
    typable = reachable(set(ranked) | guess_keys, lang)
    return ranked, base_keys, guess_keys, blocked, typable


def ranked_answers(lang, length, ranked, base_keys, blocked, typable, excluded):
    answers, seen = [], set()
    for word in ranked:
        key = plain(word, lang)
        if len(key) != length or key in seen or word not in typable:
            continue
        if key in blocked or key not in base_keys or word in excluded:
            continue
        seen.add(key)
        answers.append(word)
    return answers


def read_reviewed(kind, lang):
    path = os.path.join(HERE, "%s_%s.txt" % (kind, lang))
    return set(read_lines(path)) if os.path.exists(path) else set()


def write_lines(path, lines):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def candidates(sources, out_dir, only_pending):
    os.makedirs(out_dir, exist_ok=True)
    for lang in LANGUAGES:
        ranked, base_keys, _, blocked, typable = load_language(sources, lang)
        reviewed = read_reviewed("approved", lang) | read_reviewed("exclude", lang)
        for length in LENGTHS:
            words = ranked_answers(lang, length, ranked, base_keys, blocked, typable, set())[:CANDIDATES_PER_LIST]
            if only_pending:
                words = [w for w in words if w not in reviewed]
            write_lines(os.path.join(out_dir, "%s_%d.txt" % (lang, length)), words)
            print("%s %d: %d %s" % (lang, length, len(words), "a revisar" if only_pending else "candidatas"))


def stable_answers(published, candidates, approved, excluded, blocked, typable, lang, seed):
    """Keeps the published order, so the word of the day does not change for anyone.

    A published word that is now excluded, blocked or no longer typable gives its place to a new word.
    New words only come from the approved list, in the order of the candidates, and only go to the end of
    the list, up to ANSWERS_PER_LIST.
    """
    published_keys = {plain(w, lang) for w in published}
    removed = [w in excluded or plain(w, lang) in blocked or w not in typable for w in published]
    fresh = [w for w in candidates if w in approved and w not in excluded and plain(w, lang) not in published_keys]
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
    today = (datetime.date.today() - EPOCH).days
    for lang in LANGUAGES:
        ranked, base_keys, guess_keys, blocked, typable = load_language(sources, lang)
        approved = read_reviewed("approved", lang)
        excluded = read_reviewed("exclude", lang)
        lang_dir = os.path.join(OUTPUT, lang)
        os.makedirs(lang_dir, exist_ok=True)
        for length in LENGTHS:
            answers_path = os.path.join(lang_dir, "answers_%d.txt" % length)
            published = read_lines(answers_path) if os.path.exists(answers_path) else []
            unapproved = [w for w in published if w not in approved]
            if unapproved:
                print("  %s %d: respostas publicadas fora de approved_%s.txt: %s" % (lang, length, lang, ", ".join(unapproved[:10])))
                failed = True
                continue
            candidates = ranked_answers(lang, length, ranked, base_keys, blocked, typable, excluded)
            words, shifted = stable_answers(published, candidates, approved, excluded, blocked,
                                            reachable(published, lang), lang,
                                            "%s-%d" % (lang, length))
            if shifted:
                print("  %s %d: palavras removidas sem substituta, a palavra do dia muda a partir delas" % (lang, length))
            if published and len(words) != len(published) and len(published) <= today + LENGTH_CHANGE_MARGIN_DAYS \
                    and os.environ.get("ALLOW_LENGTH_CHANGE") != "1":
                print("  %s %d: a lista passaria de %d para %d palavras, e o dia de hoje é %d: a palavra do dia mudaria"
                      " para todos. Para aceitar, rode de novo com ALLOW_LENGTH_CHANGE=1."
                      % (lang, length, len(published), len(words), today))
                failed = True
                continue
            guesses = {k for k in guess_keys if len(k) == length and k in typable}
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
    if sys.argv[2] in ("candidates", "pending"):
        candidates(sys.argv[1], sys.argv[3], sys.argv[2] == "pending")
    else:
        build(sys.argv[1])
