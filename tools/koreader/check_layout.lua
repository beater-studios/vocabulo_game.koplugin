-- Plays every combination of language and length through taps, in every interface language, and checks that
-- each screen fits: no text wider or taller than its room (the Canvas notes those), nothing below the screen and
-- every tap area inside it. Also checks the version on the About screen, a game resumed in a new screen, the
-- sequence of refresh modes, the Back key and a failure while laying out or painting.
-- Run at four sizes with tools/koreader/check_all_sizes.sh.
local plugin_dir = assert(os.getenv("PLUGIN_DIR"))
local out_dir = assert(os.getenv("OUTPUT_DIR"))

require("setupkoenv")
local DataStorage = require("datastorage")
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
G_reader_settings:saveSetting("language", "pt_BR")
package.path = plugin_dir .. "/?.lua;" .. package.path

local Device = require("device")
local Screen = Device.screen
require("document/canvascontext"):init(Device)
local UIManager = require("ui/uimanager")
UIManager:init()
local Canvas = require("vocabulo_game/ui/canvas")
local Engine = require("vocabulo_game/engine")
local GameScreen = require("vocabulo_game/ui/screen")
local GameView = require("vocabulo_game/ui/game_view")
local Words = require("vocabulo_game/words")
local meta = dofile(plugin_dir .. "/_meta.lua")

local problems = 0
local function problem(text)
    problems = problems + 1
    print("PROBLEM: " .. text)
end

local function shot(name)
    UIManager:forceRePaint()
    Screen.bb:writePNG(out_dir .. "/" .. name .. ".png")
end

-- What the Canvas noted, the height and the tap areas of the screen shown now.
local function check_screen(game, name)
    for _, text in ipairs(game.layout_problems or {}) do
        problem(name .. ": " .. text)
    end
    if game.content_height > Screen:getHeight() then
        problem(name .. ": taller than the screen (" .. game.content_height .. ")")
    end
    for _, hit in ipairs(game.canvas.hits) do
        local r = hit.rect
        if r.x < 0 or r.y < 0 or r.x + r.w > Screen:getWidth() + 1 or r.y + r.h > Screen:getHeight() + 1 then
            problem(name .. ": tap area off screen: " .. tostring(hit.id))
        end
    end
end

-- Painted after every tap, as on the device, so the next tap finds the screen already updated.
local function tap(game, id)
    local rect = game:hit_rect(id)
    if not rect then
        problem("no tap area " .. tostring(id) .. " on " .. tostring(game.mode))
        return
    end
    game:onTap(nil, { pos = { x = rect.x + math.floor(rect.w / 2), y = rect.y + math.floor(rect.h / 2) } })
    UIManager:forceRePaint()
end

local function type_word(game, word)
    for _, letter in ipairs(Engine.split(word)) do
        tap(game, letter)
    end
    tap(game, "submit")
end

local function wrong_words(game, count)
    local list = {}
    for _, word in ipairs(game:word_lists().answers) do
        local key = Engine.plain(word, game.lang)
        if key ~= game.engine.answer_key then
            list[#list + 1] = key
        end
        if #list == count then
            break
        end
    end
    return list
end

local function shows(game, text)
    for _, shown in ipairs(game:shown_texts()) do
        if shown:find(text, 1, true) then
            return true
        end
    end
    return false
end

local game = GameScreen:new{ plugin_dir = plugin_dir }
UIManager:show(game)

-- Texts that only show in some games, measured with the font and room of the screen that shows them.
local function check_widths(lang)
    local t = game.i18n[lang]
    local c = Canvas.new(Screen:getWidth(), Screen:getHeight())
    local checks = {
        { string.format(t.won, Engine.ATTEMPTS), Canvas.SERIF_BOLD, 28, 520 },
        { string.format(t.continue_attempt, Engine.ATTEMPTS, Engine.ATTEMPTS) .. "  ›", Canvas.SANS_BOLD, 14, 296 },
        { string.format(t.attempt, Engine.ATTEMPTS, Engine.ATTEMPTS), Canvas.SANS_BOLD, 14, 518 },
        { t.short, Canvas.SANS_BOLD, 14, 518 },
        { t.unknown, Canvas.SANS_BOLD, 14, 518 },
        { string.format(t.daily_number, 9999) .. " · " .. string.format(t.combo, "Português", 7), Canvas.SERIF_ITALIC, 13, 264 },
        { string.format(t.streak_line, 999), Canvas.SANS_BOLD, 13, 340 },
        { string.format(t.free_summary, 9999, 9999), Canvas.SANS, 13, 480 },
    }
    for _, check in ipairs(checks) do
        if c:measure(check[1], check[2], check[3]) > check[4] then
            problem("text does not fit (" .. lang .. "): " .. check[1])
        end
    end
end

local played = 0
for _, ui in ipairs(Words.LANGUAGES) do
    check_widths(ui)
    for _, length in ipairs(Words.LENGTHS) do
        local label = ui .. " " .. length
        game.games, game.free_games, game.stats, game.free_stats, game.history = {}, {}, {}, {}, {}
        game.lang, game.length = ui, length
        game:show_title()
        check_screen(game, "title " .. label)
        if length == 5 then shot("title_" .. ui) end

        tap(game, "play")
        if game.mode ~= "game" then problem("Play did not open the game in " .. label) end
        check_screen(game, "game " .. label)
        local geom = game.geom
        if geom.top + Engine.ATTEMPTS * (geom.size + geom.gap) - geom.gap > GameView.KEYBOARD_TOP - 8 then
            problem("board runs into the keyboard in " .. label)
        end
        for _, word in ipairs(game:word_lists().answers) do
            for _, letter in ipairs(Engine.split(Engine.plain(word, ui))) do
                if not game:hit_rect(letter) then problem("letter without a key in " .. label .. ": " .. letter .. " in " .. word) end
            end
        end
        local wrong = wrong_words(game, Engine.ATTEMPTS)
        tap(game, Engine.split(wrong[1])[1])
        if game.engine.current[1] ~= Engine.split(wrong[1])[1] then problem("a tap did not type in " .. label) end
        tap(game, "submit")
        if game.message ~= game:strings().short or not game.message_dark then problem("no warning about missing letters in " .. label) end
        check_screen(game, "warning " .. label)
        tap(game, "backspace")
        if #game.engine.current ~= 0 then problem("delete failed in " .. label) end
        for i = 1, 3 do type_word(game, wrong[i]) end
        if #game.engine.guesses ~= 3 then problem("attempts were not recorded in " .. label) end
        if length == 5 then shot("game_" .. ui) end
        tap(game, "back")
        if game.mode ~= "title" then problem("Back did not return to the title in " .. label) end
        check_screen(game, "title with a game " .. label)
        tap(game, "play")
        type_word(game, game.engine.answer_key)
        if not game.engine:is_won() then problem("not won in " .. label) end
        check_screen(game, "won " .. label)
        if length == 5 then shot("won_" .. ui) end
        local key = game:config_key()
        if game.stats[key].won ~= 1 or game.stats[key].last_attempts ~= 4 then problem("statistics not recorded in " .. label) end
        if game.history[key][Engine.today()] ~= "w" then problem("history not recorded in " .. label) end
        played = played + 1

        tap(game, "share")
        check_screen(game, "share " .. label)
        tap(game, "back")
        if not game.engine:is_over() or game.mode ~= "game" then problem("Back from sharing did not return to the result in " .. label) end
        tap(game, "stats")
        check_screen(game, "statistics " .. label)
        if length == 5 then shot("stats_" .. ui) end
        tap(game, "stats_length:7")
        check_screen(game, "statistics 7 " .. label)
        tap(game, "back")

        game.games = {}
        game:start_game()
        for i = 1, Engine.ATTEMPTS do type_word(game, wrong[i]) end
        if not game.engine:is_over() or game.engine:is_won() then problem("a loss did not end the game in " .. label) end
        check_screen(game, "lost " .. label)
        if length == 7 then shot("lost_" .. ui) end
        game:start_game()
        if not game.engine:is_over() then problem("finished game did not come back saved in " .. label) end

        game:show_title()
        local daily_played = game.stats[key].played
        tap(game, "free")
        if not game.free_play or game.engine:is_over() then problem("free play did not start in " .. label) end
        local today_key = Engine.plain(Engine.answer_for_day(game:word_lists().answers, Engine.today()), ui)
        if game.engine.answer_key == today_key then problem("free play drew today's word in " .. label) end
        local first_free = game.engine.answer
        local guess = wrong[1] ~= game.engine.answer_key and wrong[1] or wrong[2]
        type_word(game, guess)
        game:show_title()
        tap(game, "free")
        if game.engine.answer ~= first_free or #game.engine.guesses ~= 1 then problem("free play did not come back saved in " .. label) end
        type_word(game, game.engine.answer_key)
        if not game.engine:is_won() then problem("free play was not won in " .. label) end
        check_screen(game, "free play won " .. label)
        if length == 5 then shot("free_" .. ui) end
        local free = game.free_stats[key]
        if free.won ~= 1 or free.distribution[2] ~= 1 then problem("wrong free play statistics in " .. label) end
        if game.stats[key].played ~= daily_played then problem("free play changed the streak in " .. label) end
        tap(game, "new_word")
        if game.engine:is_over() or game.engine.answer == first_free then problem("new word did not draw another one in " .. label) end
        tap(game, "help")
        check_screen(game, "help from the game " .. label)
        tap(game, "back")
        if game.mode ~= "game" or not game.free_play then problem("Back from help did not return to the game in " .. label) end
    end
    game:show_title()
    tap(game, "help")
    check_screen(game, "help " .. ui)
    shot("help_" .. ui)
    tap(game, "back")
    tap(game, "about")
    check_screen(game, "about " .. ui)
    shot("about_" .. ui)
    if not shows(game, meta.version) then problem("version missing on the About screen in " .. ui) end
    tap(game, "back")
end
print(string.format("%d combinations played through taps", played))

-- Choices are saved, and a daily game in progress comes back in a new screen opened with the same settings.
game.games, game.lang, game.length = {}, "es", 6
game:save()
game:start_game()
local first_guess = wrong_words(game, 1)[1]
type_word(game, first_guess)
local resumed = GameScreen:new{ plugin_dir = plugin_dir }
UIManager:show(resumed)
if resumed.lang ~= "es" or resumed.length ~= 6 then problem("language and length did not come back in a new screen") end
resumed:start_game()
if #resumed.engine.guesses ~= 1 or resumed.engine.guesses[1] ~= first_guess or resumed.engine.answer ~= game.engine.answer then
    problem("game in progress did not come back in a new screen")
end

-- Refresh modes: a new layout flashes, a change inside it does not, the 9th change in a row flashes, and
-- the end of a game flashes. Nothing asks for "partial", which KOReader counts towards its own flashes.
local real_set_dirty = UIManager.setDirty
local log = {}
UIManager.setDirty = function(_, widget, refresh)
    if widget == resumed then
        log[#log + 1] = type(refresh) == "function" and (refresh()) or refresh
    end
end
local function modes(action)
    log = {}
    action()
    return table.concat(log, ",")
end
local function expect(name, actual, wanted)
    if actual ~= wanted then problem(string.format("refresh in %s: %s, expected %s", name, actual, wanted)) end
end
resumed.games = {}
resumed:show_help(function() end)
expect("title screen", modes(function() resumed:show_title() end), "full")
local changes = {}
for i = 1, 9 do
    local length = Words.LENGTHS[i % 3 + 1]
    changes[i] = modes(function() tap(resumed, "length:" .. length) end)
end
expect("changing options", table.concat(changes, ","), "ui,ui,ui,ui,ui,ui,ui,ui,full")
expect("opening a game", modes(function() tap(resumed, "play") end), "full")
local wrong = wrong_words(resumed, 1)
local letters = string.rep("ui,", resumed.length)
expect("typing and sending", modes(function() type_word(resumed, wrong[1]) end), letters .. "ui")
expect("a word not in the list", modes(function()
    for _ = 1, resumed.length do tap(resumed, "z") end
    tap(resumed, "submit")
end), letters .. "ui")
expect("typing after a warning", modes(function() tap(resumed, "backspace") end), "ui,ui")
for _ = 2, resumed.length do tap(resumed, "backspace") end
expect("win", modes(function() type_word(resumed, resumed.engine.answer_key) end), letters .. "full")
expect("page", modes(function() tap(resumed, "stats") end), "full")
expect("statistics of another length", modes(function() tap(resumed, "stats_length:7") end), "ui")
UIManager.setDirty = real_set_dirty

-- A failure while laying out shows a message with a way back; one while painting does too, and then only the
-- way back answers.
local broken = GameScreen:new{ plugin_dir = plugin_dir }
UIManager:show(broken)
broken.games = {}
local real_layout = GameView.layout_play
GameView.layout_play = function() error("planted layout failure") end
broken:start_game()
if broken.mode ~= "error" then problem("a layout failure was not handled") end
shot("layout_failed")
tap(broken, "back")
if broken.mode ~= "title" then problem("Back did not work after a layout failure") end
GameView.layout_play = real_layout
broken:start_game()
local real_paint = Canvas.paint
local planted = broken.canvas
Canvas.paint = function(c, ...)
    if c == planted then error("planted paint failure") end
    return real_paint(c, ...)
end
local full_after_failure = false
local real_dirty = UIManager.setDirty
UIManager.setDirty = function(manager, widget, refresh, ...)
    if widget == broken and refresh == "full" then full_after_failure = true end
    return real_dirty(manager, widget, refresh, ...)
end
UIManager:forceRePaint()
UIManager:_checkTasks()
UIManager.setDirty = real_dirty
if not broken.paint_failed then problem("a painting failure was not handled") end
if not full_after_failure then problem("a painting failure did not ask for a full refresh, so the message may not reach the screen") end
shot("paint_failed")
local before = #broken.engine.current
local key_rect = planted:hit_by_id("a").rect
broken:onTap(nil, { pos = { x = key_rect.x + 2, y = key_rect.y + 2 } })
if #broken.engine.current ~= before then problem("a key answered with painting failing") end
tap(broken, "back")
if broken.mode ~= "title" then problem("Back did not work with painting failing") end
Canvas.paint = real_paint
UIManager:close(broken)

-- A title screen that fails leaves a way out of the game, and Back closes it instead of failing again.
local Pages = require("vocabulo_game/ui/pages")
local real_title = Pages.title
Pages.title = function() error("planted title failure") end
local stuck = GameScreen:new{ plugin_dir = plugin_dir }
UIManager:show(stuck)
if stuck.mode ~= "error" then problem("a title failure was not handled") end
tap(stuck, "back")
if UIManager:isWidgetShown(stuck) then problem("Back did not close the game after a title failure") end
Pages.title = real_title

-- The help page from a game goes back to the same game, with the letters being typed.
local helped = GameScreen:new{ plugin_dir = plugin_dir }
UIManager:show(helped)
helped.games = {}
helped:start_game()
local typed = Engine.split(wrong_words(helped, 1)[1])
tap(helped, typed[1])
tap(helped, typed[2])
tap(helped, "help")
tap(helped, "back")
if helped.mode ~= "game" or #helped.engine.current ~= 2 then problem("Back from help lost the letters being typed") end
UIManager:close(helped)

-- Free play wins saved before the attempts were counted stay out of the average.
local upgraded = GameScreen:new{ plugin_dir = plugin_dir }
UIManager:show(upgraded)
upgraded.free_games, upgraded.lang, upgraded.length = {}, "en", 5
upgraded.free_stats.en_5 = { played = 10, won = 8, distribution = {} }
upgraded:start_free_game()
type_word(upgraded, upgraded.engine.answer_key)
if not shows(upgraded, "1.0") then problem("free play average counts wins from before the attempts were saved") end
UIManager:close(upgraded)

-- Back goes back one screen and closes from the title; KOReader's Close closes, except before a shutdown.
local back = GameScreen:new{ plugin_dir = plugin_dir }
UIManager:show(back)
back:start_game()
back:onBack()
if back.mode ~= "title" or not UIManager:isWidgetShown(back) then problem("Back in the game did not return to the title") end
back:show_help(function() back:show_title() end)
back:onBack()
if back.mode ~= "title" then problem("Back on the help page did not return to the title") end
back:onClose({ keep_screensaver = true })
if not UIManager:isWidgetShown(back) then problem("Close before a shutdown closed the window") end
back:onBack()
if UIManager:isWidgetShown(back) then problem("Back on the title did not close the game") end
local closing = GameScreen:new{ plugin_dir = plugin_dir }
UIManager:show(closing)
closing:start_game()
closing:onClose()
if UIManager:isWidgetShown(closing) then problem("KOReader's Close did not close the window") end

print("problems: " .. problems)
os.exit(problems == 0 and 0 or 1)
