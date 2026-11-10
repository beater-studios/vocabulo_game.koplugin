local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LuaSettings = require("luasettings")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")

local Engine = require("vocabulo_game/engine")
local GameView = require("vocabulo_game/ui/game_view")
local Portrait = require("vocabulo_game/portrait")
local Refresh = require("vocabulo_game/refresh")
local State = require("vocabulo_game/state")
local Words = require("vocabulo_game/words")

local Device_screen = Device.screen

local SERIF = "noto/NotoSerif-Regular.ttf"
local SERIF_BOLD = "noto/NotoSerif-Bold.ttf"
local SERIF_ITALIC = "noto/NotoSerif-Italic.ttf"
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
    self.width, self.height = self.dimen.w, self.dimen.h
    self.margin = self:scaled(20)
    self.text_width = self.width - 2 * self.margin
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

function Screen:scaled(value)
    return Device_screen:scaleBySize(value)
end

function Screen:strings()
    return self.i18n[self.lang]
end

function Screen:config_key()
    return self.lang .. "_" .. self.length
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
    self.settings:flush()
end

-- kind names the layout: the same kind again is a change inside it and is updated without a flash.
function Screen:set_widget(widget, kind)
    if self[1] then
        self[1]:free()
    end
    -- Read by tools/koreader/check_layout.lua to catch pages taller than the screen.
    self.content_height = widget:getSize().h
    self[1] = widget
    local mode = self.refresh:mode(kind)
    UIManager:setDirty(self, function()
        return mode, self.dimen
    end)
end

function Screen:set_page(group, kind)
    self:set_widget(FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        width = self.width,
        height = self.height,
        group,
    }, kind)
    self.content_height = group:getSize().h
end

function Screen:centered(widget, height)
    return CenterContainer:new{
        dimen = Geom:new{ w = self.width, h = height or widget:getSize().h },
        widget,
    }
end

function Screen:text_line(text, face, size)
    return TextWidget:new{ text = text, face = Font:getFace(face, size), max_width = self.text_width }
end

function Screen:menu_button(text, callback)
    return Button:new{
        text = text,
        width = self.width - 2 * self:scaled(70),
        padding_v = self:scaled(8),
        radius = self:scaled(8),
        bordersize = self:scaled(2),
        text_font_face = "cfont",
        text_font_size = 19,
        callback = callback,
    }
end

function Screen:option_row(options, selected, on_select)
    local row = HorizontalGroup:new{ align = "center" }
    local gap = self:scaled(6)
    local width = math.floor((self.text_width - (#options - 1) * gap) / #options)
    for i, option in ipairs(options) do
        if i > 1 then
            row[#row + 1] = HorizontalSpan:new{ width = gap }
        end
        local is_selected = option.value == selected
        row[#row + 1] = Button:new{
            text = (is_selected and "• " or "") .. option.label,
            width = width,
            padding_v = self:scaled(7),
            radius = self:scaled(8),
            bordersize = is_selected and self:scaled(3) or self:scaled(1),
            text_font_face = "cfont",
            text_font_bold = is_selected,
            text_font_size = 17,
            callback = function() on_select(option.value) end,
        }
    end
    return row
end

function Screen:saved_game(day)
    local saved = self.games[self:config_key()]
    if saved and saved.day == (day or Engine.today()) then
        return saved
    end
end

function Screen:show_title()
    self.mode = "title"
    local t = self:strings()
    local group = VerticalGroup:new{ align = "center" }
    local function add(widget)
        group[#group + 1] = widget
    end
    local function space(value)
        group[#group + 1] = VerticalSpan:new{ width = self:scaled(value) }
    end

    add(self:centered(self:text_line(t.name, SERIF_BOLD, 36)))
    space(20)
    add(self:centered(self:text_line(t.language, SERIF_ITALIC, 18)))
    space(6)
    local languages = {}
    for i, code in ipairs(Words.LANGUAGES) do
        languages[i] = { value = code, label = LANGUAGE_NAMES[code] }
    end
    add(self:centered(self:option_row(languages, self.lang, function(value)
        self.lang = value
        self:save()
        self:show_title()
    end)))
    space(14)
    add(self:centered(self:text_line(t.letters, SERIF_ITALIC, 18)))
    space(6)
    local lengths = {}
    for i, length in ipairs(Words.LENGTHS) do
        lengths[i] = { value = length, label = tostring(length) }
    end
    add(self:centered(self:option_row(lengths, self.length, function(value)
        self.length = value
        self:save()
        self:show_title()
    end)))
    space(26)

    local saved = self:saved_game()
    local play_label = t.play
    if saved and saved.finished then
        play_label = t.see_result
    elseif saved and #saved.guesses > 0 then
        play_label = t.resume
    end
    local free_saved = self.free_games[self:config_key()]
    local free_label = (free_saved and not free_saved.finished and #free_saved.guesses > 0) and t.free_resume or t.free_play
    for _, item in ipairs({
        { play_label, function() self:start_game() end },
        { free_label, function() self:start_free_game() end },
        { t.stats, function() self:show_stats(function() self:show_title() end) end },
        { t.help, function() self:show_help() end },
        { t.about, function() self:show_about() end },
        { t.exit, function() UIManager:close(self) end },
    }) do
        add(self:centered(self:menu_button(item[1], item[2])))
        space(8)
    end
    self:set_page(CenterContainer:new{ dimen = Geom:new{ w = self.width, h = self.height }, group }, "title")
    self.content_height = group:getSize().h
end

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

function Screen:open_game(opts)
    self.mode = "game"
    self.free_play = opts.free_play or false
    local answer = opts.answer
    self.engine = Engine.new{
        lang = self.lang,
        length = self.length,
        day = opts.day,
        answer = answer,
        is_valid = self:word_lists().is_valid,
    }
    if opts.saved then
        self.engine:restore(opts.saved)
    end
    local answer_letters = Engine.split(answer)
    for i, letter in ipairs(answer_letters) do
        answer_letters[i] = Engine.upper(letter)
    end
    self.view = GameView:new{
        engine = self.engine,
        strings = self:strings(),
        width = self.width,
        height = self.height,
        answer_letters = answer_letters,
        free_play = self.free_play,
        on_new_word = function() self:start_free_game() end,
        on_change = function(change) self:on_game_change(change) end,
        on_back = function() self:show_title() end,
        on_share = function() self:share_result() end,
        on_stats = function() self:show_stats(function() self:start_game(opts.day) end) end,
    }
    self.view.message = self:game_message()
    -- Every game opens with a full update, even a new word from the result of the last one.
    self.refresh:reset()
    self:set_widget(self.view, "game")
end

function Screen:game_message()
    local engine = self.engine
    local t = self:strings()
    if engine:is_won() then
        return string.format(t.won, #engine.guesses)
    elseif engine:is_over() then
        return string.format(t.lost, table.concat(self.view.answer_letters))
    end
    return string.format(t.attempt, #engine.guesses + 1, Engine.ATTEMPTS)
end

function Screen:refresh_view(mode, rect)
    UIManager:setDirty(self, function()
        return mode, rect
    end)
end

function Screen:on_game_change(change)
    local view, engine = self.view, self.engine
    if change == "letter" then
        local message = self:game_message()
        if message ~= view.message then
            view.message = message
            self:refresh_view("ui", view:message_rect())
        end
        self:refresh_view("ui", view:row_rect(#engine.guesses + 1))
        return
    end
    local ok, reason = engine:submit()
    if reason == "over" then
        return
    end
    if not ok then
        local t = self:strings()
        view.message = reason == "short" and t.short or t.unknown
        self:refresh_view("ui", view:message_rect())
        return
    end
    local key = self:config_key()
    if self.free_play then
        self.free_games[key] = State.record(engine, engine:is_over(), false)
        if engine:is_over() then
            local stats = self.free_stats[key] or { played = 0, won = 0 }
            stats.played = stats.played + 1
            stats.won = stats.won + (engine:is_won() and 1 or 0)
            self.free_stats[key] = stats
        end
    else
        self.games[key] = State.record(engine, engine:is_over(), true)
        if engine:is_over() then
            self.stats[key] = Engine.record_result(self.stats[key] or Engine.new_stats(), engine.day, engine:is_won(), #engine.guesses)
        end
    end
    self:save()
    view.message = self:game_message()
    -- The end of a game always flashes; the attempts before it count towards the next full update.
    if engine:is_over() then
        self.refresh:reset()
    end
    self:refresh_view(self.refresh:mode("game"), self.dimen)
end

function Screen:share_result()
    local QRMessage = require("ui/widget/qrmessage")
    UIManager:show(QRMessage:new{ text = self.engine:share_text(self:strings().share_title) })
end

function Screen:show_page(title, items, back)
    self.mode = "page"
    self.page_back = back
    local t = self:strings()
    local group = VerticalGroup:new{ align = "center" }
    group[#group + 1] = self:centered(self:text_line(title, SERIF_BOLD, 26), self:scaled(60))
    for _, item in ipairs(items) do
        local body = VerticalGroup:new{ align = "left" }
        local inner_width = self.text_width - 2 * self:scaled(10) - 2 * self:scaled(2)
        if item.title then
            body[#body + 1] = TextBoxWidget:new{ text = item.title, face = Font:getFace(SERIF_BOLD, 18), width = inner_width }
        end
        if item.meta then
            body[#body + 1] = TextBoxWidget:new{ text = item.meta, face = Font:getFace(SERIF_ITALIC, 14), width = inner_width }
        end
        if item.text then
            body[#body + 1] = TextBoxWidget:new{ text = item.text, face = Font:getFace(SERIF, 16), width = inner_width }
        end
        group[#group + 1] = self:centered(FrameContainer:new{
            width = self.text_width,
            padding = self:scaled(10),
            bordersize = self:scaled(2),
            radius = self:scaled(8),
            background = Blitbuffer.COLOR_WHITE,
            body,
        })
        group[#group + 1] = VerticalSpan:new{ width = self:scaled(8) }
    end
    group[#group + 1] = VerticalSpan:new{ width = self:scaled(6) }
    group[#group + 1] = self:centered(self:menu_button(t.back, back))
    self:set_page(group, "page:" .. title)
end

function Screen:show_help()
    self:show_page(self:strings().help, self:strings().help_items, function() self:show_title() end)
end

local function bare_url(url)
    return (url:gsub("^https?://", ""):gsub("/$", ""))
end

function Screen:show_about()
    self:show_page(self:strings().about, self:about_items(), function() self:show_title() end)
end

function Screen:about_items()
    local t = self:strings()
    return {
        {
            title = t.name,
            meta = string.format(t.version, self.meta.version),
            text = string.format("%s\n%s\n%s", string.format(t.by, self.meta.author), bare_url(self.meta.website), self.meta.copyright),
        },
        { title = t.source_title, text = bare_url(self.meta.homepage) },
        { title = t.license_title, text = t.license },
        { title = t.sources_title, text = t.sources },
        { title = t.warranty_title, text = t.warranty },
    }
end

function Screen:show_stats(back)
    local t = self:strings()
    local stats = self.stats[self:config_key()] or Engine.new_stats()
    local win_rate = stats.played > 0 and math.floor(stats.won * 100 / stats.played + 0.5) or 0
    local lines = {
        string.format("%s: %d", t.played, stats.played),
        string.format("%s: %d%%", t.win_rate, win_rate),
        string.format("%s: %d", t.streak, Engine.current_streak(stats, Engine.today())),
        string.format("%s: %d", t.best_streak, stats.best_streak),
    }
    local free = self.free_stats[self:config_key()] or { played = 0, won = 0 }
    local bars = {}
    for attempt = 1, Engine.ATTEMPTS do
        local count = stats.distribution[attempt] or 0
        bars[attempt] = string.format("%d: %s %d", attempt, string.rep("■", math.min(count, 20)), count)
    end
    self:show_page(t.stats, {
        { title = string.format("%s · %s", LANGUAGE_NAMES[self.lang], string.format(t.letters_count, self.length)), text = table.concat(lines, "\n") },
        { title = t.distribution, text = table.concat(bars, "\n") },
        { title = t.free_play, text = string.format("%s: %d\n%s: %d", t.played, free.played, t.wins, free.won) },
    }, back)
end

Screen.onSetRotationMode = Portrait.ignore_rotation

-- The device Back key goes back one screen, and closes the game from the title screen.
function Screen:onBack()
    if self.mode == "game" then
        self:show_title()
    elseif self.mode == "page" then
        self.page_back()
    else
        UIManager:close(self)
    end
    return true
end

-- KOReader sends Close to every window before it quits (USB mode on a Kobo, closing the window on a computer).
function Screen:onClose(arg)
    if not (arg and arg.keep_screensaver) then
        UIManager:close(self)
    end
end

-- The sleep screen covered everything, so the next update clears the ghosting.
function Screen:onResume()
    self.refresh:reset()
end

function Screen:onCloseWidget()
    if self[1] then
        self[1]:free()
        self[1] = nil
    end
    self.lists = nil
    Portrait.close(self)
    UIManager:setDirty(nil, "full")
end

return Screen
