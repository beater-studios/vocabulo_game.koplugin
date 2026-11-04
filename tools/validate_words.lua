package.path = "./?.lua;" .. package.path
local Engine = require("vocabulo_game/engine")
local Words = require("vocabulo_game/words")

local KEYBOARD = {
    pt = "abcdefghijklmnopqrstuvwxyz",
    en = "abcdefghijklmnopqrstuvwxyz",
    es = "abcdefghijklmnopqrstuvwxyzñ",
}
local MINIMUM_ANSWERS = 365
local errors = {}
local function fail(text)
    errors[#errors + 1] = text
end

for _, lang in ipairs(Words.LANGUAGES) do
    local allowed = {}
    for _, letter in ipairs(Engine.split(KEYBOARD[lang])) do
        allowed[letter] = true
    end
    for _, length in ipairs(Words.LENGTHS) do
        local label = lang .. " " .. length
        local answers = Words.load_answers(".", lang, length)
        local is_valid = Words.load_validator(".", lang, length)
        if #answers < MINIMUM_ANSWERS then
            fail(label .. ": só " .. #answers .. " respostas")
        end
        local seen = {}
        for _, word in ipairs(answers) do
            local key = Engine.plain(word, lang)
            local letters = Engine.split(key)
            if #letters ~= length then fail(label .. ": tamanho errado: " .. word) end
            if seen[key] then fail(label .. ": repetida: " .. word) end
            seen[key] = true
            if not is_valid(key) then fail(label .. ": resposta não aceita como tentativa: " .. word) end
            for _, letter in ipairs(letters) do
                if not allowed[letter] then fail(label .. ": letra sem tecla: " .. word) end
            end
        end
        -- The validator looks for "\nword\n", so the file format matters as much as the words.
        local path = string.format("data/words/%s/guesses_%d.txt", lang, length)
        local file = assert(io.open(path, "rb"))
        local content = file:read("*a")
        file:close()
        if content:find("\r", 1, true) then fail(label .. ": tentativas com \\r") end
        if content:sub(-1) ~= "\n" then fail(label .. ": tentativas sem quebra de linha no fim") end
        local previous, guesses = nil, 0
        for word in content:gmatch("([^\n]*)\n") do
            guesses = guesses + 1
            local letters = Engine.split(word)
            if #letters ~= length then fail(label .. ": tentativa de tamanho errado: " .. word) end
            for _, letter in ipairs(letters) do
                if not allowed[letter] then fail(label .. ": tentativa com letra sem tecla: " .. word) break end
            end
            if previous and word <= previous then fail(label .. ": tentativas fora de ordem ou repetidas: " .. word) end
            previous = word
        end
        print(string.format("%s: %d respostas, %d tentativas", label, #answers, guesses))
    end
end

local function load_data(path)
    local chunk = assert(loadfile(path))
    setfenv(chunk, {})
    return chunk()
end
local i18n = load_data("data/i18n.lua")
for key in pairs(i18n.pt) do
    for _, lang in ipairs(Words.LANGUAGES) do
        if i18n[lang][key] == nil then fail("texto ausente em " .. lang .. ": " .. key) end
    end
end
for _, lang in ipairs(Words.LANGUAGES) do
    for key in pairs(i18n[lang]) do
        if i18n.pt[key] == nil then fail("texto só em " .. lang .. ": " .. key) end
    end
end

for _, text in ipairs(errors) do
    print("ERRO: " .. text)
end
print(string.format("%d erros", #errors))
os.exit(#errors == 0 and 0 or 1)
