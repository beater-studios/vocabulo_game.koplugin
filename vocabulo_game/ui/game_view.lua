local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")

local Engine = require("vocabulo_game/engine")
local Keyboard = require("vocabulo_game/keyboard")

local Screen = Device.screen

local SERIF_BOLD = "noto/NotoSerif-Bold.ttf"
local SERIF_ITALIC = "noto/NotoSerif-Italic.ttf"
local BACKSPACE = "backspace"
local SUBMIT = "submit"

local function face_for_pixels(name, pixels)
    return Font:getFace(name, pixels * 1000 / Screen:scaleBySize(1000))
end

local GameView = InputContainer:extend{
    name = "vocabulo_game_view",
    engine = nil,
    strings = nil,
    width = nil,
    height = nil,
    answer_letters = nil,
    on_change = nil,
    on_back = nil,
    on_share = nil,
    on_stats = nil,
    on_new_word = nil,
    free_play = false,
    message = nil,
}

function GameView:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.text_cache = {}
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
    self:compute_layout()
end

function GameView:getSize()
    return self.dimen
end

function GameView:compute_layout()
    local s = function(value) return Screen:scaleBySize(value) end
    local W, H = self.width, self.height
    local margin, gap = s(10), s(5)
    self.margin, self.gap = margin, gap
    self.header_h = s(66)

    local rows = Keyboard.rows(self.engine.lang)
    local key_gap = s(4)
    local key_w = math.floor((W - 2 * margin - 9 * key_gap) / 10)
    local key_h = s(46)
    self.keyboard_h = 3 * key_h + 2 * key_gap + s(12)
    local keyboard_y = H - self.keyboard_h
    self.keyboard_rect = Geom:new{ x = 0, y = keyboard_y, w = W, h = self.keyboard_h }

    local board_padding = s(8)
    local board_h = keyboard_y - self.header_h - 2 * board_padding
    local attempts, length = Engine.ATTEMPTS, self.engine.length
    local cell = math.floor(math.min(
        (W - 2 * margin - (length - 1) * gap) / length,
        (board_h - (attempts - 1) * gap) / attempts))
    self.cell = cell
    local board_w = length * cell + (length - 1) * gap
    self.board_x = math.floor((W - board_w) / 2)
    self.board_y = self.header_h + board_padding + math.floor((board_h - (attempts * cell + (attempts - 1) * gap)) / 2)
    self.letter_face = face_for_pixels(SERIF_BOLD, math.floor(cell * 0.58))
    self.key_face = face_for_pixels(SERIF_BOLD, math.floor(key_h * 0.46))
    self.action_face = face_for_pixels(SERIF_BOLD, math.floor(key_h * 0.32))
    self.title_face = Font:getFace(SERIF_BOLD, 20)
    self.message_face = Font:getFace(SERIF_ITALIC, 17)
    self.button_face = Font:getFace(SERIF_BOLD, 18)

    self.keys = {}
    local y = keyboard_y + s(6)
    for row_index, row in ipairs(rows) do
        local letters = Engine.split(row)
        local total = #letters * key_w + (#letters - 1) * key_gap
        local action_w = 0
        if row_index == 3 then
            action_w = math.floor(key_w * 1.5)
            total = total + 2 * (action_w + key_gap)
        end
        local x = math.floor((W - total) / 2)
        if row_index == 3 then
            self.keys[#self.keys + 1] = { id = SUBMIT, label = self.strings.submit, x = x, y = y, w = action_w, h = key_h, action = true }
            x = x + action_w + key_gap
        end
        for _, letter in ipairs(letters) do
            self.keys[#self.keys + 1] = { id = letter, label = Engine.upper(letter), x = x, y = y, w = key_w, h = key_h }
            x = x + key_w + key_gap
        end
        if row_index == 3 then
            self.keys[#self.keys + 1] = { id = BACKSPACE, label = "←", x = x, y = y, w = action_w, h = key_h, action = true }
        end
        y = y + key_h + key_gap
    end

    local button_h, button_gap = s(46), s(8)
    local button_w = math.floor((W - 2 * margin - button_gap) / 2)
    local first_y = keyboard_y + s(8)
    local full_w = 2 * button_w + button_gap
    if self.free_play then
        self.result_buttons = {
            { id = "new_word", label = self.strings.new_word, x = margin, y = first_y, w = full_w, h = button_h },
            { id = "back", label = self.strings.back, x = margin, y = first_y + button_h + button_gap, w = full_w, h = button_h },
        }
    else
        self.result_buttons = {
            { id = "share", label = self.strings.share, x = margin, y = first_y, w = button_w, h = button_h },
            { id = "stats", label = self.strings.stats, x = margin + button_w + button_gap, y = first_y, w = button_w, h = button_h },
            { id = "back", label = self.strings.back, x = margin, y = first_y + button_h + button_gap, w = full_w, h = button_h },
        }
    end
    self.back_face = Font:getFace(SERIF_BOLD, 15)
    local back_h = s(44)
    self.back_rect = { id = "back", label = "‹ " .. self.strings.back, x = margin, y = math.floor((self.header_h - back_h) / 2), w = s(92), h = back_h }
end

function GameView:cell_rect(row, column)
    return Geom:new{
        x = self.board_x + (column - 1) * (self.cell + self.gap),
        y = self.board_y + (row - 1) * (self.cell + self.gap),
        w = self.cell,
        h = self.cell,
    }
end

-- Rects below are relative to the view, except the ones given to the screen for refreshing.
function GameView:row_rect(row)
    local first = self:cell_rect(row, 1)
    local w = self.engine.length * self.cell + (self.engine.length - 1) * self.gap
    return Geom:new{ x = self.dimen.x + first.x, y = self.dimen.y + first.y, w = w, h = self.cell }
end

function GameView:message_rect()
    return Geom:new{ x = self.dimen.x, y = self.dimen.y, w = self.width, h = self.header_h }
end

local function paint_centered(bb, widget, x, y, w, h)
    local size = widget:getSize()
    widget:paintTo(bb, x + math.floor((w - size.w) / 2), y + math.floor((h - size.h) / 2))
end

function GameView:draw_text(bb, text, face, x, y, w, h, color, max_width)
    local widget = TextWidget:new{ text = text, face = face, fgcolor = color, max_width = max_width or w }
    paint_centered(bb, widget, self.dimen.x + x, self.dimen.y + y, w, h)
    widget:free()
end

-- Cells and keys only show a few letters in a few styles, so their texts are built once and reused.
function GameView:draw_cached_text(bb, text, face, style, x, y, w, h)
    self.text_cache[face] = self.text_cache[face] or {}
    local by_style = self.text_cache[face]
    by_style[style] = by_style[style] or {}
    local widget = by_style[style][text]
    if not widget then
        widget = TextWidget:new{ text = text, face = face, fgcolor = style.text, max_width = w }
        by_style[style][text] = widget
    end
    paint_centered(bb, widget, self.dimen.x + x, self.dimen.y + y, w, h)
end

function GameView:free()
    for _, by_style in pairs(self.text_cache) do
        for _, by_text in pairs(by_style) do
            for _, widget in pairs(by_text) do
                widget:free()
            end
        end
    end
    self.text_cache = {}
    if InputContainer.free then
        InputContainer.free(self)
    end
end

local STATE_STYLE = {
    [Engine.CORRECT] = { background = Blitbuffer.COLOR_BLACK, text = Blitbuffer.COLOR_WHITE, border = Blitbuffer.COLOR_BLACK },
    [Engine.PRESENT] = { background = Blitbuffer.COLOR_GRAY, text = Blitbuffer.COLOR_BLACK, border = Blitbuffer.COLOR_BLACK },
    [Engine.ABSENT] = { background = Blitbuffer.COLOR_WHITE, text = Blitbuffer.COLOR_DARK_GRAY, border = Blitbuffer.COLOR_GRAY },
}
local EMPTY_STYLE = { background = Blitbuffer.COLOR_WHITE, text = Blitbuffer.COLOR_BLACK, border = Blitbuffer.COLOR_GRAY }
local PLAIN_STYLE = { background = Blitbuffer.COLOR_WHITE, text = Blitbuffer.COLOR_BLACK, border = Blitbuffer.COLOR_BLACK }

function GameView:paint_box(bb, x, y, w, h, style, border_size)
    x, y = self.dimen.x + x, self.dimen.y + y
    bb:paintRect(x, y, w, h, style.background)
    bb:paintBorder(x, y, w, h, border_size, style.border)
end

function GameView:row_letters(row)
    local engine = self.engine
    if engine.guesses[row] then
        if engine.guesses[row] == engine.answer_key then
            return self.answer_letters
        end
        local letters = Engine.split(engine.guesses[row])
        for i, letter in ipairs(letters) do
            letters[i] = Engine.upper(letter)
        end
        return letters
    end
    if row == #engine.guesses + 1 then
        local letters = {}
        for i, letter in ipairs(engine.current) do
            letters[i] = Engine.upper(letter)
        end
        return letters
    end
    return {}
end

function GameView:paint_board(bb)
    local engine = self.engine
    local thin, thick = Screen:scaleBySize(1), Screen:scaleBySize(2)
    for row = 1, Engine.ATTEMPTS do
        local letters = self:row_letters(row)
        local result = engine.results[row]
        for column = 1, engine.length do
            local rect = self:cell_rect(row, column)
            local style = result and STATE_STYLE[result[column]] or (letters[column] and PLAIN_STYLE or EMPTY_STYLE)
            self:paint_box(bb, rect.x, rect.y, rect.w, rect.h, style, (result or letters[column]) and thick or thin)
            if letters[column] then
                self:draw_cached_text(bb, letters[column], self.letter_face, style, rect.x, rect.y, rect.w, rect.h)
            end
        end
    end
end

function GameView:paint_keyboard(bb)
    local states = self.engine:keyboard_states()
    local border = Screen:scaleBySize(1)
    for _, key in ipairs(self.keys) do
        local style = STATE_STYLE[states[key.id]] or PLAIN_STYLE
        self:paint_box(bb, key.x, key.y, key.w, key.h, style, border)
        self:draw_cached_text(bb, key.label, key.action and self.action_face or self.key_face, style, key.x, key.y, key.w, key.h)
    end
end

function GameView:paint_result_buttons(bb)
    local style = PLAIN_STYLE
    for _, button in ipairs(self.result_buttons) do
        self:paint_box(bb, button.x, button.y, button.w, button.h, style, Screen:scaleBySize(2))
        self:draw_text(bb, button.label, self.button_face, button.x, button.y, button.w, button.h, style.text)
    end
end

function GameView:paint_header(bb)
    local s = function(value) return Screen:scaleBySize(value) end
    local back = self.back_rect
    local style = PLAIN_STYLE
    self:paint_box(bb, back.x, back.y, back.w, back.h, style, s(2))
    self:draw_text(bb, back.label, self.back_face, back.x, back.y, back.w, back.h, style.text, back.w - s(8))
    local text_x = back.x + back.w + s(6)
    local text_w = self.width - 2 * text_x
    local mode_name = self.free_play and self.strings.free_play or self.strings.name
    local title = string.format("%s · %s", mode_name, string.format(self.strings.letters_count, self.engine.length))
    self:draw_text(bb, title, self.title_face, text_x, s(8), text_w, s(32), Blitbuffer.COLOR_BLACK)
    if self.message then
        self:draw_text(bb, self.message, self.message_face, text_x, s(38), text_w, s(26), Blitbuffer.COLOR_BLACK)
    end
    bb:paintRect(self.dimen.x, self.dimen.y + self.header_h - s(1), self.width, s(1), Blitbuffer.COLOR_BLACK)
end

function GameView:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)
    self:paint_header(bb)
    self:paint_board(bb)
    if self.engine:is_over() then
        self:paint_result_buttons(bb)
    else
        self:paint_keyboard(bb)
    end
end

local function hit(rects, x, y)
    for _, rect in ipairs(rects) do
        if x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h then
            return rect
        end
    end
end

function GameView:press(id)
    local engine = self.engine
    if id == "back" then
        self.on_back()
    elseif id == "share" then
        self.on_share()
    elseif id == "stats" then
        self.on_stats()
    elseif id == "new_word" then
        self.on_new_word()
    elseif id == SUBMIT then
        self.on_change("submit")
    elseif id == BACKSPACE then
        if engine:remove_letter() then
            self.on_change("letter")
        end
    elseif engine:add_letter(id) then
        self.on_change("letter")
    end
end

function GameView:onTap(_, ges)
    local rects = self.engine:is_over() and self.result_buttons or self.keys
    local x, y = ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y
    local target = hit(rects, x, y) or hit({ self.back_rect }, x, y)
    if target then
        self:press(target.id)
    end
    return true
end

return GameView
