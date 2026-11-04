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
local Words = require("vocabulo_game/words")

local problems = 0
local function problem(text)
    problems = problems + 1
    print("PROBLEMA: " .. text)
end
local function shot(widget, name)
    Screen.bb:fill(require("ffi/blitbuffer").COLOR_WHITE)
    widget:paintTo(Screen.bb, 0, 0)
    Screen.bb:writePNG(out_dir .. "/" .. name .. ".png")
end
local function check_height(game, name)
    if game.content_height > Screen:getHeight() then
        problem("tela estoura em " .. name .. ": " .. game.content_height)
    end
end
local function check_rects(rects, name)
    for _, r in ipairs(rects) do
        if r.x < 0 or r.y < 0 or r.x + r.w > Screen:getWidth() or r.y + r.h > Screen:getHeight() then
            problem(name .. " fora da tela: " .. tostring(r.id))
        end
    end
end
local function tap(game, rect)
    local pos = { x = rect.x + math.floor(rect.w / 2), y = rect.y + math.floor(rect.h / 2) }
    game.view:onTap(nil, { pos = pos })
end
local function key_rect(game, id)
    for _, key in ipairs(game.view.keys) do
        if key.id == id then return key end
    end
    problem("tecla ausente: " .. id)
end
local function type_word(game, word)
    for _, letter in ipairs(Engine.split(word)) do
        tap(game, key_rect(game, letter))
    end
    tap(game, key_rect(game, "submit"))
end

local game = GameScreen:new{ plugin_dir = plugin_dir }
check_height(game, "título")
shot(game, "title")

local played = 0
for _, lang in ipairs(Words.LANGUAGES) do
    for _, length in ipairs(Words.LENGTHS) do
        local label = lang .. " " .. length
        game.lang, game.length = lang, length
        game.games = {}
        game:show_title()
        check_height(game, "título " .. label)
        game:start_game()
        local view = game.view
        check_rects(view.keys, label)
        check_rects(view.result_buttons, label)
        check_rects({ view.back_rect }, label .. " botão de voltar")
        local TextWidget = require("ui/widget/textwidget")
        local back_text = TextWidget:new{ text = view.back_rect.label, face = view.back_face }
        if back_text:getSize().w > view.back_rect.w - 8 then problem("texto do botão de voltar não cabe em " .. label) end
        back_text:free()
        local available = Screen:getWidth() - 2 * (view.back_rect.x + view.back_rect.w + Screen:scaleBySize(6))
        for _, text in ipairs({ game:strings().unknown, game:strings().short, string.format(game:strings().lost, string.rep("W", length)), string.format("%s · %s", game:strings().free_play, string.format(game:strings().letters_count, length)) }) do
            local face = text:find("·", 1, true) and view.title_face or view.message_face
            local widget = TextWidget:new{ text = text, face = face }
            if widget:getSize().w > available then problem("texto colide com o botão de voltar em " .. label .. ": " .. text) end
            widget:free()
        end
        tap(game, view.back_rect)
        if game.mode ~= "title" then problem("botão de voltar não voltou ao menu em " .. label) end
        game:start_game()
        view = game.view
        local last = view:cell_rect(Engine.ATTEMPTS, length)
        if last.y + last.h > view.keyboard_rect.y then
            problem("grade invade o teclado em " .. label)
        end
        if last.x + last.w > Screen:getWidth() then
            problem("grade fora da tela em " .. label)
        end
        for _, key in ipairs(view.keys) do
            if key.w < 1 or key.h < 1 then problem("tecla sem tamanho em " .. label) end
        end

        local answers = Words.load_answers(plugin_dir, lang, length)
        local answer_key = Engine.plain(game.engine.answer, lang)
        for _, word in ipairs(answers) do
            if #Engine.split(Engine.plain(word, lang)) ~= length then
                problem("palavra de tamanho errado em " .. label .. ": " .. word)
            end
            if not game.engine.is_valid(Engine.plain(word, lang)) then
                problem("resposta não aceita como tentativa em " .. label .. ": " .. word)
            end
            for _, letter in ipairs(Engine.split(Engine.plain(word, lang))) do
                local found = false
                for _, key in ipairs(view.keys) do
                    if key.id == letter then found = true break end
                end
                if not found then problem("letra sem tecla em " .. label .. ": " .. letter .. " em " .. word) end
            end
        end

        local wrong = {}
        for _, word in ipairs(answers) do
            local key = Engine.plain(word, lang)
            if key ~= answer_key then wrong[#wrong + 1] = key end
            if #wrong == 5 then break end
        end
        tap(game, key_rect(game, Engine.split(wrong[1])[1]))
        if game.engine.current[1] ~= Engine.split(wrong[1])[1] then problem("toque não digitou em " .. label) end
        tap(game, key_rect(game, "submit"))
        if view.message ~= game:strings().short then problem("não avisou que faltam letras em " .. label) end
        tap(game, key_rect(game, "backspace"))
        if #game.engine.current ~= 0 then problem("apagar falhou em " .. label) end
        if lang == "pt" and length == 5 then shot(game, "game_empty") end

        for i = 1, 3 do type_word(game, wrong[i]) end
        if #game.engine.guesses ~= 3 then problem("tentativas não entraram em " .. label) end
        shot(game, "game_" .. lang .. "_" .. length)
        type_word(game, answer_key)
        if not game.engine:is_won() then problem("não venceu em " .. label) end
        shot(game, "won_" .. lang .. "_" .. length)
        if not game.stats[lang .. "_" .. length] or game.stats[lang .. "_" .. length].won ~= 1 then
            problem("estatística não registrada em " .. label)
        end
        played = played + 1

        game.games = {}
        game:start_game()
        for i = 1, Engine.ATTEMPTS do type_word(game, wrong[(i - 1) % #wrong + 1]) end
        if not game.engine:is_over() or game.engine:is_won() then problem("derrota não encerrou em " .. label) end
        if lang == "pt" and length == 7 then shot(game, "lost") end

        game:start_game()
        if not game.engine:is_over() then problem("partida encerrada não voltou salva em " .. label) end
        local daily_stats = game.stats[lang .. "_" .. length].played

        game:show_title()
        check_height(game, "título com modo livre " .. label)
        game:start_free_game()
        if not game.free_play or game.engine:is_over() then problem("modo livre não começou em " .. label) end
        local today_key = Engine.plain(Engine.answer_for_day(answers, Engine.today()), lang)
        if game.engine.answer_key == today_key then problem("modo livre sorteou a palavra de hoje em " .. label) end
        check_rects(game.view.result_buttons, label .. " livre")
        local first_free = game.engine.answer
        local guess_key = wrong[1] ~= game.engine.answer_key and wrong[1] or wrong[2]
        type_word(game, guess_key)
        game:show_title()
        game:start_free_game()
        if game.engine.answer ~= first_free or #game.engine.guesses ~= 1 then problem("modo livre não voltou salvo em " .. label) end
        if lang == "pt" and length == 5 then shot(game, "free_game") end
        type_word(game, game.engine.answer_key)
        if not game.engine:is_won() then problem("modo livre não venceu em " .. label) end
        if lang == "pt" and length == 5 then shot(game, "free_won") end
        if game.free_stats[lang .. "_" .. length].won ~= 1 then problem("estatística livre errada em " .. label) end
        if game.stats[lang .. "_" .. length].played ~= daily_stats then problem("modo livre mexeu na sequência em " .. label) end
        local new_word
        for _, button in ipairs(game.view.result_buttons) do
            if button.id == "new_word" then new_word = button end
        end
        tap(game, new_word)
        if game.engine:is_over() or game.engine.answer == first_free then problem("nova palavra não sorteou outra em " .. label) end
        game:show_stats(function() end)
        check_height(game, "estatísticas " .. label)
        if lang == "pt" and length == 5 then shot(game, "stats") end
        game:show_help()
        check_height(game, "ajuda " .. lang)
        if length == 5 then shot(game, "help_" .. lang) end
        game:show_about()
        check_height(game, "sobre " .. lang)
        if length == 5 then shot(game, "about_" .. lang) end
    end
end
print(string.format("%d combinações jogadas pelos toques", played))

game.games = {}
game.lang, game.length = "es", 5
game:save()
game:start_game()
local accent_answer = game.engine.answer
game:share_result()
print("resultado compartilhado sem erro; resposta do dia: " .. accent_answer)
UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)

local reopened = GameScreen:new{ plugin_dir = plugin_dir }
if reopened.lang ~= "es" or reopened.length ~= 5 then problem("configuração não foi salva") end

local initial_rotation = Screen:getRotationMode()
Screen:setRotationMode(Screen.DEVICE_ROTATED_CLOCKWISE)
local rotated = GameScreen:new{ plugin_dir = plugin_dir }
rotated:start_game()
if Screen:getWidth() > Screen:getHeight() then problem("não voltou para retrato") end
shot(rotated, "opened_in_landscape")
rotated:onCloseWidget()
if Screen:getRotationMode() ~= Screen.DEVICE_ROTATED_CLOCKWISE then problem("rotação não foi restaurada") end
Screen:setRotationMode(initial_rotation)

print("problemas: " .. problems)
os.exit(problems == 0 and 0 or 1)
