package.path = "./?.lua;" .. package.path
local Engine = require("vocabulo_game/engine")
local SavedState = require("vocabulo_game/saved_state")
local State = require("vocabulo_game/state")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAILED: " .. name .. "\n  " .. tostring(err))
    end
end
local function eq(actual, expected)
    if actual ~= expected then
        error(string.format("expected %s, got %s", tostring(expected), tostring(actual)), 2)
    end
end
local function load(saved)
    local warnings = {}
    local state = State.load(function(name) return saved[name] end, function(text) warnings[#warnings + 1] = text end)
    return state, warnings
end
local function list_dir(path)
    local names = {}
    local pipe = io.popen("ls '" .. path .. "'")
    for name in pipe:lines() do
        names[#names + 1] = name
    end
    pipe:close()
    return names
end
local function engine_for(record, lang, length)
    local engine = Engine.new{ lang = lang, length = length, day = record.day, answer = record.answer, is_valid = function() return true end }
    engine:restore(record)
    return engine
end
local function type_word(engine, word)
    for _, letter in ipairs(Engine.split(word)) do engine:add_letter(letter) end
    return engine:submit()
end

test("a game comes back the same after saving", function()
    local engine = Engine.new{ lang = "pt", length = 5, day = 312, answer = "buquê", is_valid = function() return true end }
    type_word(engine, "gesto")
    type_word(engine, "bolsa")
    local saved = { games = { pt_5 = SavedState.copy(State.record(engine, false, true)) }, lang = "pt", length = 5 }
    local state = load(saved)
    local again = engine_for(state.games.pt_5, "pt", 5)
    eq(#again.guesses, 2)
    eq(again.guesses[2], "bolsa")
    eq(again.day, 312)
    for i = 1, 5 do eq(again.results[2][i], engine.results[2][i]) end
    type_word(again, "buque")
    eq(again:is_won(), true)
end)

test("saving does not share the attempt list with the engine", function()
    local engine = Engine.new{ lang = "pt", length = 5, day = 1, answer = "carro", is_valid = function() return true end }
    type_word(engine, "gesto")
    local record = State.record(engine, false, true)
    type_word(engine, "bolsa")
    eq(#record.guesses, 1)
    local restored = engine_for(record, "pt", 5)
    type_word(restored, "mundo")
    eq(#record.guesses, 1)
end)

test("an answer that left the lists stays in the saved game", function()
    local state = load({ games = { pt_5 = { day = 5, answer = "zebra", guesses = { "carro" } } } })
    eq(state.games.pt_5.answer, "zebra")
    eq(state.games.pt_5.version, State.GAME_VERSION)
end)

test("a broken game is dropped and the rest stays", function()
    local state, warnings = load({
        lang = "es",
        games = {
            pt_5 = { day = 5, answer = "carro", guesses = 5 },
            pt_6 = { day = 5, answer = "carro", guesses = {} },
            en_5 = { day = "hoje", answer = "house", guesses = {} },
            es_5 = { day = 5, answer = "perro", guesses = { "gato" } },
            es_6 = { day = 5, answer = "pueblo", guesses = { "aaaaaa", "bbbbbb", "cccccc", "dddddd", "eeeeee", "ffffff", "gggggg" } },
            en_6 = { day = 5, answer = "bridge", guesses = { "orange" }, version = 2 },
            en_7 = { day = 5, answer = "kitchen", guesses = { "chicken" } },
            xx_5 = { day = 5, answer = "carro", guesses = {} },
            pt_9 = { day = 5, answer = "carro", guesses = {} },
        },
        stats = { pt_5 = { played = 3, won = 2, streak = 1, best_streak = 2, last_day = 4, distribution = { [3] = 2 } } },
    })
    for _, key in ipairs({ "pt_5", "pt_6", "en_5", "es_5", "es_6", "en_6", "xx_5", "pt_9" }) do
        eq(state.games[key], nil)
    end
    eq(state.games.en_7.guesses[1], "chicken")
    eq(state.stats.pt_5.played, 3)
    eq(state.stats.pt_5.distribution[3], 2)
    eq(state.lang, "es")
    eq(#warnings, 0)
end)

test("an error reading a game does not stop the opening", function()
    local broken = setmetatable({}, { __index = function() error("broken save") end })
    local state, warnings = load({ games = { pt_5 = broken, en_5 = { day = 1, answer = "house", guesses = {} } } })
    eq(state.games.pt_5, nil)
    eq(state.games.en_5.answer, "house")
    eq(#warnings, 1)
end)

test("statistics missing a field get the default value", function()
    local state = load({ stats = { en_5 = { played = 2, won = 1 }, es_7 = { played = "x", distribution = 3, last_day = "ontem" } } })
    eq(state.stats.en_5.played, 2)
    eq(state.stats.en_5.best_streak, 0)
    eq(state.stats.en_5.streak, 0)
    eq(next(state.stats.en_5.distribution), nil)
    eq(state.stats.es_7.played, 0)
    eq(state.stats.es_7.last_day, nil)
    eq(Engine.current_streak(state.stats.es_7, 10), 0)
    Engine.record_result(state.stats.en_5, 10, true, 4)
    eq(state.stats.en_5.distribution[4], 1)
end)

test("saved choices that no longer exist go back to the default", function()
    local state = load({ lang = "fr", length = 9 })
    eq(state.lang, nil)
    eq(state.length, 5)
    state = load({ lang = 1, length = "6" })
    eq(state.lang, nil)
    eq(state.length, 5)
    state = load({})
    eq(next(state.games), nil)
    eq(next(state.free_recent), nil)
end)

test("recent free play words without holes or repeats", function()
    local state = load({ free_recent = { pt_5 = { [1] = "carro", [2] = 5, [4] = "bolsa", [5] = "carro" }, en_5 = "x" } })
    eq(#state.free_recent.pt_5, 2)
    eq(state.free_recent.pt_5[2], "bolsa")
    eq(#state.free_recent.en_5, 0)
end)

test("the daily history keeps only days and results", function()
    local state = load({ history = { pt_5 = { [10] = "w", [11] = "l", [12] = "x", [12.5] = "w", day = "w" }, xx_5 = { [1] = "w" }, en_5 = 3 } })
    eq(state.history.pt_5[10], "w")
    eq(state.history.pt_5[11], "l")
    eq(state.history.pt_5[12], nil)
    eq(state.history.pt_5[12.5], nil)
    eq(state.history.pt_5.day, nil)
    eq(state.history.xx_5, nil)
    eq(next(state.history.en_5), nil)
end)

test("the attempts of the last game are a number from 1 to 6", function()
    local state = load({ stats = { pt_5 = { played = 1, won = 1, last_attempts = 4 }, pt_6 = { last_attempts = 9 }, pt_7 = { last_attempts = "4" } } })
    eq(state.stats.pt_5.last_attempts, 4)
    eq(state.stats.pt_6.last_attempts, nil)
    eq(state.stats.pt_7.last_attempts, nil)
end)

test("free play statistics get the attempts by game", function()
    local state = load({ free_stats = { pt_5 = { played = 3, won = 2 }, en_5 = { played = 2, won = 2, distribution = { [3] = 2, [7] = 1, [2] = -1 } } } })
    eq(next(state.free_stats.pt_5.distribution), nil)
    eq(state.free_stats.en_5.distribution[3], 2)
    eq(state.free_stats.en_5.distribution[7], nil)
    eq(state.free_stats.en_5.distribution[2], nil)
end)

test("saves from earlier versions open", function()
    local names = list_dir("tests/saves")
    eq(#names > 0, true)
    for _, name in ipairs(names) do
        local saved = dofile("tests/saves/" .. name)
        local state, warnings = load(saved)
        eq(#warnings, 0)
        local games = 0
        for key, record in pairs(state.games) do
            local lang, length = State.combination(key)
            local engine = engine_for(record, lang, length)
            eq(#engine.guesses, #saved.games[key].guesses)
            eq(engine.answer, saved.games[key].answer)
            eq(record.finished == true, saved.games[key].finished == true)
            games = games + 1
        end
        local saved_games = 0
        for _ in pairs(saved.games or {}) do saved_games = saved_games + 1 end
        eq(games, saved_games)
        for key, record in pairs(state.free_games) do
            eq(record.answer, saved.free_games[key].answer)
            eq(#record.guesses, #saved.free_games[key].guesses)
        end
        for key, stats in pairs(saved.stats or {}) do
            for _, field in ipairs({ "played", "won", "streak", "best_streak", "last_day" }) do
                eq(state.stats[key][field], stats[field])
            end
            for attempt = 1, Engine.ATTEMPTS do eq(state.stats[key].distribution[attempt], stats.distribution[attempt]) end
        end
        eq(state.lang, saved.lang)
        eq(state.length, saved.length)
    end
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
