-- The letters of the game keyboard, without KOReader, so the word list tools ask the same keyboard the
-- player uses which words can be typed.
local Engine = require("vocabulo_game/engine")

local Keyboard = {}

local ROWS = {
    default = { "qwertyuiop", "asdfghjkl", "zxcvbnm" },
    es = { "qwertyuiop", "asdfghjklñ", "zxcvbnm" },
}

function Keyboard.rows(lang)
    return ROWS[lang] or ROWS.default
end

local letter_sets = {}
local function letters_of(lang)
    if not letter_sets[lang] then
        local set = {}
        for _, row in ipairs(Keyboard.rows(lang)) do
            for _, letter in ipairs(Engine.split(row)) do
                set[letter] = true
            end
        end
        letter_sets[lang] = set
    end
    return letter_sets[lang]
end

-- Whether every letter of the word, as the game compares it (without accents), has a key.
function Keyboard.reaches(word, lang)
    local keys = letters_of(lang)
    for _, letter in ipairs(Engine.split(Engine.plain(word, lang))) do
        if not keys[letter] then
            return false
        end
    end
    return true
end

return Keyboard
