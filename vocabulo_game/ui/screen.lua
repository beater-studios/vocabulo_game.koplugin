-- The game window. Every screen is laid out on a Canvas (ui/canvas.lua) in the units of the mockups and painted
-- by this one widget: the title and the pages in ui/pages.lua, the board and the result in ui/game_view.lua.
local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local Canvas = require("vocabulo_game/ui/canvas")
local Engine = require("vocabulo_game/engine")
local GameView = require("vocabulo_game/ui/game_view")
local Pages = require("vocabulo_game/ui/pages")
local Portrait = require("vocabulo_game/portrait")
local Refresh = require("vocabulo_game/refresh")
local State = require("vocabulo_game/state")
local Words = require("vocabulo_game/words")

local Device_screen = Device.screen

local LANGUAGE_NAMES = { pt = "Português", en = "English", es = "Español" }
local RECENT_FREE_WORDS = 30
local UPCOMING_DAILY_WORDS = 30

local function load_table(path)
    local chunk = assert(loadfile(path))
    setfenv(chunk, {})
    return chunk()
end

local function default_language()
    local code = G_reader_settings and G_reader_settings:readSetting("language") or ""
    local prefix = code:sub(1, 2):lower()
    return LANGUAGE_NAMES[prefix] and prefix or "en"
end

local Screen = InputContainer:extend{
    name = "vocabulo_game_screen",
    covers_fullscreen = true,
    stop_events_propagation = true,
    plugin_dir = ".",
}

-- The layout only fits portrait.
function Screen:init()
    Portrait.open(self, self.setup)
end

function Screen:setup()
    if Device:hasKeys() then
        self.key_events.Back = { { Device.input.group.Back } }
    end
    -- Screens are rebuilt whole, so up to 8 updates without a flash, then a full one against ghosting.
    self.refresh = Refresh.new(8)
    math.randomseed(os.time())
    self.dimen = Geom:new{ x = 0, y = 0, w = Device_screen:getWidth(), h = Device_screen:getHeight() }
    self.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
    self.cache = {}
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/vocabulo_game.lua")
    self.meta = load_table(self.plugin_dir .. "/_meta.lua")
    self.i18n = load_table(self.plugin_dir .. "/data/i18n.lua")
    local saved = State.load(function(name) return self.settings:readSetting(name) end, logger.warn)
    self.lang = saved.lang or default_language()
    self.length = saved.length
    self.games = saved.games
    self.stats = saved.stats
    self.free_games = saved.free_games
    self.free_stats = saved.free_stats
    self.free_recent = saved.free_recent
    self.history = saved.history
    self:show_title()
end

-- Shown by the menu when the screen could not open. The texts file may be what failed, so English is the
-- last resort.
function Screen.open_failed_text(plugin_dir)
    local ok, i18n = pcall(load_table, plugin_dir .. "/data/i18n.lua")
    if not ok or type(i18n) ~= "table" then
        return "Vocábulo could not open. Try restarting KOReader."
    end
    local settings_ok, settings = pcall(LuaSettings.open, LuaSettings, DataStorage:getSettingsDir() .. "/vocabulo_game.lua")
    local lang = settings_ok and settings:readSetting("lang") or default_language()
    local texts = i18n[lang] or i18n.en
    return texts.open_failed
end

function Screen:strings()
    return self.i18n[self.lang]
end

function Screen:language_name(code)
    return LANGUAGE_NAMES[code] or code
end

function Screen:config_key()
    return self.lang .. "_" .. self.length
end

function Screen:stats_for(key)
    return self.stats[key] or Engine.new_stats()
end

function Screen:free_stats_for(key)
    return self.free_stats[key] or { played = 0, won = 0, distribution = {} }
end

-- Only the lists of the combination in play stay in memory.
function Screen:word_lists()
    local key = self:config_key()
    if not self.lists or self.lists.key ~= key then
        -- Dropped first, so the old and the new lists are not both held while loading.
        self.lists = nil
        self.lists = {
            key = key,
            answers = Words.load_answers(self.plugin_dir, self.lang, self.length),
            is_valid = Words.load_validator(self.plugin_dir, self.lang, self.length),
        }
    end
    return self.lists
end

function Screen:save()
    self.settings:saveSetting("lang", self.lang)
    self.settings:saveSetting("length", self.length)
    self.settings:saveSetting("games", self.games)
    self.settings:saveSetting("stats", self.stats)
    self.settings:saveSetting("free_games", self.free_games)
    self.settings:saveSetting("free_stats", self.free_stats)
    self.settings:saveSetting("free_recent", self.free_recent)
    self.settings:saveSetting("history", self.history)
    self.settings:flush()
end

function Screen:saved_game(day)
    local saved = self.games[self:config_key()]
    if saved and saved.day == (day or Engine.today()) then
        return saved
    end
end

-- --- Showing a screen ---

-- Where Back goes from the message shown when a screen fails: the title, or out of the game when the title
-- itself is what failed, so the window can always be closed.
function Screen:error_back()
    if self.mode == "title" then
        return function() self:close() end
    end
    return function() self:show_title() end
end

-- Lays out a screen on a new canvas. A layout that fails shows a message with a way back instead.
function Screen:build(layout)
    local c = Canvas.new(self.dimen.w, self.dimen.h, self.cache)
    local ok, err = pcall(layout, self, c)
    if not ok then
        logger.warn("vocabulo_game: could not lay out the screen", self.mode, err)
        c:free()
        c = Canvas.new(self.dimen.w, self.dimen.h, self.cache)
        self.failure_back = self:error_back()
        Pages.error(self, c, self.failure_back)
        return c, false
    end
    return c, true
end

function Screen:set_canvas(c)
    if self.canvas then
        self.canvas:free()
    end
    self.canvas = c
    self.paint_failed = false
    -- Read by tools/koreader/check_layout.lua.
    self.content_height = c:content_height()
    self.layout_problems = c.problems
end

-- kind names the layout for the e-ink updates: the same kind again is updated without a flash, a new kind (or
-- every ninth update) flashes.
function Screen:present(mode, kind, layout)
    self.mode = mode
    local c, ok = self:build(layout)
    if not ok then
        self.mode, kind = "error", "error"
    end
    self:set_canvas(c)
    local refresh = self.refresh:mode(kind)
    UIManager:setDirty(self, function()
        return refresh, self.dimen
    end)
end

function Screen:show_title()
    self:present("title", "title", Pages.title)
end

-- A language or length picked on the title screen.
function Screen:choose(field, value)
    self[field] = value
    self:save()
    self:show_title()
end

function Screen:show_page(kind, layout, back)
    self.page_back = back
    self:present("page", kind, layout)
end

function Screen:show_stats(back)
    self.stats_lang, self.stats_length = self.lang, self.length
    self:show_page("stats", Pages.stats, back)
end

-- A language or length picked on the statistics screen, which does not change the game settings.
function Screen:choose_stats(field, value)
    if field == "lang" then
        self.stats_lang = value
    else
        self.stats_length = value
    end
    self:present("page", "stats", Pages.stats)
end

function Screen:show_help(back)
    self:show_page("page:help", Pages.help, back)
end

function Screen:show_about()
    self:show_page("page:about", Pages.about, function() self:show_title() end)
end

function Screen:show_share(back)
    self:show_page("share", Pages.share, back)
end

function Screen:close()
    UIManager:close(self)
end

-- Every text laid out on the current screen, for the checks.
function Screen:shown_texts()
    local texts = {}
    for _, item in ipairs(self.canvas and self.canvas.items or {}) do
        if item.widget and item.widget.text then
            texts[#texts + 1] = item.widget.text
        end
    end
    return texts
end

-- The screen rectangle of a tap area by its id, for the checks and the random taps.
function Screen:hit_rect(id)
    local hit = self.canvas and self.canvas:hit_by_id(id)
    return hit and hit.rect
end

-- --- The game ---

-- The day is kept when coming back from the statistics, even if the date changed meanwhile.
function Screen:start_game(day)
    day = day or Engine.today()
    local saved = self:saved_game(day)
    local answer = saved and saved.answer or Engine.answer_for_day(self:word_lists().answers, day)
    self:open_game{ day = day, answer = answer, saved = saved }
end

function Screen:pick_free_word()
    local key = self:config_key()
    local answers = self:word_lists().answers
    local recent = self.free_recent[key] or {}
    local avoided = Engine.free_avoided(answers, self.lang, Engine.today(), UPCOMING_DAILY_WORDS, recent)
    local answer = Engine.pick_free(answers, self.lang, avoided, math.random)
    table.insert(recent, Engine.plain(answer, self.lang))
    while #recent > RECENT_FREE_WORDS do
        table.remove(recent, 1)
    end
    self.free_recent[key] = recent
    return answer
end

function Screen:start_free_game()
    local key = self:config_key()
    local saved = self.free_games[key]
    if not saved or saved.finished then
        saved = { version = State.GAME_VERSION, answer = self:pick_free_word(), guesses = {} }
        self.free_games[key] = saved
        self:save()
    end
    self:open_game{ answer = saved.answer, saved = saved, free_play = true }
end

-- Back to the game left for the help page, as it was, with the letters being typed.
function Screen:reopen_game()
    self.refresh:reset()
    self:show_game("game")
end

function Screen:open_game(opts)
    self.free_play = opts.free_play or false
    self.engine = Engine.new{
        lang = self.lang,
        length = self.length,
        day = opts.day,
        answer = opts.answer,
        is_valid = self:word_lists().is_valid,
    }
    if opts.saved then
        self.engine:restore(opts.saved)
    end
    self.message, self.message_dark = self:game_message(), false
    -- Every game opens with a full update, even a new word from the result of the last one.
    self.refresh:reset()
    self:show_game("game")
end

function Screen:show_game(kind)
    if self.engine:is_over() then
        self:present("game", "result", GameView.layout_result)
    else
        self:present("game", kind, function(screen, c)
            screen.geom = GameView.layout_play(screen, c)
        end)
    end
end

function Screen:game_message()
    return string.format(self:strings().attempt, #self.engine.guesses + 1, Engine.ATTEMPTS)
end

-- A change inside the board: only the row being typed, and the message if it changed, reach the e-ink screen.
function Screen:update_play(rows, message_changed)
    local c, ok = self:build(function(screen, canvas)
        screen.geom = GameView.layout_play(screen, canvas)
    end)
    self:set_canvas(c)
    if not ok then
        self.mode = "error"
        UIManager:setDirty(self, function() return "full", self.dimen end)
        return
    end
    for _, row in ipairs(rows) do
        local rect = GameView.row_rect(c, self.geom, row)
        UIManager:setDirty(self, function() return "ui", rect end)
    end
    if message_changed then
        local rect = GameView.message_rect(c)
        UIManager:setDirty(self, function() return "ui", rect end)
    end
end

function Screen:set_message(text, dark)
    local changed = text ~= self.message or dark ~= self.message_dark
    self.message, self.message_dark = text, dark
    return changed
end

function Screen:press(id)
    local engine = self.engine
    if not engine or engine:is_over() then
        return
    end
    if id == "submit" then
        self:submit()
        return
    end
    local changed
    if id == "backspace" then
        changed = engine:remove_letter()
    else
        changed = engine:add_letter(id)
    end
    if changed then
        -- The warning of a word not accepted goes away as soon as the player types again.
        local message_changed = self:set_message(self:game_message(), false)
        self:update_play({ #engine.guesses + 1 }, message_changed)
    end
end

-- Keeps the last days of results of a combination, enough for the statistics calendar.
local HISTORY_DAYS = 70

function Screen:record_daily(key, engine)
    local stats = self:stats_for(key)
    local before = stats.last_day
    local won = engine:is_won()
    Engine.record_result(stats, engine.day, won, #engine.guesses)
    if stats.last_day ~= before then
        stats.last_attempts = won and #engine.guesses or nil
        local history = self.history[key] or {}
        history[engine.day] = won and "w" or "l"
        for day in pairs(history) do
            if day <= engine.day - HISTORY_DAYS then
                history[day] = nil
            end
        end
        self.history[key] = history
    end
    self.stats[key] = stats
end

function Screen:record_free(key, engine)
    local stats = self:free_stats_for(key)
    stats.played = stats.played + 1
    if engine:is_won() then
        stats.won = stats.won + 1
        stats.distribution[#engine.guesses] = (stats.distribution[#engine.guesses] or 0) + 1
    end
    self.free_stats[key] = stats
end

function Screen:submit()
    local engine = self.engine
    local ok, reason = engine:submit()
    if reason == "over" then
        return
    end
    if not ok then
        local t = self:strings()
        local changed = self:set_message(reason == "short" and t.short or t.unknown, true)
        self:update_play({}, changed)
        return
    end
    local key = self:config_key()
    if self.free_play then
        self.free_games[key] = State.record(engine, engine:is_over(), false)
        if engine:is_over() then
            self:record_free(key, engine)
        end
    else
        self.games[key] = State.record(engine, engine:is_over(), true)
        if engine:is_over() then
            self:record_daily(key, engine)
        end
    end
    self:save()
    self:set_message(self:game_message(), false)
    -- The end of a game always flashes; the attempts before it count towards the next full update.
    self:show_game("game")
end

-- --- Painting and input ---

-- An error while painting would repeat on every paint and leave the screen unusable, so the screen is painted
-- protected, and after a failure only the way back answers taps.
function Screen:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    if not self.canvas then
        return
    end
    local ok, err = pcall(self.canvas.paint, self.canvas, bb, x, y)
    if ok then
        return
    end
    logger.warn("vocabulo_game: could not draw the screen", self.mode, err)
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    if not self.paint_failed then
        if self.failed_canvas then
            self.failed_canvas:free()
        end
        self.failed_canvas = Canvas.new(self.dimen.w, self.dimen.h, self.cache)
        self.failure_back = self:error_back()
        Pages.error(self, self.failed_canvas, self.failure_back)
        self.paint_failed = true
        -- The update that failed may have been a single row, so the message would not reach the e-ink screen.
        UIManager:nextTick(function()
            UIManager:setDirty(self, "full")
        end)
    end
    self.failed_canvas:paint(bb, x, y)
end

function Screen:onTap(_, ges)
    local canvas = self.paint_failed and self.failed_canvas or self.canvas
    local hit = canvas and canvas:hit_at(ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y)
    if hit then
        hit.action()
    end
    return true
end

Screen.onSetRotationMode = Portrait.ignore_rotation

-- The device Back key goes back one screen, and closes the game from the title screen.
function Screen:onBack()
    if self.paint_failed or self.mode == "error" then
        self.failure_back()
    elseif self.mode == "game" then
        self:show_title()
    elseif self.mode == "page" then
        self.page_back()
    else
        self:close()
    end
    return true
end

-- KOReader sends Close to every window before it quits (USB mode on a Kobo, closing the window on a computer).
function Screen:onClose(arg)
    if not (arg and arg.keep_screensaver) then
        self:close()
    end
end

-- The sleep screen covered everything, so the next update clears the ghosting.
function Screen:onResume()
    self.refresh:reset()
end

function Screen:onCloseWidget()
    if self.canvas then
        self.canvas:free()
    end
    if self.failed_canvas then
        self.failed_canvas:free()
    end
    self.canvas, self.failed_canvas = nil, nil
    Canvas.free_cache(self.cache)
    self.cache = {}
    self.lists = nil
    Portrait.close(self)
    UIManager:setDirty(nil, "full")
end

return Screen
