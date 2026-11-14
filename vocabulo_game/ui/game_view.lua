-- The game screens, laid out on a Canvas: the board with the keyboard while playing, and the result card over a
-- smaller board when the game is over. They read the state of the screen and call its actions.
local Canvas = require("vocabulo_game/ui/canvas")
local Engine = require("vocabulo_game/engine")
local Keyboard = require("vocabulo_game/keyboard")
local Parts = require("vocabulo_game/ui/parts")

local BLACK, DARK, MID, GRAY, LIGHT, PAPER, WHITE =
    Canvas.BLACK, Canvas.DARK, Canvas.MID, Canvas.GRAY, Canvas.LIGHT, Canvas.PAPER, Canvas.WHITE
local SANS_BOLD, SERIF_BOLD, SERIF_ITALIC = Canvas.SANS_BOLD, Canvas.SERIF_BOLD, Canvas.SERIF_ITALIC

local GameView = {}

GameView.BOARD_TOP = 124
GameView.KEYBOARD_TOP = 590
GameView.MESSAGE_TOP = 80

-- The letters shown in a row: a guess as typed, or the answer with its accents when it was found.
local function row_letters(screen, row)
    local engine = screen.engine
    local guess = engine.guesses[row]
    if guess then
        return guess == engine.answer_key and Engine.split(engine.answer) or Engine.split(guess)
    end
    if row == #engine.guesses + 1 then
        return engine.current
    end
    return {}
end

-- The size of the board tiles for a length, so 7 letters still fit the width.
function GameView.board_geometry(length)
    local gap = 8
    local size = math.min((552 - (length - 1) * gap) / length, (446 - 5 * gap) / Engine.ATTEMPTS)
    return { top = GameView.BOARD_TOP, size = size, gap = gap, length = length,
        left = 300 - (length * size + (length - 1) * gap) / 2 }
end

local function board(c, screen, geom, playing)
    local engine = screen.engine
    for row = 1, Engine.ATTEMPTS do
        local y = geom.top + (row - 1) * (geom.size + geom.gap)
        local letters = row_letters(screen, row)
        local result = engine.results[row]
        local current = playing and row == #engine.guesses + 1
        for col = 1, geom.length do
            local x = geom.left + (col - 1) * (geom.size + geom.gap)
            Parts.tile(c, x, y, geom.size, letters[col], result and result[col], {
                typed = current and letters[col] ~= nil,
                cursor = current and col == #letters + 1,
            })
        end
    end
end

local function keyboard(c, screen)
    local margin, gap, key_h, row_gap = 10, 6, 56, 8
    local key_w = (600 - 2 * margin - 9 * gap) / 10
    local action_w = key_w * 1.5
    local states = screen.engine:keyboard_states()
    for r, row in ipairs(Keyboard.rows(screen.engine.lang)) do
        local y = GameView.KEYBOARD_TOP + (r - 1) * (key_h + row_gap)
        local letters = Engine.split(row)
        local total = #letters * key_w + (#letters - 1) * gap
        if r == 3 then
            total = total + 2 * (action_w + gap)
        end
        local x = (600 - total) / 2
        if r == 3 then
            c:box(x, y, x + action_w, y + key_h, { fill = BLACK, radius = 8 })
            c:text(x + action_w / 2, y + key_h / 2, screen:strings().submit, SANS_BOLD, 13,
                { anchor = "center", middle = true, color = WHITE, room = action_w - 6, name = "send key", cache = true })
            c:hit(x, y, x + action_w, y + key_h, function() screen:press("submit") end, "submit")
            x = x + action_w + gap
        end
        for _, letter in ipairs(letters) do
            local mark = states[letter]
            local text_color = BLACK
            if mark == Engine.CORRECT then
                c:box(x, y, x + key_w, y + key_h, { fill = BLACK, radius = 8 })
                text_color = WHITE
            elseif mark == Engine.PRESENT then
                c:box(x, y, x + key_w, y + key_h, { fill = GRAY, border = BLACK, width = 2, radius = 8 })
                c:corner(x + key_w - 2, y + 2, 11, BLACK)
            elseif mark == Engine.ABSENT then
                c:box(x, y, x + key_w, y + key_h, { fill = PAPER, radius = 8 })
                text_color = LIGHT
            else
                c:box(x, y, x + key_w, y + key_h, { fill = WHITE, border = BLACK, width = 2, radius = 8 })
            end
            c:text(x + key_w / 2, y + key_h / 2 + 1, Engine.upper(letter), SERIF_BOLD, 22,
                { anchor = "center", middle = true, color = text_color, cache = true })
            c:hit(x, y, x + key_w, y + key_h, function() screen:press(letter) end, letter)
            x = x + key_w + gap
        end
        if r == 3 then
            c:box(x, y, x + action_w, y + key_h, { fill = WHITE, border = BLACK, width = 2, radius = 8 })
            Parts.icon(c, screen.plugin_dir, "backspace", x + action_w / 2, y + key_h / 2, 30)
            c:hit(x, y, x + action_w, y + key_h, function() screen:press("backspace") end, "backspace")
        end
    end
end

-- The title and subtitle of a game: the word of the day with its number, or free play.
function GameView.titles(screen)
    local t = screen:strings()
    local combo = string.format(t.combo, screen:language_name(screen.engine.lang), screen.engine.length)
    if screen.free_play then
        return t.free_play, combo
    end
    return t.daily_title, string.format(t.daily_number, screen.engine.day) .. " · " .. combo
end

function GameView.layout_play(screen, c)
    local title, subtitle = GameView.titles(screen)
    Parts.header(c, {
        title = title, subtitle = subtitle, back_label = screen:strings().back,
        back = function() screen:show_title() end,
        help = function() screen:show_help(function() screen:reopen_game() end) end,
    })
    Parts.pill(c, GameView.MESSAGE_TOP, screen.message, screen.message_dark)
    local geom = GameView.board_geometry(screen.engine.length)
    board(c, screen, geom, true)
    keyboard(c, screen)
    return geom
end

-- Screen rectangles for the updates without a flash: one row of the board and the message.
function GameView.row_rect(c, geom, row)
    local y = geom.top + (row - 1) * (geom.size + geom.gap)
    return c:rect(geom.left - 4, y - 4, 600 - geom.left + 4, y + geom.size + 4)
end

function GameView.message_rect(c)
    return c:rect(0, GameView.MESSAGE_TOP - 4, 600, GameView.MESSAGE_TOP + 34)
end

local function average_text(screen, value)
    local text = string.format("%.1f", value)
    return screen.lang == "en" and text or (text:gsub("%.", ","))
end

function GameView.layout_result(screen, c)
    local t = screen:strings()
    local engine = screen.engine
    local title, subtitle = GameView.titles(screen)
    Parts.header(c, { title = title, subtitle = subtitle, back_label = t.home, back = function() screen:show_title() end })
    local length = engine.length
    local size, gap = 38, 5
    local left = 300 - (length * size + (length - 1) * gap) / 2
    for row = 1, Engine.ATTEMPTS do
        local letters = row_letters(screen, row)
        local result = engine.results[row]
        for col = 1, length do
            Parts.tile(c, left + (col - 1) * (size + gap), 82 + (row - 1) * (size + gap), size, letters[col], result and result[col],
                { radius = 5 })
        end
    end
    c:box(24, 336, 576, 776, { border = BLACK, width = 2, radius = 16 })
    local won = engine:is_won()
    if won then
        c:text(300, 370, string.format(t.won, #engine.guesses), SERIF_BOLD, 28, { anchor = "center", middle = true, room = 520, name = "result" })
        c:text(300, 402, screen.free_play and t.free_note or t.next_word, SERIF_ITALIC, 14,
            { anchor = "center", middle = true, color = DARK, room = 520, name = "result note" })
    else
        c:text(300, 360, t.lost_title, SERIF_ITALIC, 15, { anchor = "center", middle = true, color = DARK, room = 520, name = "result" })
        local marks = {}
        for i = 1, length do
            marks[i] = Engine.CORRECT
        end
        Parts.tile_row(c, 378, 40, 6, length, Engine.split(engine.answer), marks, { radius = 5 })
    end
    local counts, highlight, numbers
    if screen.free_play then
        local free = screen:free_stats_for(screen:config_key())
        -- Wins from before the attempts were counted (1.2.2 and earlier) are left out of the average.
        local sum, counted = 0, 0
        for attempt, count in pairs(free.distribution) do
            sum, counted = sum + attempt * count, counted + count
        end
        numbers = {
            { tostring(free.played), t.played_short }, { tostring(free.won), t.wins_short },
            { counted > 0 and average_text(screen, sum / counted) or "-", t.average_short },
        }
        counts, highlight = free.distribution, won and #engine.guesses or nil
    else
        local stats = screen:stats_for(screen:config_key())
        local rate = stats.played > 0 and math.floor(stats.won * 100 / stats.played + 0.5) or 0
        numbers = {
            { tostring(Engine.current_streak(stats, Engine.today())), t.streak_short },
            { tostring(stats.best_streak), t.best_short }, { rate .. "%", t.rate_short },
        }
        counts, highlight = stats.distribution, won and #engine.guesses or nil
    end
    for i, number in ipairs(numbers) do
        local x0 = 48 + (i - 1) * 172
        Parts.number_box(c, x0, 430, x0 + 160, 488, number[1], number[2])
    end
    Parts.section(c, 48, 504, screen.free_play and t.free_distribution or t.distribution)
    Parts.distribution(c, 48, 528, 552, counts, highlight, 15, 5)
    local plugin_dir = screen.plugin_dir
    if screen.free_play then
        Parts.button(c, 48, 668, 552, 714, t.new_word, { dark = true, icon = "shuffle_white", plugin_dir = plugin_dir, size = 16,
            action = function() screen:start_free_game() end, id = "new_word" })
        Parts.button(c, 48, 724, 552, 762, t.daily_title, { size = 15, radius = 19,
            action = function() screen:start_game() end, id = "daily" })
    else
        local day = engine.day
        Parts.button(c, 48, 668, 294, 714, t.share, { dark = true, icon = "qr_white", plugin_dir = plugin_dir, size = 15,
            action = function() screen:show_share(function() screen:start_game(day) end) end, id = "share" })
        Parts.button(c, 306, 668, 552, 714, t.stats, { icon = "bars", plugin_dir = plugin_dir, size = 15,
            action = function() screen:show_stats(function() screen:start_game(day) end) end, id = "stats" })
        Parts.button(c, 48, 724, 552, 762, t.play_free .. "  ›", { size = 15, radius = 19,
            action = function() screen:start_free_game() end, id = "play_free" })
    end
end

return GameView
