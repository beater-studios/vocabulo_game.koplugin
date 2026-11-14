# Vocábulo: design and tools

How the game works inside, for anyone who wants to understand the code or change the word lists. To install and play, see the [README](../README.md). `vocabulo_game` is the plugin identifier.

## Rules

- The player picks the language and the length (5, 6 or 7 letters) and has 6 attempts.
- Every attempt has to be a word from the list of valid guesses.
- **Black:** letter in the right place. **Gray with a black corner:** letter in the word, in another place. **White:** letter not in the word. A repeated letter is only marked as many times as the answer has it. The corner is on the board, the keyboard, the small grids of the title card and the sharing screen, and the help, so a letter in another place does not depend only on telling gray from white on a panel with ghosting.
- Accents and cedilla are not typed, and they appear when the word is revealed. In Spanish, `Ñ` is a letter of its own, with its own key.
- **Word of the day:** comes from the local date and the answer list of each combination of language and length. Everyone with the same settings gets the same word, with no internet. At the end of the list, the sequence starts over.
- **Free play:** words drawn from the same lists, with no daily limit. It does not count for the streak and has its own counter. The draw avoids today's word, the ones for the next 30 days and the last 30 drawn. A word played in free play can still come back as a word of the day later, when the list wraps around. The result is not shared.
- Progress is saved after every attempt in `koreader/settings/vocabulo_game.lua`, together with the answer, so a game in progress does not change if the lists are updated. Statistics are separate for each combination.
- The streak is only recalculated when a game ends. On the statistics screen, it shows as zero if the last game was before yesterday. Each day counts once: with the device clock set back, a day equal to or before the last one recorded does not count again.
- The result of the word of the day can be shared on a screen of its own, with the grid of colors and a QR code that holds the text of the result (`■ ▣ □`), without revealing letters.
- The interface texts follow the language picked. The first time, the language comes from the KOReader setting.
- The game is always in portrait and uses no network. If the device is in landscape, the screen rotates on opening and goes back on closing, or if opening fails; in that case, the menu shows a message instead of the game. It needs a touch screen. On devices with a Back button, it goes back one screen and, on the title screen, closes the game. The `Close` that KOReader sends to every window before quitting closes the game, except before a shutdown or restart, so the sleep screen is left alone.
- **Sleep screen:** if the device sleeps with the game open and the KOReader sleep screen is set to the book cover, the Vocábulo cover shows instead. With the game closed, in another mode, on shutdown or on restart, nothing changes.

## Structure

```
vocabulo_game.koplugin/
  _meta.lua, main.lua     registration in KOReader
  vocabulo_game/
    engine.lua            rules, without KOReader
    words.lua             loads the lists
    keyboard.lua          letters of the game keyboard, also used by the list generator
    state.lua             reads the saved progress, without KOReader
    ui/screen.lua         the window: state, navigation, taps, Back key and e-ink updates
    ui/canvas.lua         a screen laid out in the units of the mockups and scaled to the device
    ui/parts.lua          tiles, header, buttons, choices, number boxes and attempt bars
    ui/game_view.lua      the board with the keyboard, and the result card
    ui/pages.lua          title, statistics, sharing, help, about and the error message
    screensaver.lua       game cover on the sleep screen
    portrait.lua          portrait screen while the game is open
    refresh.lua           when the e-ink screen flashes
    letters.lua           accented letters (split, remove accents, upper case)
    calendar.lua          day number, word of the day, free play draw and streak
    saved_state.lua       reads saves from earlier versions
  data/
    i18n.lua              texts in the three languages
    words/<lang>/         answers_<n>.txt and guesses_<n>.txt
  assets/screensaver.png  full-screen cover, 1200x1600
  assets/icon.png         game icon for the About screen
  assets/icons/           SVG icons of the buttons, in black and, for dark buttons, in white
  tools/, tests/, docs/   development, left out of the published package
```

`screensaver.lua`, `portrait.lua`, `refresh.lua`, `letters.lua`, `calendar.lua` and `saved_state.lua` are unedited copies of modules shared with other plugins, as are `tools/package_lib.sh`, `tools/check_texts.lua`, the workflows in `.github/workflows/` and, in `tools/koreader/`, `run_headless.sh`, `run_emulator.sh`, `check_all_sizes.sh`, `fuzz.lua`, `check_screensaver.lua` and `check_rotation.lua`. The header of each one says so. An improvement to them is not made only here, because the next copy undoes it. The engine keeps the names it already used (`Engine.split`, `Engine.plain`, `Engine.today`, `Engine.record_result` and the others), calling those modules.

The sleep screen cover wraps KOReader's `Screensaver.setup`: it picks the image as usual, and the game only swaps it for its own cover when the Vocábulo screen is the full-screen window on top. No setting is saved, so there is nothing to undo on waking. The swap only happens with `screensaver_type` set to `cover` and on a regular sleep, not on shutdown or restart. The image is 1200x1600, twice 600x800, to stay sharp on larger screens; on 600x800 screens, KOReader halves it. The art comes from `KOREADER_DIR=<desktop KOReader> python3 -I tools/make_screensaver.py`, which uses Pillow and KOReader's Noto Serif.

Every screen is drawn by the one window widget, on a canvas (`ui/canvas.lua`) laid out in the units of the mockups, 600x800, scaled to the screen and centered. Laying out a screen builds a list of things to paint and of tap areas, each tap area with an id that the checks use; painting only replays the list. KOReader buttons are not used: 30 of them would weigh on e-ink, and they cannot draw the tiles and cards of the design.

The game screen is laid out again on every key, which costs under a millisecond on the desktop. The letters, the keys and the icons are built once and kept in a cache that lives until the window closes, so a key does not build dozens of texts or render an SVG again. On the e-ink screen, each key updates only the row being typed, and the message only when it changes.

Every text is measured when the screen is laid out. A text wider or taller than the room it was given is cut on the screen and noted by the canvas, and `tools/koreader/check_layout.lua` fails on any of them, in every language, at four screen sizes.

Screen updates only use the `ui` (no flash) and `full` (flash) modes, counted by `refresh.lua`. Each screen has a kind (`title`, `game` or the open page): opening a screen of another kind flashes, and a change within the same kind (changing language or length, sending an attempt) does not flash, up to 8 in a row; the ninth flashes, to clear the e-ink ghosting. Opening a game, ending a game and waking the device also make the next update flash. Typed letters only update their own row, outside the count. The `partial` mode is not used, because it goes into KOReader's own count and the flash would come at a random moment.

Laying out and painting both run inside `pcall`. If either fails (a save that passed the checks but does not work, for example), the error goes to the KOReader log, the screen shows only the Back button and a message in the three languages, and taps outside Back are ignored, so no tap lands on a key that is not shown. Without this, a painting error would repeat on every paint and the screen would be stuck. `check_layout.lua` plants both failures and checks this.

## Saved progress

Kept in `koreader/settings/vocabulo_game.lua`, written after every attempt. Keys:

- `lang` and `length`: the last combination picked.
- `games`: the daily game of each combination (`pt_5`, `en_7`...), with `version`, `day`, `answer`, `guesses` and `finished`. A finished daily game stays saved until the next day, so the title screen shows "See Result" and the same word is not played again.
- `stats`: per combination, `played`, `won`, `streak`, `best_streak`, `last_day`, `distribution` (wins by number of attempts) and `last_attempts` (the attempts of the last daily game when it was won, highlighted in the statistics; empty after a loss).
- `history`: per combination, the result of each daily game of the last 70 days (`"w"` won, `"l"` lost), for the calendar of the last 4 weeks in the statistics. It starts empty in the version that added it.
- `free_games`, `free_stats` and `free_recent`: the free play game, its counters (`played`, `won` and `distribution`, for the average of attempts) and the last 30 words drawn, without accents, per combination.

`history`, `last_attempts` and the free play `distribution` were added in 1.3.0 as new fields, with the same meaning in every save, so the game `version` did not change. `state.lua` reads everything back field by field: a language or length that does not exist goes back to the default, a field missing from the statistics gets the default value, and a game whose answer, day or attempts do not fit its combination is dropped, without taking the statistics or the other games with it. Each game is read protected, so a broken save never stops the game from opening. Games saved before 1.2.2 have no `version` and are read as version 1, which has the same format. `version` only goes up when a field changes meaning, and then reading converts or drops only the game. The saved attempts are a copy, never the same table the engine keeps changing.

`tests/saves/<version>.lua` keeps real saves from published versions, made in the emulator with that version, and `tests/state_spec.lua` opens each one. Before publishing a version that changes the lists or the save format, make a save with the published version and add it to the folder.

The valid guesses are kept as a single string in memory, with up to 49 thousand words, instead of a Lua table. Only the list of the combination in play is loaded.

## Word lists

Built by `tools/words/build_words.py`, from the sources downloaded by `tools/words/fetch_sources.sh`. The sources stay out of the repository. The script downloads each source at a fixed commit, written in it, into a new and empty folder (it refuses a folder with files), and checks the SHA-256 of each file against `tools/words/sources.sha256`. The commits are the ones that built the lists published in 1.2.0, and building again with them gives exactly the lists in the repository. Updating a source is a deliberate change, made on its own: change the commit in the script and the checksum in `sources.sha256`, and review the difference in the lists.

| Use | Portuguese | English | Spanish |
|---|---|---|---|
| Valid guesses | [fserb/pt-br](https://github.com/fserb/pt-br) (MIT) | [dwyl/english-words](https://github.com/dwyl/english-words) (Unlicense) | [an-array-of-spanish-words](https://github.com/words/an-array-of-spanish-words) (MIT) |
| Answer frequency | ICF from fserb/pt-br | [FrequencyWords](https://github.com/hermitdave/FrequencyWords) (content CC BY-SA 4.0) | FrequencyWords |

Two filters are only used while building, and do not go into the game: the base forms of the Hunspell dictionaries from [wooorm/dictionaries](https://github.com/wooorm/dictionaries), which remove inflections and proper names, and [LDNOOBW](https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words) (CC BY 4.0). In Portuguese, the Hunspell base forms do not work: it keeps common words as derived from others (escola from "escolar", música from "músico", livro from "livrar"), and they would never become answers. So the Portuguese base is the fserb/pt-br lexicon, minus plurals and part of the proper names:

- **Plurals:** the word goes out when its singular, by -s, -es, -ões, -ães, -ãos, -ns, -is (-l or -il) or -eis, is also in the lexicon. For the suffixes ending in -is or -es (-is, -eis, -es, -ões, -ães), the singular is compared without accents, to catch papéis (papel), meses (mês) and ingleses (inglês). For -s and -ãos the comparison is exact, otherwise pires would go out as the plural of piré. Nouns only used in the plural, such as óculos, férias and parabéns, also go out.
- **Proper names:** a word that Hunspell only knows capitalized goes out, such as Cícero and Beatriz. The comparison keeps accents, so a place like Choró does not remove choro. The filter is partial: Hunspell lacks many names (Silva, Bruno, Mariana) and only has a few common words capitalized (leste, malta, marinho), which then stop being candidates.

The lexicon also has conjugated verb forms (passa, deixa, penso, sofreu), and the filters do not catch proper names, demonyms or foreign words that Hunspell does not know. All of that goes out when the candidates are reviewed. Verb forms that are also nouns, such as conta and ajuda, stay; the ones that are only verbs go out. Infinitives can be answers.

Answers only come from `tools/words/approved_<lang>.txt`, the list of words already reviewed and approved, in the frequency order of the candidates, shuffled with a fixed seed. Rejected words stay in `tools/words/exclude_<lang>.txt`, so they do not come back for review. There are up to 750 answers per language and length. Every published answer is in the approved list, and the generator stops with an error if one is not. A new word from the sources only becomes an answer after someone approves it: `build_words.py <sources> pending <folder>` lists, among the first 1200 candidates of each combination, those that are neither approved nor excluded, and each one goes to one of the two lists. The first approved list was made with everything already published plus the first 1200 candidates of each combination that were not excluded, which the generator used to treat as reviewed.

The generator does not repeat the keyboard rules: `tools/words/reachable.lua` loads the game's `keyboard.lua` and answers, word by word, whether it can be typed in that language. A published answer that can no longer be typed goes out like an excluded one.

The published order in `answers_<n>.txt` is the sequence of daily words, so the generator keeps it: published words stay in the same place, a word that becomes excluded or blocked is replaced by a new one in the same position, and new words only go at the end, up to the limit for the language. A word already among the answers only goes out through `exclude_<lang>.txt` or the blocklist: changes to the filters or to the candidate cut do not reach it, so the sequence does not move. That is why some answers may be outside the current candidates (in Portuguese, leste, malta, marinho, pomar and névoa). Running the generator again with the same sources changes nothing. Only when there is no replacement does the list get shorter and the sequence change from that point, and the generator says so. Since the word of the day is `answers[day % length + 1]`, changing the length of a list only keeps the following days while the list is longer than today's day number. So the generator stops with an error, without writing, when the length of a list would change and it does not have at least a year to spare over today's day number; `ALLOW_LENGTH_CHANGE=1` accepts the change on purpose. To build a list from scratch, delete the matching `answers_<n>.txt` first.

What is excluded: function words, inflections, proper names, demonyms, months, foreign words, obscure terms and anything offensive or heavy to see first thing in the morning (violence, death, serious illness, drugs, religion and party politics).

```sh
sh tools/words/fetch_sources.sh /new/folder
python3 -I tools/words/build_words.py /new/folder pending /review/folder
python3 -I tools/words/build_words.py /new/folder build
```

The release builds the lists again from the sources and fails if the result differs from the repository (`sh tools/check.sh release`), so what was reviewed is what goes into the package.

## Tools

- `sh tools/check.sh`: everything that runs without KOReader, the same command on the Mac and in the CI: `tools/validate_words.lua` (the lists and the keyboard), the tests in `tests/*_spec.lua` (the engine and the saved progress), `tools/check_texts.lua t 'strings()'` (the same keys and markers in the three languages, no dashes, no device brand and every key the code asks for present) and the package. With `release`, it also downloads the sources, builds the lists and checks that they match the repository.
- `sh tools/package.sh`: builds the zip and its checksum in `dist/`, with the steps of `tools/package_lib.sh`, which requires `LICENSE`, `NOTICE` and the cover and checks that everything the code loads is in the package. The same content builds the same zip, byte for byte.
- With `KOREADER_DIR` pointing to a desktop KOReader, from the plugin folder:
  - `tools/koreader/run_emulator.sh` opens the game in a 600x800 window, with the on-screen keyboard on, as on the Kindle.
  - `tools/koreader/check_all_sizes.sh` runs `tools/koreader/check_layout.lua` at four screen sizes and lists every one that failed. In each interface language, it plays every combination through the tap areas, as a finger would, and checks that no screen has a text out of its room, anything below the screen or a tap area outside it; the texts that only show in some games (six attempts, day 9999); the statistics and history recorded; the version on the About screen; a game resumed in a new screen; the sequence of refresh modes; planted layout and painting failures; and the Back key.
  - `tools/koreader/run_headless.sh tools/koreader/fuzz_ui.lua` makes random taps, holds and swipes on the title screen, on the word of the day of each combination and on free play in each language, typing words from the lists now and then, with the day fixed. Each error comes with the command to repeat it (`SEED`, `ACTIONS` and `ONLY`).
  - `tools/koreader/run_headless.sh tools/koreader/check_screensaver.lua` checks when the game cover goes on the sleep screen, and `tools/koreader/check_rotation.lua` opens the game with KOReader in landscape and checks portrait, also when opening fails.
  - With `OUTPUT_DIR`, the scripts save the screens as PNG in that folder. `OUTPUT_DIR=docs/screenshots tools/koreader/run_headless.sh tools/koreader/render_screens.lua` makes the README screenshots (title, game, result and statistics), in English in `docs/screenshots/` and in Portuguese in `docs/screenshots/pt/`, with the date fixed on 2026-11-14 and made-up statistics.
- `KOREADER_DIR=<desktop KOReader> python3 -I tools/make_brand_art.py`, after the screenshots: the icon (`docs/brand/icon.png`, and `assets/icon.png` for the About screen), the README banner and the GitHub preview, in English (`docs/brand/banner.png` and `docs/social-preview.png`) and in Portuguese (the same names ending in `_pt`). The GitHub preview is uploaded by hand in the repository's Settings > Social preview.

The emulator does not show what is specific to e-ink or the speed of the device: the final check is on a real device.

## License

Everything is under GPL-3.0, version 3 only. A "non-commercial" license is not possible here, because the answers use CC BY-SA 4.0 data. Credits for the sources are in `NOTICE`.

## Publishing a version

1. Update `version` in `_meta.lua` and add the version section in `CHANGELOG.md`, in the form `## [1.2.3]`.
2. If the version changes the lists or the save format, add to `tests/saves/` a save made with the published version.
3. Run `sh tools/check.sh`, `tools/koreader/check_all_sizes.sh`, `fuzz_ui.lua`, `check_screensaver.lua` and `check_rotation.lua`, and test on a device.
4. Publish the release `v1.2.3` on GitHub, creating the tag with it, after the push. The `release.yml` workflow checks that the tag matches `_meta.lua`, runs `sh tools/check.sh release` (which builds the lists again from the sources), builds the package and attaches the zip and its checksum to the release. The CI (`ci.yml`) runs `sh tools/check.sh` on every push and pull request.
