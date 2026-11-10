local Calendar = require("vocabulo_game/calendar")
local Letters = require("vocabulo_game/letters")

local Engine = {}
Engine.__index = Engine

Engine.ATTEMPTS = 6
Engine.CORRECT = "correct"
Engine.PRESENT = "present"
Engine.ABSENT = "absent"

local KEPT_LETTERS = { es = { ["ñ"] = true } }

Engine.split = Letters.split
Engine.upper = Letters.upper
Engine.lower = Letters.lower

-- Without accents and cedilla, keeping the letters the language types as they are (ñ in Spanish).
function Engine.plain(word, lang)
    return Letters.plain(word, KEPT_LETTERS[lang])
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

Engine.day_number = Calendar.day_number
Engine.today = Calendar.today
Engine.answer_for_day = Calendar.of_day

-- Free play shares the daily lists, so it skips the daily words of the coming days and the ones played
-- recently. Words are compared without accents, and the recent ones are saved that way.
function Engine.free_avoided(answers, lang, today, upcoming_days, recent)
    return Calendar.avoided(answers, today, upcoming_days, recent, function(word) return Engine.plain(word, lang) end)
end

function Engine.pick_free(answers, lang, avoided, random)
    return Calendar.pick_free(answers, avoided, random, function(word) return Engine.plain(word, lang) end)
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
    self.guesses = {}
    for i, guess in ipairs(saved.guesses or {}) do
        self.guesses[i] = guess
    end
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
    local stats = Calendar.new_stats()
    stats.distribution = {}
    return stats
end

-- A day is recorded once; the attempts only count when it was.
function Engine.record_result(stats, day, won, attempts)
    if Calendar.record(stats, day, won) and won then
        stats.distribution[attempts] = (stats.distribution[attempts] or 0) + 1
    end
    return stats
end

Engine.current_streak = Calendar.current_streak

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
