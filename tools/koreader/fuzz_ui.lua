-- Random touches through the real screens: the title in each language, the word of the day in each
-- language and length, and free play in each language. In a game, one step in four types a word from the
-- lists on the game keyboard (now and then the answer), so games reach their end.
-- Run: KOREADER_DIR=<desktop KOReader> tools/koreader/run_headless.sh tools/koreader/fuzz_ui.lua
local Fuzz = dofile(os.getenv("PLUGIN_DIR") .. "/tools/koreader/fuzz.lua")
local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local Engine = require("vocabulo_game/engine")
local GameScreen = require("vocabulo_game/ui/screen")
local SavedState = require("vocabulo_game/saved_state")
local Words = require("vocabulo_game/words")

-- A fixed day, so a run repeats the same word of the day whatever the date.
Engine.today = function() return 312 end

local settings_file = DataStorage:getSettingsDir() .. "/vocabulo_game.lua"
local taps, modes = 0, {}
local real_tap = GameScreen.onTap
GameScreen.onTap = function(...)
    taps = taps + 1
    return real_tap(...)
end

local screen = GameScreen:new{ plugin_dir = Fuzz.plugin_dir }
local fuzz = Fuzz.new{ screen = screen }

-- Every run starts from no saved state and the same free play draws.
local function fresh_screen(f, lang, length)
    if UIManager:isWidgetShown(f.screen) then
        UIManager:close(f.screen)
    end
    SavedState.remove_file(settings_file)
    local new = GameScreen:new{ plugin_dir = Fuzz.plugin_dir }
    math.randomseed(f.seed)
    new.lang, new.length = lang, length or Words.LENGTHS[1]
    new:save()
    UIManager:show(new)
    return new
end

-- The screen catches its own layout and painting errors and shows a message instead, so the module would never
-- see them: a step that leaves the screen there is an error.
local function check_screen(f)
    if f.screen.mode == "error" or f.screen.paint_failed then
        error("the screen could not be drawn (mode " .. tostring(f.screen.mode) .. "), see the log above")
    end
end

local function tap_rect(f, rect)
    f:tap(rect.x + math.floor(rect.w / 2), rect.y + math.floor(rect.h / 2))
end


local function game_step(f)
    local game = f.screen
    modes[game.mode] = true
    if game.mode == "game" and not game.engine:is_over() and f.random(1, 4) == 1 then
        local answers = game:word_lists().answers
        local word = f.random(1, 10) == 1 and game.engine.answer or answers[f.random(1, #answers)]
        for _, letter in ipairs(Engine.split(Engine.plain(word, game.lang))) do
            tap_rect(f, game:hit_rect(letter))
        end
        tap_rect(f, game:hit_rect("submit"))
    else
        f:touch()
    end
    check_screen(f)
end

local function left_game(f)
    return f.screen.mode ~= "game"
end

for _, lang in ipairs(Words.LANGUAGES) do
    fuzz:run{
        label = "title " .. lang,
        setup = function(f)
            local new = fresh_screen(f, lang)
            new:show_title()
            return new
        end,
        step = function(f)
            modes[f.screen.mode] = true
            f:touch()
            check_screen(f)
        end,
    }
end
for _, lang in ipairs(Words.LANGUAGES) do
    for _, length in ipairs(Words.LENGTHS) do
        fuzz:run{
            label = string.format("daily %s %d", lang, length),
            setup = function(f)
                local new = fresh_screen(f, lang, length)
                new:start_game()
                return new
            end,
            again = left_game,
            step = game_step,
        }
    end
end
for _, lang in ipairs(Words.LANGUAGES) do
    fuzz:run{
        label = "free " .. lang,
        setup = function(f)
            local new = fresh_screen(f, lang)
            new:start_free_game()
            return new
        end,
        again = left_game,
        step = game_step,
    }
end

local visited = {}
for mode in pairs(modes) do visited[#visited + 1] = mode end
table.sort(visited)
print(string.format("%d taps reached the game screen; screens visited: %s", taps, table.concat(visited, ", ")))
fuzz:finish()
