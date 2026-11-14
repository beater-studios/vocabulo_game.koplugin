-- The screens around the game, laid out on a Canvas: title, statistics, sharing, help, about and the message
-- shown when a screen could not be drawn. They read the state of the screen and call its actions.
local Canvas = require("vocabulo_game/ui/canvas")
local Engine = require("vocabulo_game/engine")
local Parts = require("vocabulo_game/ui/parts")
local Words = require("vocabulo_game/words")

local BLACK, DARK, MID, GRAY, LIGHT, PALE, WHITE =
    Canvas.BLACK, Canvas.DARK, Canvas.MID, Canvas.GRAY, Canvas.LIGHT, Canvas.PALE, Canvas.WHITE
local SANS, SANS_BOLD, SERIF_BOLD, SERIF_ITALIC = Canvas.SANS, Canvas.SANS_BOLD, Canvas.SERIF_BOLD, Canvas.SERIF_ITALIC

local Pages = {}

local LOGO = { "v", "o", "c", "á", "b", "u", "l", "o" }
local LOGO_MARKS = { Engine.CORRECT, Engine.ABSENT, Engine.PRESENT, Engine.CORRECT, Engine.ABSENT, Engine.PRESENT,
    Engine.ABSENT, Engine.CORRECT }

local function language_options(screen)
    local options = {}
    for i, code in ipairs(Words.LANGUAGES) do
        options[i] = { label = screen:language_name(code), value = code }
    end
    return options
end

local function length_options()
    local options = {}
    for i, length in ipairs(Words.LENGTHS) do
        options[i] = { label = tostring(length), value = length }
    end
    return options
end

-- A card of the title menu: an icon, a name and a line about its state.
local function menu_card(c, screen, x0, y0, x1, y1, icon, title, note, action, id)
    c:box(x0, y0, x1, y1, { border = BLACK, width = 2, radius = 12 })
    Parts.icon(c, screen.plugin_dir, icon, x0 + 30, (y0 + y1) / 2, 24)
    c:text(x0 + 56, y0 + 22, title, SANS_BOLD, 17, { middle = true, room = x1 - x0 - 66, name = "menu card" })
    c:text(x0 + 56, y0 + 48, note, SANS, 12, { middle = true, color = DARK, room = x1 - x0 - 66, name = "menu card note" })
    c:hit(x0, y0, x1, y1, action, id)
end

function Pages.title(screen, c)
    local t = screen:strings()
    Parts.tile_row(c, 40, 56, 6, #LOGO, LOGO, LOGO_MARKS)
    c:text(300, 116, t.tagline, SERIF_ITALIC, 15, { anchor = "center", color = DARK, room = 552, name = "tagline" })

    -- The word of the day, as the main action.
    local today = Engine.today()
    local saved = screen:saved_game(today)
    local stats = screen:stats_for(screen:config_key())
    c:box(24, 150, 576, 316, { fill = BLACK, radius = 16 })
    c:text(48, 170, t.daily_title, SERIF_BOLD, 24, { color = WHITE, room = 380, name = "daily card" })
    local combo = string.format(t.combo, screen:language_name(screen.lang), screen.length)
    c:text(48, 206, string.format(t.daily_number, today) .. " · " .. combo, SANS, 14, { color = LIGHT, room = 380, name = "daily card" })
    local streak = Engine.current_streak(stats, today)
    if streak > 0 then
        Parts.icon(c, screen.plugin_dir, "flame_white", 56, 240, 18)
        c:text(70, 240, string.format(t.streak_line, streak), SANS_BOLD, 13, { middle = true, color = WHITE, room = 340, name = "daily card" })
    end
    local rows = {}
    if saved then
        local key = Engine.plain(saved.answer, screen.lang)
        for i, guess in ipairs(saved.guesses) do
            rows[i] = Engine.evaluate(guess, key)
        end
    end
    local length = screen.length
    local cell = math.floor((106 - (length - 1) * 4) / length)
    Parts.mini_grid(c, 552 - (length * cell + (length - 1) * 4), 168, cell, 4, rows, length, Engine.ATTEMPTS, true)
    local label = t.play
    if saved and saved.finished then
        label = t.see_result
    elseif saved and #saved.guesses > 0 then
        label = string.format(t.continue_attempt, #saved.guesses + 1, Engine.ATTEMPTS)
    end
    c:box(48, 264, 360, 300, { fill = WHITE, radius = 18 })
    c:text(204, 282, label .. "  ›", SANS_BOLD, 14, { anchor = "center", middle = true, room = 296, name = "daily button" })
    c:hit(24, 150, 576, 316, function() screen:start_game() end, "play")

    Parts.section(c, 48, 334, t.language)
    Parts.segmented(c, 24, 352, 576, 396, language_options(screen), screen.lang, function(value) screen:choose("lang", value) end, 15, "lang")
    Parts.section(c, 48, 414, t.letters)
    Parts.segmented(c, 24, 432, 576, 476, length_options(), screen.length, function(value) screen:choose("length", value) end, 17, "length")

    local free = screen.free_games[screen:config_key()]
    local free_note = (free and not free.finished and #free.guesses > 0) and t.free_note_progress or t.free_note_new
    local stats_note = stats.played > 0 and string.format(t.stats_note, math.floor(stats.won * 100 / stats.played + 0.5)) or t.stats_note_empty
    menu_card(c, screen, 24, 500, 294, 570, "shuffle", t.free_play, free_note, function() screen:start_free_game() end, "free")
    menu_card(c, screen, 306, 500, 576, 570, "bars", t.stats, stats_note, function() screen:show_stats(function() screen:show_title() end) end, "stats")
    menu_card(c, screen, 24, 582, 294, 652, "question", t.help, t.help_note, function() screen:show_help(function() screen:show_title() end) end, "help")
    menu_card(c, screen, 306, 582, 576, 652, "info", t.about, string.format(t.version, screen.meta.version), function() screen:show_about() end, "about")
    Parts.button(c, 200, 674, 400, 718, t.exit, { icon = "exit", plugin_dir = screen.plugin_dir, size = 15,
        action = function() screen:close() end, id = "exit" })
    c:text(300, 756, t.next_word, SANS, 12, { anchor = "center", color = MID, room = 552, name = "footer" })
end

function Pages.stats(screen, c)
    local t = screen:strings()
    Parts.header(c, { title = t.stats, back_label = t.back, back = function() screen.page_back() end })
    local lang, length = screen.stats_lang, screen.stats_length
    Parts.segmented(c, 24, 84, 400, 120, language_options(screen), lang, function(value) screen:choose_stats("lang", value) end, 13, "stats_lang")
    Parts.segmented(c, 412, 84, 576, 120, length_options(), length, function(value) screen:choose_stats("length", value) end, 14, "stats_length")
    local key = lang .. "_" .. length
    local stats = screen:stats_for(key)
    local today = Engine.today()
    local rate = stats.played > 0 and math.floor(stats.won * 100 / stats.played + 0.5) or 0
    local numbers = {
        { tostring(stats.played), t.played_short }, { rate .. "%", t.rate_short },
        { tostring(Engine.current_streak(stats, today)), t.streak_short }, { tostring(stats.best_streak), t.best_short },
    }
    for i, number in ipairs(numbers) do
        local x0 = 24 + (i - 1) * 140
        Parts.number_box(c, x0, 138, x0 + 132, 200, number[1], number[2])
    end
    Parts.section(c, 24, 216, t.distribution)
    Parts.distribution(c, 24, 238, 576, stats.distribution, stats.last_attempts, 20, 6)

    -- The last four weeks, a row per week from Sunday, ending with this week.
    Parts.section(c, 24, 406, t.last_weeks)
    local history = screen.history[key] or {}
    local cell, gap, row_h = 62, 14, 34
    local x0 = (600 - (7 * cell + 6 * gap)) / 2
    for col = 1, 7 do
        c:text(x0 + (col - 1) * (cell + gap) + cell / 2, 438, t.weekdays[col], SANS_BOLD, 12,
            { anchor = "center", middle = true, color = DARK })
    end
    local weekday = os.date("*t").wday
    local first = today - (weekday - 1) - 21
    for i = 0, 27 do
        local day = first + i
        if day <= today then
            local x = x0 + (i % 7) * (cell + gap)
            local y = 452 + math.floor(i / 7) * (row_h + 8)
            local mark = history[day]
            if mark == "w" then
                c:box(x, y, x + cell, y + row_h, { fill = BLACK, radius = 6 })
            elseif mark == "l" then
                c:box(x, y, x + cell, y + row_h, { fill = GRAY, border = BLACK, width = 2, radius = 6 })
            elseif day == today then
                c:box(x, y, x + cell, y + row_h, { fill = WHITE, border = BLACK, width = 3, radius = 6 })
                c:text(x + cell / 2, y + row_h / 2, t.today, SANS_BOLD, 11, { anchor = "center", middle = true, room = cell - 6, name = "today" })
            else
                c:box(x, y, x + cell, y + row_h, { fill = WHITE, border = PALE, width = 2, radius = 6 })
            end
        end
    end
    local legend = { { "w", t.day_won }, { "l", t.day_lost }, { "-", t.day_none } }
    for i, item in ipairs(legend) do
        local x = 60 + (i - 1) * 170
        if item[1] == "w" then
            c:box(x, 630, x + 18, 648, { fill = BLACK, radius = 4 })
        elseif item[1] == "l" then
            c:box(x, 630, x + 18, 648, { fill = GRAY, border = BLACK, width = 2, radius = 4 })
        else
            c:box(x, 630, x + 18, 648, { fill = WHITE, border = PALE, width = 2, radius = 4 })
        end
        c:text(x + 26, 639, item[2], SANS, 13, { middle = true, room = 136, name = "legend" })
    end
    local free = screen:free_stats_for(key)
    c:box(24, 676, 576, 756, { border = BLACK, width = 2, radius = 12 })
    Parts.icon(c, screen.plugin_dir, "shuffle", 54, 716, 24)
    c:text(80, 700, t.free_play, SANS_BOLD, 16, { middle = true, room = 480, name = "free card" })
    c:text(80, 728, string.format(t.free_summary, free.played, free.won), SANS, 13, { middle = true, color = DARK, room = 480, name = "free card" })
end

function Pages.share(screen, c)
    local t = screen:strings()
    local engine = screen.engine
    Parts.header(c, { title = t.share, subtitle = t.daily_title .. " · " .. string.format(t.daily_number, engine.day),
        back_label = t.back, back = function() screen.page_back() end })
    local text = engine:share_text(t.share_title)
    c:box(24, 92, 576, 360, { border = BLACK, width = 2, radius = 16 })
    c:text(300, 122, text:match("^[^\n]*"), SERIF_BOLD, 18, { anchor = "center", middle = true, room = 520, name = "share line" })
    local length, cell, gap = engine.length, 30, 6
    if length * (cell + gap) - gap > 500 then
        cell = (500 - (length - 1) * gap) / length
    end
    Parts.mini_grid(c, 300 - (length * (cell + gap) - gap) / 2, 148, cell, gap, engine.results, length, #engine.results, false)
    c:text(300, 330, t.share_hint, SERIF_ITALIC, 14, { anchor = "center", middle = true, color = DARK, room = 520, name = "share hint" })
    local QRWidget = require("ui/widget/qrwidget")
    local size = c:px(260)
    local qr = QRWidget:new{ text = text, width = size, height = size }
    local shown = qr:getSize()
    c:widget(qr, 300 - shown.w / c.s / 2, 520 - shown.h / c.s / 2)
    c:paragraph(60, 670, 480, t.qr_note, SANS, 14, { align = "center", color = DARK, room = 110, name = "qr note" })
end

local function step(c, y, number, title, text)
    c:circle(44, y + 12, 14, { fill = BLACK })
    c:text(44, y + 12, tostring(number), SANS_BOLD, 14, { anchor = "center", middle = true, color = WHITE })
    c:text(72, y + 12, title, SERIF_BOLD, 17, { middle = true, room = 500, name = "help step" })
    return c:paragraph(72, y + 32, 500, text, SANS, 14, { color = DARK })
end

function Pages.help(screen, c)
    local t = screen:strings()
    Parts.header(c, { title = t.help, back_label = t.back, back = function() screen.page_back() end })
    local y = step(c, 84, 1, t.help_1_title, t.help_1_text)
    y = step(c, y + 12, 2, t.help_2_title, t.help_2_text)
    local guess = Engine.split(t.help_guess)
    Parts.tile_row(c, y + 6, 54, 8, #guess, guess, Engine.evaluate(t.help_guess, t.help_answer))
    c:text(300, y + 66, string.format(t.help_example, Engine.upper(t.help_answer)), SERIF_ITALIC, 13,
        { anchor = "center", color = DARK, room = 520, name = "help example" })
    y = y + 94
    for _, row in ipairs({ { Engine.CORRECT, t.color_correct }, { Engine.PRESENT, t.color_present }, { Engine.ABSENT, t.color_absent } }) do
        Parts.tile(c, 72, y, 28, "", row[1], { radius = 4 })
        c:text(112, y + 14, row[2], SANS, 14, { middle = true, room = 464, name = "help color" })
        y = y + 36
    end
    y = step(c, y + 6, 3, t.help_3_title, t.help_3_text)
    local plain, accented = Engine.split(t.help_plain), Engine.split(t.help_accented)
    Parts.tile_row(c, y + 6, 44, 6, #plain, plain, nil, { typed = true })
    c:text(300, y + 56, t.help_becomes, SERIF_ITALIC, 13, { anchor = "center", color = DARK, room = 300, name = "help example" })
    local marks = {}
    for i = 1, #accented do
        marks[i] = Engine.CORRECT
    end
    Parts.tile_row(c, y + 78, 44, 6, #accented, accented, marks)
    step(c, y + 134, 4, t.help_4_title, t.help_4_text)
end

function Pages.about(screen, c)
    local t = screen:strings()
    local meta = screen.meta
    Parts.header(c, { title = t.about, back_label = t.back, back = function() screen:show_title() end })
    c:image(screen.plugin_dir .. "/assets/icon.png", 252, 86, 96, 96)
    c:text(300, 210, t.name, SERIF_BOLD, 26, { anchor = "center", middle = true })
    c:text(300, 238, string.format(t.about_line, meta.version, meta.author), SERIF_ITALIC, 14,
        { anchor = "center", middle = true, color = DARK, room = 552, name = "about line" })
    c:text(300, 260, (meta.website:gsub("^https?://", ""):gsub("/$", "")), SANS, 13, { anchor = "center", middle = true, color = DARK })
    local items = {
        { t.source_title, (meta.homepage:gsub("^https?://", "")) },
        { t.words_title, t.sources },
        { t.license_title, t.license },
        { t.warranty_title, t.warranty },
    }
    -- Each card is as tall as its text, with the same room above and below.
    local y = 290
    for _, item in ipairs(items) do
        local text_h = c:measure_paragraph(item[2], SANS, 13, 520)
        local height = 14 + 20 + 4 + text_h + 14
        c:box(24, y, 576, y + height, { border = BLACK, width = 2, radius = 12 })
        c:text(40, y + 24, item[1], SANS_BOLD, 15, { middle = true, room = 520, name = "about card" })
        c:paragraph(40, y + 38, 520, item[2], SANS, 13, { color = DARK })
        y = y + height + 10
    end
end

-- Only a way back, without whatever failed to draw.
function Pages.error(screen, c, back)
    local t = screen:strings()
    Parts.back_pill(c, t.back, back)
    c:paragraph(40, 360, 520, t.draw_failed, SERIF_ITALIC, 17, { align = "center" })
end

return Pages
