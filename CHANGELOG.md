# Changelog

## [1.3.0]

- New look for every screen: the word of the day in a card on the title screen, with the streak and your attempts so far, rounded tiles and keys, and a result card with the numbers of the day when a game ends.
- A letter in another place is gray with a black corner, on the board and the keyboard, so it does not depend on telling gray from white.
- The statistics show a calendar of the last four weeks and highlight the attempts of your last daily game when you won it, and you can switch language and length without leaving them. The calendar fills from this version on.
- Free play shows how many attempts you need on average.
- Sharing opens a screen with the grid of colors and the QR code together.
- A "?" in the game opens How to play, with examples, and goes back to the same game.
- The sleep screen cover uses the new tiles.
- If a screen cannot be drawn, it shows a message and the Back button keeps working, instead of getting stuck.
- The documentation is now in English, with the README also in Portuguese (`README_pt.md`).
- The README has a banner, screenshots in English and Portuguese, and the statistics screen.

## [1.2.2]

- The English help also explains that accents do not need to be typed.
- If the game cannot open, a message says so, and KOReader keeps working in the same orientation as before.
- A damaged saved game no longer stops the game from opening: only that game is dropped, and the statistics stay.
- With the device clock set back, a day already played does not count again in the statistics.
- During a game, the screen flashes once every 8 updates to clear e-ink ghosting, instead of at a random moment.
- On devices with a Back button, quitting KOReader with the game open closes the game and restores the screen orientation.
- The word lists are built from fixed versions of the sources, checked by checksum, and new words only come from a reviewed list. The published lists do not change.

## [1.2.1]

- With the game open, the sleep screen shows the Vocábulo cover instead of the book cover.

## [1.2.0]

- 250 more daily words in Portuguese for each length, now 750, with common words that were left out before, such as escola, música and livro.
- More daily words in English and Spanish, now 750 for each length (744 in Spanish with 5 letters).
- The daily words already published stay the same, in the same order.

## [1.1.0]

- The error message goes away as soon as you start typing again.
- The streak in the statistics goes back to zero when you skip a day.
- The device Back button goes back one screen and, on the title screen, closes the game.
- The daily game keeps its answer, so it does not change if the lists are updated.
- Going back from the statistics opens the same game, even after midnight.
- Free play also avoids the daily words of the next 30 days.
- The statistics show the win rate with its own name, separate from the number of wins.
- Less work on every tap: the lists are loaded once per combination, and the texts of the board and keyboard are reused.
- Changing language or length does not flash the whole screen.
- The list generator keeps the published order, so the word of the day does not change for anyone already playing.
- The validation also checks the format of the guess lists.

## [1.0.0]

First public version.

- Word of the day in Portuguese, English and Spanish, with 5, 6 or 7 letters and 6 attempts.
- Free play, with random words and no daily limit.
- Win streak and statistics per language and length.
- Daily result as a QR code, without revealing letters.
- Works offline and saves progress after every attempt.
