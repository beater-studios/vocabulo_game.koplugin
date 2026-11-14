import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "screensaver.png")

W, H = 600, 800
SCALE = 4
BLACK, GRAY, LIGHT, WHITE = 0, 170, 187, 255
ANSWER = "LIVRO"
GUESSES = ["NUVEM", "PORTA", "TURVO", "LIVRO"]
ROWS = 6


def evaluate(guess, answer):
    marks = ["absent"] * len(guess)
    left = list(answer)
    for i, letter in enumerate(guess):
        if answer[i] == letter:
            marks[i] = "correct"
            left[i] = None
    for i, letter in enumerate(guess):
        if marks[i] != "correct" and letter in left:
            marks[i] = "present"
            left[left.index(letter)] = None
    return marks


def font(koreader, name, size):
    return ImageFont.truetype(os.path.join(koreader, "fonts", "noto", name), size * SCALE)


def centered_text(draw, cx, cy, text, face, fill):
    draw.text((cx * SCALE, cy * SCALE), text, font=face, fill=fill, anchor="mm")


# The tiles of the game: rounded, and a letter in another place also gets a black corner.
def tile(draw, x, y, size, letter, mark, face):
    box = [x * SCALE, y * SCALE, (x + size) * SCALE, (y + size) * SCALE]
    radius = 7 * SCALE
    if mark == "correct":
        draw.rounded_rectangle(box, radius=radius, fill=BLACK)
        color = WHITE
    elif mark == "present":
        draw.rounded_rectangle(box, radius=radius, fill=GRAY, outline=BLACK, width=2 * SCALE)
        corner = size * 0.26
        draw.polygon([((x + size - corner) * SCALE, (y + 2) * SCALE), ((x + size - 2) * SCALE, (y + 2) * SCALE),
                      ((x + size - 2) * SCALE, (y + corner) * SCALE)], fill=BLACK)
        color = BLACK
    elif mark == "absent":
        draw.rounded_rectangle(box, radius=radius, fill=WHITE, outline=LIGHT, width=2 * SCALE)
        color = 136
    else:
        draw.rounded_rectangle(box, radius=radius, fill=WHITE, outline=LIGHT, width=2 * SCALE)
        return
    centered_text(draw, x + size / 2, y + size / 2 + 2, letter, face, color)


def main():
    koreader = os.environ.get("KOREADER_DIR")
    if not koreader:
        sys.exit("Set KOREADER_DIR to the KOReader folder, which has the Noto fonts.")
    image = Image.new("L", (W * SCALE, H * SCALE), WHITE)
    draw = ImageDraw.Draw(image)

    centered_text(draw, W / 2, 112, "Vocábulo", font(koreader, "NotoSerif-Bold.ttf", 68), BLACK)

    size, gap = 78, 9
    board_w = 5 * size + 4 * gap
    x0 = (W - board_w) // 2
    y0 = 196
    letter_face = font(koreader, "NotoSerif-Bold.ttf", 46)
    for row in range(ROWS):
        guess = GUESSES[row] if row < len(GUESSES) else None
        marks = evaluate(guess, ANSWER) if guess else [None] * 5
        for column in range(5):
            x, y = x0 + column * (size + gap), y0 + row * (size + gap)
            tile(draw, x, y, size, guess and guess[column], marks[column], letter_face)

    # Saved at twice the layout size, so larger screens get a sharp image and 600x800 gets a clean halving.
    small = image.resize((W * 2, H * 2), Image.LANCZOS)
    small = small.point(lambda v: round(v / 17) * 17)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    small.save(OUT, optimize=True)
    print(f"Image generated: {os.path.relpath(OUT, os.getcwd())}")


if __name__ == "__main__":
    sys.exit(main())
