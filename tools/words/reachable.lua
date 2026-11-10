-- Answers the word list generator with the game keyboard itself: reads one word per line from stdin and
-- prints 1 when the player can type it in that language, 0 otherwise.
-- Usage, from the plugin folder: luajit tools/words/reachable.lua <lang> < words
local lang = assert(arg[1], "usage: reachable.lua <lang>")
local root = (arg[0]:match("^(.*)/tools/words/[^/]+$")) or "."
package.path = root .. "/?.lua;" .. package.path
local Keyboard = require("vocabulo_game/keyboard")

local out = {}
for word in io.stdin:lines() do
    out[#out + 1] = Keyboard.reaches(word, lang) and "1" or "0"
end
io.stdout:write(table.concat(out, "\n"), #out > 0 and "\n" or "")
