-- The README screenshots: title, game, result and statistics, in English (OUTPUT_DIR) and Portuguese
-- (OUTPUT_DIR/pt). Run: OUTPUT_DIR=docs/screenshots KOREADER_DIR=<desktop KOReader> tools/koreader/run_headless.sh tools/koreader/render_screens.lua
local plugin_dir = assert(os.getenv("PLUGIN_DIR"))
local out_dir = assert(os.getenv("OUTPUT_DIR"))

require("setupkoenv")
local DataStorage = require("datastorage")
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
package.path = plugin_dir .. "/?.lua;" .. package.path

local Device = require("device")
local Screen = Device.screen
require("document/canvascontext"):init(Device)
local UIManager = require("ui/uimanager")
UIManager:init()
local Engine = require("vocabulo_game/engine")
local GameScreen = require("vocabulo_game/ui/screen")

-- A fixed date (Saturday 2026-11-14, day 317), so the images only change when the screens do.
local real_date = os.date
os.date = function(format, time)
    if format == "*t" and time == nil then
        return { year = 2026, month = 11, day = 14, wday = 7, yday = 318, hour = 14, min = 32, sec = 0, isdst = false }
    end
    return real_date(format, time)
end
local TODAY = Engine.today()

-- Words picked so the game shows the three colors before the answer.
local GAMES = {
    en = { folder = out_dir, answer = "plant", guesses = { "house", "train", "plain" }, typing = "pla" },
    pt = { folder = out_dir .. "/pt", answer = "carta", guesses = { "mundo", "barco", "campo" }, typing = "car" },
}

local function shot(game, folder, name)
    UIManager:forceRePaint()
    local path = folder .. "/" .. name .. ".png"
    Screen.bb:writePNG(path)
    print("saved: " .. path)
end

-- Made-up statistics: nine days in a row up to yesterday, as on the title screen.
local function made_up_stats(game, key)
    game.stats[key] = {
        played = 30, won = 28, streak = 9, best_streak = 12, last_day = TODAY - 1, last_attempts = 3,
        distribution = { [2] = 3, [3] = 9, [4] = 11, [5] = 3, [6] = 2 },
    }
    local history = {}
    local marks = "wwwlw-www-wwwwwwlwwwwwwwwww"
    for i = 1, #marks do
        local mark = marks:sub(i, i)
        if mark ~= "-" then history[TODAY - #marks - 1 + i] = mark end
    end
    game.history[key] = history
    game.free_stats[key] = { played = 14, won = 12, distribution = { [3] = 4, [4] = 5, [5] = 2, [6] = 1 } }
end

for _, lang in ipairs({ "en", "pt" }) do
    local spec = GAMES[lang]
    os.execute("mkdir -p '" .. spec.folder .. "'")
    local game = GameScreen:new{ plugin_dir = plugin_dir }
    UIManager:show(game)
    game.lang, game.length, game.games = lang, 5, {}
    made_up_stats(game, game:config_key())
    game:start_game()
    game.engine.answer, game.engine.answer_key = spec.answer, spec.answer
    for _, word in ipairs(spec.guesses) do
        for _, letter in ipairs(Engine.split(word)) do game:press(letter) end
        game:press("submit")
    end
    assert(#game.engine.guesses == #spec.guesses, "a guess was not accepted")
    for _, letter in ipairs(Engine.split(spec.typing)) do game:press(letter) end
    game:show_title()
    shot(game, spec.folder, "title")
    game:start_game()
    for _, letter in ipairs(Engine.split(spec.typing)) do game:press(letter) end
    shot(game, spec.folder, "game")
    for _, letter in ipairs(Engine.split(spec.answer:sub(#spec.typing + 1))) do game:press(letter) end
    game:press("submit")
    shot(game, spec.folder, "result")
    game:show_stats(function() end)
    shot(game, spec.folder, "stats")
    UIManager:close(game)
end
os.exit(0)
