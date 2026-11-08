local plugin_dir = assert(os.getenv("PLUGIN_DIR"))
local out_dir = assert(os.getenv("OUTPUT_DIR"))

require("setupkoenv")
local DataStorage = require("datastorage")
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
G_reader_settings:saveSetting("language", "pt_BR")
G_reader_settings:saveSetting("screensaver_type", "cover")
G_reader_settings:saveSetting("screensaver_img_background", "black")
package.path = plugin_dir .. "/?.lua;" .. package.path

local Device = require("device")
local Screen = Device.screen
require("document/canvascontext"):init(Device)
local UIManager = require("ui/uimanager")
UIManager:init()
-- Screensaver needs a ReaderUI or FileManager instance; without a last book it falls back to the KOReader logo.
require("apps/filemanager/filemanager").instance = {}

local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local Screensaver = require("ui/screensaver")
local GameScreensaver = require("vocabulo_game/screensaver")
local GameScreen = require("vocabulo_game/ui/screen")

GameScreensaver.install(plugin_dir)
GameScreensaver.install(plugin_dir)

local game_image = plugin_dir .. "/assets/screensaver.png"
local default_image = "resources/koreader.png"
local failures = 0

local function report(ok, label, detail)
    print(string.format("%s %s: %s", ok and "ok" or "FALHOU", label, detail))
    if not ok then
        failures = failures + 1
    end
end

local function check(label, event, expected_file)
    Screensaver:setup(event)
    local file, kind = Screensaver.image_file, Screensaver.screensaver_type
    local ok = file == expected_file and (expected_file ~= game_image or kind == "cover")
    report(ok, label, string.format("%s (%s)", tostring(file), tostring(kind)))
    Screensaver:cleanup()
end

check("sem jogo aberto", nil, default_image)

local game = GameScreen:new{ plugin_dir = plugin_dir }
UIManager:show(game)
check("com o jogo aberto", nil, game_image)
check("desligando com o jogo aberto", "poweroff", default_image)

local dialog = InfoMessage:new{ text = "Mensagem" }
UIManager:show(dialog)
check("com um diálogo sobre o jogo", nil, game_image)
UIManager:close(dialog)

local other = InputContainer:new{ name = "other_fullscreen", covers_fullscreen = true }
UIManager:show(other)
check("com outra tela cheia sobre o jogo", nil, default_image)
UIManager:close(other)

Screensaver:setup()
Screensaver:show()
local painted = false
for widget in UIManager:topdown_widgets_iter() do
    if widget.name == "ScreenSaver" then
        Screen.bb:fill(require("ffi/blitbuffer").COLOR_WHITE)
        widget:paintTo(Screen.bb, 0, 0)
        Screen.bb:writePNG(out_dir .. "/screensaver.png")
        painted = true
        break
    end
end
report(painted, "tela de descanso desenhada", out_dir .. "/screensaver.png")
Screensaver:close_widget()
Screensaver:cleanup()
Device.screen_saver_mode = false

G_reader_settings:saveSetting("screensaver_type", "random_image")
check("modo diferente de capa", nil, default_image)
G_reader_settings:saveSetting("screensaver_type", "cover")

UIManager:close(game)
check("depois de fechar o jogo", nil, default_image)

os.exit(failures == 0 and 0 or 1)
