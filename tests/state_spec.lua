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
        print("FALHOU: " .. name .. "\n  " .. tostring(err))
    end
end
local function eq(actual, expected)
    if actual ~= expected then
        error(string.format("esperado %s, veio %s", tostring(expected), tostring(actual)), 2)
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

test("partida volta igual depois de salvar", function()
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

test("salvar não divide a lista de tentativas com o motor", function()
    local engine = Engine.new{ lang = "pt", length = 5, day = 1, answer = "carro", is_valid = function() return true end }
    type_word(engine, "gesto")
    local record = State.record(engine, false, true)
    type_word(engine, "bolsa")
    eq(#record.guesses, 1)
    local restored = engine_for(record, "pt", 5)
    type_word(restored, "mundo")
    eq(#record.guesses, 1)
end)

test("resposta que saiu das listas continua na partida salva", function()
    local state = load({ games = { pt_5 = { day = 5, answer = "zebra", guesses = { "carro" } } } })
    eq(state.games.pt_5.answer, "zebra")
    eq(state.games.pt_5.version, State.GAME_VERSION)
end)

test("partida estragada é descartada e o resto fica", function()
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

test("erro ao ler uma partida não impede a abertura", function()
    local broken = setmetatable({}, { __index = function() error("save quebrado") end })
    local state, warnings = load({ games = { pt_5 = broken, en_5 = { day = 1, answer = "house", guesses = {} } } })
    eq(state.games.pt_5, nil)
    eq(state.games.en_5.answer, "house")
    eq(#warnings, 1)
end)

test("estatísticas sem um campo recebem o valor padrão", function()
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

test("opções salvas que não existem voltam ao padrão", function()
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

test("palavras recentes do modo livre sem buracos nem repetidas", function()
    local state = load({ free_recent = { pt_5 = { [1] = "carro", [2] = 5, [4] = "bolsa", [5] = "carro" }, en_5 = "x" } })
    eq(#state.free_recent.pt_5, 2)
    eq(state.free_recent.pt_5[2], "bolsa")
    eq(#state.free_recent.en_5, 0)
end)

test("saves de versões anteriores abrem", function()
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

print(string.format("%d passaram, %d falharam", passed, failed))
os.exit(failed == 0 and 0 or 1)
