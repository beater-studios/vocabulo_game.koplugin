local Words = {}

Words.LANGUAGES = { "pt", "en", "es" }
Words.LENGTHS = { 5, 6, 7 }

local function read_file(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

function Words.load_answers(plugin_dir, lang, length)
    local answers = {}
    for word in read_file(string.format("%s/data/words/%s/answers_%d.txt", plugin_dir, lang, length)):gmatch("[^\n]+") do
        answers[#answers + 1] = word
    end
    return answers
end

-- Guess lists have up to 50 thousand words, so they stay as one string instead of a table.
-- Every line ends with a newline, which tools/validate_words.lua checks.
function Words.load_validator(plugin_dir, lang, length)
    local guesses = read_file(string.format("%s/data/words/%s/guesses_%d.txt", plugin_dir, lang, length))
    return function(word)
        local line = word .. "\n"
        return guesses:sub(1, #line) == line or guesses:find("\n" .. line, 1, true) ~= nil
    end
end

return Words
