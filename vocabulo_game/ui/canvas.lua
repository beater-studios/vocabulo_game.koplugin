-- A screen laid out in the units of the mockups (600x800), scaled to the real screen and centered. Laying out
-- builds a list of things to paint and of tap areas; painting only replays the list. Every text that does not
-- fit the room it was given is noted in `problems`, which tools/koreader/check_layout.lua reads.
-- Texts laid out with `cache` (letters, keys) are built once and kept in the cache table given to new(), which
-- outlives the canvas: the game lays out the whole screen again on every key, and the cache keeps that cheap.
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")

local Canvas = {}
Canvas.__index = Canvas

Canvas.UNITS_W, Canvas.UNITS_H = 600, 800

-- The 16 grays of the screen, by brightness.
Canvas.BLACK, Canvas.INK, Canvas.DARK, Canvas.MID, Canvas.GRAY, Canvas.LIGHT, Canvas.PALE, Canvas.PAPER, Canvas.WHITE =
    0, 34, 68, 119, 170, 187, 221, 238, 255

Canvas.SANS = "noto/NotoSans-Regular.ttf"
Canvas.SANS_BOLD = "noto/NotoSans-Bold.ttf"
Canvas.SERIF = "noto/NotoSerif-Regular.ttf"
Canvas.SERIF_BOLD = "noto/NotoSerif-Bold.ttf"
Canvas.SERIF_ITALIC = "noto/NotoSerif-Italic.ttf"

local function color(value)
    return Blitbuffer.Color8(value)
end

-- cache: an optional table kept by the screen, freed with Canvas.free_cache when the screen closes.
function Canvas.new(width, height, cache)
    local self = setmetatable({}, Canvas)
    self.width, self.height = width, height
    self.s = math.min(width / Canvas.UNITS_W, height / Canvas.UNITS_H)
    self.ox = math.floor((width - Canvas.UNITS_W * self.s) / 2)
    self.oy = math.floor((height - Canvas.UNITS_H * self.s) / 2)
    self.items, self.hits, self.problems, self.bottom = {}, {}, {}, 0
    self.cache = cache or {}
    return self
end

function Canvas:px(v)
    return math.floor(v * self.s + 0.5)
end

function Canvas:x(v)
    return self.ox + self:px(v)
end

function Canvas:y(v)
    return self.oy + self:px(v)
end

-- A rectangle in units, as a screen rectangle relative to the window.
function Canvas:rect(x0, y0, x1, y1)
    return Geom:new{ x = self:x(x0), y = self:y(y0), w = self:px(x1 - x0), h = self:px(y1 - y0) }
end

-- Font:getFace multiplies the size by the screen scale; sizes here are already in pixels.
function Canvas:face(name, size)
    local factor = Device.screen:scaleBySize(1000) / 1000
    return Font:getFace(name, math.max(6, size * self.s / factor))
end

function Canvas:reach(y)
    if y > self.bottom then
        self.bottom = y
    end
end

function Canvas:problem(text)
    self.problems[#self.problems + 1] = text
end

-- A rectangle with rounded corners: fill and border are grays (nil for none), width and radius in units.
function Canvas:box(x0, y0, x1, y1, opts)
    opts = opts or {}
    self.items[#self.items + 1] = {
        kind = "box", x = self:x(x0), y = self:y(y0), w = self:px(x1 - x0), h = self:px(y1 - y0),
        fill = opts.fill, border = opts.border, bw = math.max(1, self:px(opts.width or 2)), r = self:px(opts.radius or 0),
    }
    self:reach(y1)
end

-- A straight line, horizontal or vertical.
function Canvas:line(x0, y0, x1, y1, value, width)
    local bw = math.max(1, self:px(width or 2))
    local x, y = self:x(math.min(x0, x1)), self:y(math.min(y0, y1))
    local w = x0 == x1 and bw or self:px(math.abs(x1 - x0))
    local h = y0 == y1 and bw or self:px(math.abs(y1 - y0))
    self.items[#self.items + 1] = { kind = "rect", x = x, y = y, w = w, h = h, fill = value or Canvas.BLACK }
    self:reach(math.max(y0, y1))
end

-- A right triangle in the top right corner of the square that ends at (x1, y0), with sides of `size` units.
function Canvas:corner(x1, y0, size, value)
    self.items[#self.items + 1] = { kind = "corner", x = self:x(x1 - size), y = self:y(y0), size = self:px(size), fill = value or Canvas.BLACK }
end

-- A circle around (cx, cy): filled with `fill`, or a ring of `width` units in `border`.
function Canvas:circle(cx, cy, r, opts)
    opts = opts or {}
    local item = { kind = "circle", x = self:x(cx), y = self:y(cy), r = self:px(r) }
    if opts.fill then
        self.items[#self.items + 1] = { kind = "circle", x = item.x, y = item.y, r = item.r, fill = opts.fill }
    end
    if opts.border then
        self.items[#self.items + 1] = { kind = "circle", x = item.x, y = item.y, r = item.r, fill = opts.border,
            width = math.max(1, self:px(opts.width or 2)) }
    end
    self:reach(cy + r)
end

local function text_key(text, font, size, value)
    return table.concat({ font, size, value, text }, "\0")
end

-- The width, in units, of a text on one line.
function Canvas:measure(text, font, size)
    local key = text_key(text, font, size, "w")
    local cached = self.cache[key]
    if cached then
        return cached
    end
    local widget = TextWidget:new{ text = text, face = self:face(font, size) }
    local w = widget:getSize().w / self.s
    widget:free()
    self.cache[key] = w
    return w
end

-- One line of text. anchor: left (default), center or right of x; middle: y is the vertical center instead of
-- the top. With room, a text wider than that is a problem. cache: build it once and keep it. Returns the width
-- in units.
function Canvas:text(x, y, text, font, size, opts)
    opts = opts or {}
    local value = opts.color or Canvas.BLACK
    local w = self:measure(text, font, size)
    local widget, cached
    if opts.cache and not (opts.room and w > opts.room) then
        local key = text_key(text, font, size, value)
        widget = self.cache[key]
        if not widget then
            widget = TextWidget:new{ text = text, face = self:face(font, size), fgcolor = color(value) }
            self.cache[key] = widget
        end
        cached = true
    else
        widget = TextWidget:new{
            text = text, face = self:face(font, size), fgcolor = color(value),
            max_width = opts.room and self:px(opts.room) or nil,
        }
    end
    local h = widget:getSize().h / self.s
    if opts.room and w > opts.room then
        self:problem(string.format("text does not fit in %s: %s", opts.name or "a line", text))
    end
    local shown = math.min(w, opts.room or w)
    local left = x
    if opts.anchor == "center" then
        left = x - shown / 2
    elseif opts.anchor == "right" then
        left = x - shown
    end
    local top = opts.middle and y - h / 2 or y
    self.items[#self.items + 1] = { kind = "widget", widget = widget, cached = cached, x = self:x(left), y = self:y(top) }
    self:reach(top + h)
    return w
end

-- A wrapped text. align: left (default), center or right; background: the gray behind it. With room (a
-- height), a taller text is a problem. Returns the bottom, in units.
function Canvas:paragraph(x, y, width, text, font, size, opts)
    opts = opts or {}
    local widget = TextBoxWidget:new{
        text = text, face = self:face(font, size), width = self:px(width), alignment = opts.align or "left",
        fgcolor = color(opts.color or Canvas.BLACK), bgcolor = color(opts.background or Canvas.WHITE),
    }
    local h = widget:getSize().h / self.s
    if opts.room and h > opts.room + 0.5 then
        self:problem(string.format("text taller than its room in %s: %s", opts.name or "a paragraph", text))
    end
    self.items[#self.items + 1] = { kind = "widget", widget = widget, x = self:x(x), y = self:y(y) }
    self:reach(y + h)
    return y + h
end

-- The height, in units, of a wrapped text.
function Canvas:measure_paragraph(text, font, size, width)
    local widget = TextBoxWidget:new{ text = text, face = self:face(font, size), width = self:px(width) }
    local h = widget:getSize().h
    widget:free()
    return h / self.s
end

-- An image file (PNG or SVG), stretched to w x h units. Images are icons and the game logo, so they are drawn
-- once per size and kept in the cache: an SVG would otherwise be rendered again on every key.
function Canvas:image(file, x, y, w, h)
    local width, height = self:px(w), self:px(h or w)
    local key = table.concat({ "image", file, width, height }, "\0")
    local widget = self.cache[key]
    if not widget then
        widget = ImageWidget:new{ file = file, width = width, height = height, alpha = true }
        self.cache[key] = widget
    end
    self.items[#self.items + 1] = { kind = "widget", widget = widget, cached = true, x = self:x(x), y = self:y(y) }
    self:reach(y + (h or w))
end

-- Any KOReader widget, already built, with its top left corner at (x, y) units.
function Canvas:widget(widget, x, y)
    self.items[#self.items + 1] = { kind = "widget", widget = widget, x = self:x(x), y = self:y(y) }
    self:reach(y + widget:getSize().h / self.s)
end

-- A tap area, in units, what it does and an optional id, for the checks to find it.
function Canvas:hit(x0, y0, x1, y1, action, id)
    self.hits[#self.hits + 1] = { rect = self:rect(x0, y0, x1, y1), action = action, id = id }
end

-- The topmost tap area under a screen point, or nil.
function Canvas:hit_at(x, y)
    for i = #self.hits, 1, -1 do
        local rect = self.hits[i].rect
        if x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h then
            return self.hits[i]
        end
    end
end

-- The tap area with this id, or nil.
function Canvas:hit_by_id(id)
    for _, hit in ipairs(self.hits) do
        if hit.id == id then
            return hit
        end
    end
end

-- The bottom of everything laid out, in screen pixels.
function Canvas:content_height()
    return self:y(self.bottom)
end

local function paint_corner(bb, x, y, size, value)
    for i = 0, size - 1 do
        bb:paintRect(x + i, y + i, size - i, 1, value)
    end
end

function Canvas:paint(bb, x, y)
    for _, item in ipairs(self.items) do
        if item.kind == "box" then
            if item.fill then
                if item.r > 0 then
                    bb:paintRoundedRect(x + item.x, y + item.y, item.w, item.h, color(item.fill), item.r)
                else
                    bb:paintRect(x + item.x, y + item.y, item.w, item.h, color(item.fill))
                end
            end
            if item.border then
                bb:paintBorder(x + item.x, y + item.y, item.w, item.h, item.bw, color(item.border), item.r)
            end
        elseif item.kind == "rect" then
            bb:paintRect(x + item.x, y + item.y, item.w, item.h, color(item.fill))
        elseif item.kind == "corner" then
            paint_corner(bb, x + item.x, y + item.y, item.size, color(item.fill))
        elseif item.kind == "circle" then
            bb:paintCircle(x + item.x, y + item.y, item.r, color(item.fill), item.width)
        else
            item.widget:paintTo(bb, x + item.x, y + item.y)
        end
    end
end

function Canvas:free()
    for _, item in ipairs(self.items) do
        if item.widget and not item.cached then
            item.widget:free()
        end
    end
    self.items, self.hits = {}, {}
end

function Canvas.free_cache(cache)
    for _, value in pairs(cache) do
        if type(value) == "table" and value.free then
            value:free()
        end
    end
end

return Canvas
