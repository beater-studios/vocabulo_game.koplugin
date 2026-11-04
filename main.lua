local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Screen = require("vocabulo_game/ui/screen")

local PLUGIN_DIR = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*)/") or "."

local VocabuloGame = WidgetContainer:extend{
    name = "vocabulo_game",
    is_doc_only = false,
}

function VocabuloGame:init()
    self.ui.menu:registerToMainMenu(self)
end

function VocabuloGame:addToMainMenu(menu_items)
    menu_items.vocabulo_game = {
        text = self.fullname,
        sorting_hint = "tools",
        callback = function()
            UIManager:show(Screen:new{ plugin_dir = PLUGIN_DIR })
        end,
    }
end

return VocabuloGame
