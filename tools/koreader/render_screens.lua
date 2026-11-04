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
local Engine = require("vocabulo_game/engine")
local GameScreen = require("vocabulo_game/ui/screen")

local function shot(widget, name)
    Screen.bb:fill(require("ffi/blitbuffer").COLOR_WHITE)
    widget:paintTo(Screen.bb, 0, 0)
    local path = out_dir .. "/" .. name .. ".png"
    Screen.bb:writePNG(path)
    print("salvo: " .. path)
end

local game = GameScreen:new{ plugin_dir = plugin_dir }
shot(game, "title")
game:start_game()
game.engine.answer_key = "carta"
game.engine.answer = "carta"
game.view.answer_letters = { "C", "A", "R", "T", "A" }
for _, word in ipairs({ "mundo", "barco", "campo" }) do
    game.engine.current = Engine.split(word)
    game.engine:submit()
end
game.engine.current = Engine.split("car")
game.view.message = game:game_message()
shot(game, "game")
game.engine.current = Engine.split("carta")
game.engine:submit()
game.view.message = game:game_message()
shot(game, "result")
os.exit(0)
