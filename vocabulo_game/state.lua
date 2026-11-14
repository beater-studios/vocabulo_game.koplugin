-- Reads back what any version saved in koreader/settings/vocabulo_game.lua, without KOReader, so the tests
-- load real saves of older versions. Games, statistics and choices are checked field by field: a game that
-- cannot be read is dropped, and the statistics and the other games stay.
local Engine = require("vocabulo_game/engine")
local SavedState = require("vocabulo_game/saved_state")
local Words = require("vocabulo_game/words")

local State = {}

-- Goes up only when a saved field changes meaning. Games saved before 1.2.2 have no version and the same
-- format, so they count as version 1.
State.GAME_VERSION = 1

local STATS = { played = 0, won = 0, streak = 0, best_streak = 0, distribution = {} }
local FREE_STATS = { played = 0, won = 0, distribution = {} }

-- "pt_5" to "pt", 5, or nil for a combination the game does not have.
function State.combination(key)
    if type(key) ~= "string" then
        return nil
    end
    local lang, length = key:match("^(%a+)_(%d+)$")
    length = tonumber(length)
    if SavedState.one_of(lang, Words.LANGUAGES) and SavedState.one_of(length, Words.LENGTHS) then
        return lang, length
    end
end

local function letter_count(word, lang)
    return #Engine.split(Engine.plain(word, lang))
end

-- A saved game checked against its combination, or nil when it cannot be played. The answer is kept even if
-- the word lists no longer have it, so a game in progress survives an update of the lists.
function State.game(saved, lang, length, daily)
    if type(saved) ~= "table" then
        return nil
    end
    if (saved.version or 1) ~= State.GAME_VERSION then
        return nil
    end
    if type(saved.answer) ~= "string" or letter_count(saved.answer, lang) ~= length then
        return nil
    end
    if daily and (type(saved.day) ~= "number" or saved.day % 1 ~= 0) then
        return nil
    end
    if type(saved.guesses) ~= "table" then
        return nil
    end
    local guesses = {}
    for _, guess in ipairs(SavedState.list(saved.guesses)) do
        if type(guess) ~= "string" or letter_count(guess, lang) ~= length or #guesses == Engine.ATTEMPTS then
            return nil
        end
        guesses[#guesses + 1] = Engine.plain(guess, lang)
    end
    return {
        version = State.GAME_VERSION,
        day = daily and saved.day or nil,
        answer = saved.answer,
        guesses = guesses,
        finished = saved.finished == true or nil,
    }
end

-- Wins by number of attempts, without anything but positive counts from 1 to ATTEMPTS.
local function distribution_of(saved)
    local distribution = {}
    for attempt = 1, Engine.ATTEMPTS do
        local count = type(saved) == "table" and saved[attempt]
        if type(count) == "number" and count > 0 then
            distribution[attempt] = count
        end
    end
    return distribution
end

local function whole_number(value)
    return type(value) == "number" and value % 1 == 0 and value or nil
end

local function stats_of(saved)
    local stats = SavedState.with_defaults(saved, STATS)
    stats.last_day = whole_number(stats.last_day)
    -- The attempts of the last daily game when it was won (nil after a loss), highlighted in the statistics (saved since 1.3.0).
    local last = whole_number(stats.last_attempts)
    stats.last_attempts = last and last >= 1 and last <= Engine.ATTEMPTS and last or nil
    stats.distribution = distribution_of(stats.distribution)
    return stats
end

local function free_stats_of(saved)
    local stats = SavedState.with_defaults(saved, FREE_STATS)
    stats.distribution = distribution_of(stats.distribution)
    return stats
end

-- The result of each recent daily game, by day: "w" won, "l" lost (saved since 1.3.0).
local function history_of(saved)
    local history = {}
    if type(saved) ~= "table" then
        return history
    end
    for day, mark in pairs(saved) do
        if whole_number(day) and (mark == "w" or mark == "l") then
            history[day] = mark
        end
    end
    return history
end

local function recent_of(saved)
    return SavedState.known(saved, function(word) return type(word) == "string" end)
end

-- Each entry of a saved map by combination, through `read(value, lang, length)`, keeping the ones that
-- give something back. `read` runs protected, so one broken entry never stops the opening.
local function by_combination(saved, read, warn)
    local out = {}
    if type(saved) ~= "table" then
        return out
    end
    for key, value in pairs(saved) do
        local lang, length = State.combination(key)
        if lang then
            out[key] = SavedState.restore(function(data) return read(data, lang, length) end, value, warn)
        end
    end
    return out
end

-- read(name) gives a saved setting (settings:readSetting); warn reports a dropped game (logger.warn).
function State.load(read, warn)
    return {
        lang = SavedState.one_of(read("lang"), Words.LANGUAGES),
        length = SavedState.one_of(read("length"), Words.LENGTHS, Words.LENGTHS[1]),
        games = by_combination(read("games"), function(data, lang, length) return State.game(data, lang, length, true) end, warn),
        stats = by_combination(read("stats"), stats_of, warn),
        free_games = by_combination(read("free_games"), function(data, lang, length) return State.game(data, lang, length, false) end, warn),
        free_stats = by_combination(read("free_stats"), free_stats_of, warn),
        free_recent = by_combination(read("free_recent"), recent_of, warn),
        history = by_combination(read("history"), history_of, warn),
    }
end

-- What goes into the save for the game in play: a copy, so the engine never changes a saved table.
function State.record(engine, finished, daily)
    return {
        version = State.GAME_VERSION,
        day = daily and engine.day or nil,
        answer = engine.answer,
        guesses = SavedState.copy(engine.guesses),
        finished = finished or nil,
    }
end

return State
