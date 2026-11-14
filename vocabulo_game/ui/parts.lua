-- The pieces every screen is made of, in the units of the mockups (600x800): tiles, the back pill, the header,
-- buttons, segmented choices, number boxes and attempt bars.
local Canvas = require("vocabulo_game/ui/canvas")
local Engine = require("vocabulo_game/engine")

local BLACK, INK, DARK, MID, GRAY, LIGHT, PALE, PAPER, WHITE =
    Canvas.BLACK, Canvas.INK, Canvas.DARK, Canvas.MID, Canvas.GRAY, Canvas.LIGHT, Canvas.PALE, Canvas.PAPER, Canvas.WHITE
local SANS, SANS_BOLD, SERIF_BOLD, SERIF_ITALIC = Canvas.SANS, Canvas.SANS_BOLD, Canvas.SERIF_BOLD, Canvas.SERIF_ITALIC

local Parts = {}

Parts.MARGIN = 24

function Parts.icon(c, plugin_dir, name, cx, cy, size)
    c:image(plugin_dir .. "/assets/icons/" .. name .. ".svg", cx - size / 2, cy - size / 2, size, size)
end

-- One tile of the board. mark: Engine.CORRECT, PRESENT or ABSENT, or nil for a tile without a result. A letter in
-- another place also gets a black corner, so it does not depend only on telling gray from white.
function Parts.tile(c, x, y, size, letter, mark, opts)
    opts = opts or {}
    local radius = opts.radius or 6
    local text_color = BLACK
    if mark == Engine.CORRECT then
        c:box(x, y, x + size, y + size, { fill = BLACK, radius = radius })
        text_color = WHITE
    elseif mark == Engine.PRESENT then
        c:box(x, y, x + size, y + size, { fill = GRAY, border = BLACK, width = 2, radius = radius })
        c:corner(x + size - 2, y + 2, size * 0.26, BLACK)
    elseif mark == Engine.ABSENT then
        c:box(x, y, x + size, y + size, { fill = WHITE, border = LIGHT, width = 2, radius = radius })
        text_color = MID
    elseif opts.typed then
        c:box(x, y, x + size, y + size, { fill = WHITE, border = BLACK, width = 3, radius = radius })
    else
        c:box(x, y, x + size, y + size, { fill = WHITE, border = PALE, width = 2, radius = radius })
    end
    if opts.cursor then
        c:box(x + size * 0.3, y + size - 9, x + size * 0.7, y + size - 6, { fill = BLACK })
    end
    if letter and letter ~= "" then
        c:text(x + size / 2, y + size / 2 + 1, Engine.upper(letter), SERIF_BOLD, size * 0.52,
            { anchor = "center", middle = true, color = text_color, cache = true })
    end
end

-- A row of tiles centered on the screen. letters and marks are lists; marks may be nil.
function Parts.tile_row(c, y, size, gap, count, letters, marks, opts)
    local x = Canvas.UNITS_W / 2 - (count * size + (count - 1) * gap) / 2
    for i = 1, count do
        Parts.tile(c, x + (i - 1) * (size + gap), y, size, letters and letters[i], marks and marks[i], opts)
    end
end

function Parts.back_pill(c, label, action)
    local text = "‹ " .. label
    local w = math.min(c:measure(text, SANS_BOLD, 14) + 26, 150)
    c:box(18, 18, 18 + w, 52, { border = BLACK, width = 2, radius = 17 })
    c:text(18 + w / 2, 35, text, SANS_BOLD, 14, { anchor = "center", middle = true, room = 124, name = "back button" })
    c:hit(10, 10, 26 + w, 60, action, "back")
end

function Parts.help_button(c, action)
    c:circle(565, 35, 17, { fill = WHITE, border = BLACK, width = 2 })
    c:text(565, 35, "?", SANS_BOLD, 17, { anchor = "center", middle = true })
    c:hit(538, 10, 592, 60, action, "help")
end

-- The header of every screen but the title: the back pill, the title with an optional subtitle and the line.
function Parts.header(c, opts)
    Parts.back_pill(c, opts.back_label, opts.back)
    if opts.help then
        Parts.help_button(c, opts.help)
    end
    local room = 600 - 2 * 168
    if opts.subtitle then
        c:text(300, 26, opts.title, SERIF_BOLD, 20, { anchor = "center", middle = true, room = room, name = "header title" })
        c:text(300, 50, opts.subtitle, SERIF_ITALIC, 13, { anchor = "center", middle = true, color = DARK, room = room, name = "header subtitle" })
    else
        c:text(300, 35, opts.title, SERIF_BOLD, 20, { anchor = "center", middle = true, room = room, name = "header title" })
    end
    c:line(18, 68, 582, 68, BLACK, 2)
end

-- A short message in a rounded pill, centered at y (its top); dark for a warning.
function Parts.pill(c, y, text, dark)
    local w = math.min(c:measure(text, SANS_BOLD, 14) + 34, 552)
    c:box(300 - w / 2, y, 300 + w / 2, y + 30, { fill = dark and BLACK or WHITE, border = BLACK, width = 2, radius = 15 })
    c:text(300, y + 15, text, SANS_BOLD, 14, { anchor = "center", middle = true, color = dark and WHITE or BLACK, room = 518, name = "message" })
end

-- A button with an optional icon (a name in assets/icons, drawn before the text). opts: dark, size, radius,
-- icon, action, id, plugin_dir (needed with icon).
function Parts.button(c, x0, y0, x1, y1, text, opts)
    opts = opts or {}
    local size = opts.size or 17
    c:box(x0, y0, x1, y1, { fill = opts.dark and BLACK or WHITE, border = BLACK, width = 2, radius = opts.radius or 12 })
    local text_color = opts.dark and WHITE or BLACK
    local room = x1 - x0 - 20
    local tw = math.min(c:measure(text, SANS_BOLD, size), room)
    local cy = (y0 + y1) / 2
    if opts.icon then
        room = room - 30
        tw = math.min(tw, room)
        local left = (x0 + x1) / 2 - (tw + 30) / 2
        Parts.icon(c, opts.plugin_dir, opts.icon, left + 10, cy, 20)
        c:text(left + 30, cy, text, SANS_BOLD, size, { middle = true, color = text_color, room = room, name = "button" })
    else
        c:text((x0 + x1) / 2, cy, text, SANS_BOLD, size, { anchor = "center", middle = true, color = text_color, room = room, name = "button" })
    end
    if opts.action then
        c:hit(x0, y0, x1, y1, opts.action, opts.id)
    end
end

-- A row of choices in one rounded frame, with the chosen one filled. options: { { label, value } }.
function Parts.segmented(c, x0, y0, x1, y1, options, selected, on_select, size, id_prefix)
    size = size or 15
    c:box(x0, y0, x1, y1, { fill = WHITE, border = BLACK, width = 2, radius = (y1 - y0) / 2 })
    local step = (x1 - x0) / #options
    for i, option in ipairs(options) do
        local a, b = x0 + (i - 1) * step, x0 + i * step
        local chosen = option.value == selected
        if chosen then
            c:box(a + 4, y0 + 4, b - 4, y1 - 4, { fill = BLACK, radius = (y1 - y0 - 8) / 2 })
        end
        c:text((a + b) / 2, (y0 + y1) / 2, option.label, chosen and SANS_BOLD or SANS, size,
            { anchor = "center", middle = true, color = chosen and WHITE or BLACK, room = step - 12, name = "choice" })
        c:hit(a, y0, b, y1, function() on_select(option.value) end, (id_prefix or "choice") .. ":" .. tostring(option.value))
    end
end

-- The marks of some attempts as small squares, without letters. dark: drawn on a black card.
function Parts.mini_grid(c, x, y, cell, gap, rows, length, total_rows, dark)
    for r = 1, total_rows do
        local marks = rows[r]
        for col = 1, length do
            local x0, y0 = x + (col - 1) * (cell + gap), y + (r - 1) * (cell + gap)
            local mark = marks and marks[col]
            if dark then
                if mark == Engine.CORRECT then
                    c:box(x0, y0, x0 + cell, y0 + cell, { fill = WHITE, radius = 2 })
                elseif mark == Engine.PRESENT then
                    c:box(x0, y0, x0 + cell, y0 + cell, { fill = GRAY, radius = 2 })
                    c:corner(x0 + cell, y0, cell * 0.35, BLACK)
                elseif mark == Engine.ABSENT then
                    c:box(x0, y0, x0 + cell, y0 + cell, { fill = DARK, radius = 2 })
                else
                    c:box(x0, y0, x0 + cell, y0 + cell, { fill = INK, border = MID, width = 1.5, radius = 2 })
                end
            elseif mark == Engine.CORRECT then
                c:box(x0, y0, x0 + cell, y0 + cell, { fill = BLACK, radius = 2 })
            elseif mark == Engine.PRESENT then
                c:box(x0, y0, x0 + cell, y0 + cell, { fill = GRAY, border = BLACK, width = 1.5, radius = 2 })
                c:corner(x0 + cell - 1.5, y0 + 1.5, cell * 0.3, BLACK)
            else
                c:box(x0, y0, x0 + cell, y0 + cell, { fill = WHITE, border = LIGHT, width = 1.5, radius = 2 })
            end
        end
    end
end

function Parts.number_box(c, x0, y0, x1, y1, number, label)
    c:box(x0, y0, x1, y1, { border = BLACK, width = 2, radius = 10 })
    c:text((x0 + x1) / 2, y0 + 22, number, SERIF_BOLD, 22, { anchor = "center", middle = true, room = x1 - x0 - 10, name = "number" })
    c:text((x0 + x1) / 2, y1 - 13, label, SANS, 11, { anchor = "center", middle = true, color = DARK, room = x1 - x0 - 10, name = "number label" })
end

function Parts.section(c, x, y, text)
    c:text(x, y, Engine.upper(text), SANS_BOLD, 12, { color = MID, room = 552, name = "section" })
end

-- Wins by number of attempts as bars, the highlighted one in black.
function Parts.distribution(c, x0, y0, x1, counts, highlight, row, gap)
    local top = 1
    for i = 1, Engine.ATTEMPTS do
        top = math.max(top, counts[i] or 0)
    end
    for i = 1, Engine.ATTEMPTS do
        local count = counts[i] or 0
        local y = y0 + (i - 1) * (row + gap)
        c:text(x0, y + row / 2, tostring(i), SANS_BOLD, 12, { middle = true })
        local bar_x = x0 + 18
        local width = math.max(24, (x1 - bar_x) * count / top)
        local dark = i == highlight
        c:box(bar_x, y, bar_x + width, y + row, { fill = dark and BLACK or PALE, radius = 4 })
        c:text(bar_x + width - 8, y + row / 2, tostring(count), SANS_BOLD, 11,
            { anchor = "right", middle = true, color = dark and WHITE or BLACK })
    end
    return y0 + Engine.ATTEMPTS * (row + gap)
end

return Parts
