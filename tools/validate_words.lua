package.path = "./?.lua;" .. package.path
local Engine = require("vocabulo_game/engine")
local Keyboard = require("vocabulo_game/keyboard")
local Words = require("vocabulo_game/words")

local MINIMUM_ANSWERS = 365
local errors = {}
local function fail(text)
    errors[#errors + 1] = text
end

for _, lang in ipairs(Words.LANGUAGES) do
    for _, length in ipairs(Words.LENGTHS) do
        local label = lang .. " " .. length
        local answers = Words.load_answers(".", lang, length)
        local is_valid = Words.load_validator(".", lang, length)
        if #answers < MINIMUM_ANSWERS then
            fail(label .. ": only " .. #answers .. " answers")
        end
        local seen = {}
        for _, word in ipairs(answers) do
            local key = Engine.plain(word, lang)
            local letters = Engine.split(key)
            if #letters ~= length then fail(label .. ": wrong length: " .. word) end
            if seen[key] then fail(label .. ": repeated: " .. word) end
            seen[key] = true
            if not is_valid(key) then fail(label .. ": answer not accepted as a guess: " .. word) end
            if not Keyboard.reaches(word, lang) then fail(label .. ": letter without a key: " .. word) end
        end
        -- The validator looks for "\nword\n", so the file format matters as much as the words.
        local path = string.format("data/words/%s/guesses_%d.txt", lang, length)
        local file = assert(io.open(path, "rb"))
        local content = file:read("*a")
        file:close()
        if content:find("\r", 1, true) then fail(label .. ": guesses with \\r") end
        if content:sub(-1) ~= "\n" then fail(label .. ": guesses without a final newline") end
        local previous, guesses = nil, 0
        for word in content:gmatch("([^\n]*)\n") do
            guesses = guesses + 1
            local letters = Engine.split(word)
            if #letters ~= length then fail(label .. ": guess of the wrong length: " .. word) end
            if Engine.plain(word, lang) ~= word then fail(label .. ": guess with an accent: " .. word) end
            if not Keyboard.reaches(word, lang) then fail(label .. ": guess with a letter without a key: " .. word) end
            if previous and word <= previous then fail(label .. ": guesses out of order or repeated: " .. word) end
            previous = word
        end
        print(string.format("%s: %d answers, %d guesses", label, #answers, guesses))
    end
end

for _, text in ipairs(errors) do
    print("ERROR: " .. text)
end
print(string.format("%d errors", #errors))
os.exit(#errors == 0 and 0 or 1)
