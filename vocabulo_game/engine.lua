local Engine = {}
Engine.__index = Engine

Engine.ATTEMPTS = 6
Engine.CORRECT = "correct"
Engine.PRESENT = "present"
Engine.ABSENT = "absent"

local EPOCH_DAY = 20454 -- 2026-01-01

local ACCENTS = {
    ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a",
    ["é"] = "e", ["ê"] = "e", ["è"] = "e", ["ë"] = "e",
    ["í"] = "i", ["î"] = "i", ["ì"] = "i", ["ï"] = "i",
    ["ó"] = "o", ["ô"] = "o", ["õ"] = "o", ["ò"] = "o", ["ö"] = "o",
    ["ú"] = "u", ["û"] = "u", ["ù"] = "u", ["ü"] = "u",
    ["ç"] = "c", ["ñ"] = "n",
}
local KEPT_LETTERS = { es = { ["ñ"] = true } }

local UPPER = {
    ["á"] = "Á", ["à"] = "À", ["â"] = "Â", ["ã"] = "Ã", ["ä"] = "Ä",
    ["é"] = "É", ["ê"] = "Ê", ["è"] = "È", ["ë"] = "Ë",
    ["í"] = "Í", ["î"] = "Î", ["ì"] = "Ì", ["ï"] = "Ï",
    ["ó"] = "Ó", ["ô"] = "Ô", ["õ"] = "Õ", ["ò"] = "Ò", ["ö"] = "Ö",
    ["ú"] = "Ú", ["û"] = "Û", ["ù"] = "Ù", ["ü"] = "Ü",
    ["ç"] = "Ç", ["ñ"] = "Ñ",
}

function Engine.upper(letter)
    return UPPER[letter] or letter:upper()
end

function Engine.split(word)
    local letters = {}
    for char in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        letters[#letters + 1] = char
    end
    return letters
end

function Engine.plain(word, lang)
    local kept = KEPT_LETTERS[lang] or {}
    local out = {}
    for _, char in ipairs(Engine.split(word)) do
        out[#out + 1] = (not kept[char] and ACCENTS[char]) or char
    end
    return table.concat(out)
end

-- Repeated letters are only marked present as many times as the answer still has them.
function Engine.evaluate(guess, answer)
    local guess_letters, answer_letters = Engine.split(guess), Engine.split(answer)
    local result, remaining = {}, {}
    for i, letter in ipairs(answer_letters) do
        if guess_letters[i] == letter then
            result[i] = Engine.CORRECT
        else
            remaining[letter] = (remaining[letter] or 0) + 1
        end
    end
    for i, letter in ipairs(guess_letters) do
        if not result[i] then
            if (remaining[letter] or 0) > 0 then
                result[i] = Engine.PRESENT
                remaining[letter] = remaining[letter] - 1
            else
                result[i] = Engine.ABSENT
            end
        end
    end
    return result
end

-- Civil date to day count, so the result does not depend on the time zone or daylight saving.
function Engine.day_number(date)
    local year = date.month <= 2 and date.year - 1 or date.year
    local era = math.floor(year / 400)
    local year_of_era = year - era * 400
    local shifted_month = date.month > 2 and date.month - 3 or date.month + 9
    local day_of_year = math.floor((153 * shifted_month + 2) / 5) + date.day - 1
    local day_of_era = year_of_era * 365 + math.floor(year_of_era / 4) - math.floor(year_of_era / 100) + day_of_year
    return era * 146097 + day_of_era - 719468 - EPOCH_DAY
end

function Engine.today()
    return Engine.day_number(os.date("*t"))
end

function Engine.answer_for_day(answers, day)
    return answers[day % #answers + 1]
end

-- Free play shares the daily lists, so it skips the daily words of the coming days and the ones played recently.
function Engine.free_avoided(answers, lang, today, upcoming_days, recent)
    local avoided = {}
    for day = today, today + upcoming_days do
        avoided[Engine.plain(Engine.answer_for_day(answers, day), lang)] = true
    end
    for _, word in ipairs(recent) do
        avoided[word] = true
    end
    return avoided
end

function Engine.pick_free(answers, lang, avoided, random)
    local candidates = {}
    for _, word in ipairs(answers) do
        if not avoided[Engine.plain(word, lang)] then
            candidates[#candidates + 1] = word
        end
    end
    if #candidates == 0 then
        candidates = answers
    end
    return candidates[random(#candidates)]
end

function Engine.new(opts)
    return setmetatable({
        lang = opts.lang,
        length = opts.length,
        day = opts.day,
        answer = opts.answer,
        answer_key = Engine.plain(opts.answer, opts.lang),
        is_valid = opts.is_valid,
        guesses = {},
        results = {},
        current = {},
    }, Engine)
end

function Engine:restore(saved)
    self.guesses = saved.guesses or {}
    self.results = {}
    for i, guess in ipairs(self.guesses) do
        self.results[i] = Engine.evaluate(guess, self.answer_key)
    end
    self.current = {}
end

-- The answer is saved too, so a game in progress survives an update of the word lists.
function Engine:serialize()
    return { day = self.day, answer = self.answer, guesses = self.guesses }
end

function Engine:is_won()
    return self.guesses[#self.guesses] == self.answer_key
end

function Engine:is_over()
    return self:is_won() or #self.guesses >= Engine.ATTEMPTS
end

function Engine:add_letter(letter)
    if not self:is_over() and #self.current < self.length then
        self.current[#self.current + 1] = letter
        return true
    end
    return false
end

function Engine:remove_letter()
    if not self:is_over() and #self.current > 0 then
        self.current[#self.current] = nil
        return true
    end
    return false
end

function Engine:submit()
    if self:is_over() then
        return false, "over"
    end
    if #self.current < self.length then
        return false, "short"
    end
    local guess = table.concat(self.current)
    if not self.is_valid(guess) then
        return false, "unknown"
    end
    self.guesses[#self.guesses + 1] = guess
    self.results[#self.results + 1] = Engine.evaluate(guess, self.answer_key)
    self.current = {}
    return true
end

local STATE_RANK = { [Engine.ABSENT] = 1, [Engine.PRESENT] = 2, [Engine.CORRECT] = 3 }

function Engine:keyboard_states()
    local states = {}
    for i, guess in ipairs(self.guesses) do
        local letters = Engine.split(guess)
        for j, letter in ipairs(letters) do
            local state = self.results[i][j]
            if not states[letter] or STATE_RANK[state] > STATE_RANK[states[letter]] then
                states[letter] = state
            end
        end
    end
    return states
end

function Engine.new_stats()
    return { played = 0, won = 0, streak = 0, best_streak = 0, last_day = nil, distribution = {} }
end

function Engine.record_result(stats, day, won, attempts)
    if stats.last_day == day then
        return stats
    end
    stats.played = stats.played + 1
    if won then
        stats.won = stats.won + 1
        stats.streak = stats.last_day == day - 1 and stats.streak + 1 or 1
        stats.best_streak = math.max(stats.best_streak, stats.streak)
        stats.distribution[attempts] = (stats.distribution[attempts] or 0) + 1
    else
        stats.streak = 0
    end
    stats.last_day = day
    return stats
end

-- The saved streak only changes when a game ends, so a missed day has to be checked when showing it.
function Engine.current_streak(stats, today)
    if stats.last_day and today - stats.last_day > 1 then
        return 0
    end
    return stats.streak
end

function Engine:share_text(title)
    local marks = { [Engine.CORRECT] = "■", [Engine.PRESENT] = "▣", [Engine.ABSENT] = "□" }
    local lines = { string.format("%s %s %d #%d %s/%d", title, self.lang:upper(), self.length, self.day,
        self:is_won() and #self.guesses or "X", Engine.ATTEMPTS) }
    for _, result in ipairs(self.results) do
        local row = {}
        for i, state in ipairs(result) do
            row[i] = marks[state]
        end
        lines[#lines + 1] = table.concat(row)
    end
    return table.concat(lines, "\n")
end

return Engine
