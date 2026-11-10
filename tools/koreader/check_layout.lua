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

local meta = dofile(plugin_dir .. "/_meta.lua")
for _, lang in ipairs(Words.LANGUAGES) do
    reopened.lang = lang
    local found = false
    for _, item in ipairs(reopened:about_items()) do
        if (item.meta or ""):find(meta.version, 1, true) then found = true end
    end
    if not found then problem("versão ausente na tela Sobre em " .. lang) end
end

-- A daily game in progress comes back in a new screen opened with the same settings.
reopened.games, reopened.lang, reopened.length = {}, "pt", 6
reopened:start_game()
local first_guess
for _, word in ipairs(reopened:word_lists().answers) do
    first_guess = Engine.plain(word, "pt")
    if first_guess ~= reopened.engine.answer_key then break end
end
type_word(reopened, first_guess)
local resumed = GameScreen:new{ plugin_dir = plugin_dir }
if resumed.lang ~= "pt" or resumed.length ~= 6 then problem("idioma e tamanho não voltaram na tela nova") end
resumed:start_game()
if #resumed.engine.guesses ~= 1 or resumed.engine.guesses[1] ~= first_guess or resumed.engine.answer ~= reopened.engine.answer then
    problem("partida em andamento não voltou na tela nova")
end

-- Refresh modes: a new layout flashes, a change inside it does not, the 9th change in a row flashes, and
-- the end of a game flashes. Nothing asks for "partial", which KOReader counts towards its own flashes.
local real_set_dirty = UIManager.setDirty
local log = {}
UIManager.setDirty = function(_, widget, refresh)
    if widget == resumed then
        log[#log + 1] = type(refresh) == "function" and (refresh()) or refresh
    end
end
local function modes(action)
    log = {}
    action()
    return table.concat(log, ",")
end
local function expect(name, actual, wanted)
    if actual ~= wanted then problem(string.format("pintura em %s: %s, esperado %s", name, actual, wanted)) end
end
resumed.games = {}
resumed:show_help()
expect("tela inicial", modes(function() resumed:show_title() end), "full")
local changes = {}
for i = 1, 9 do changes[i] = modes(function() resumed:show_title() end) end
expect("troca de opções", table.concat(changes, ","), "ui,ui,ui,ui,ui,ui,ui,ui,full")
expect("abrir partida", modes(function() resumed:start_game() end), "full")
local wrong = {}
for _, word in ipairs(resumed:word_lists().answers) do
    local key = Engine.plain(word, "pt")
    if key ~= resumed.engine.answer_key then wrong[#wrong + 1] = key end
    if #wrong == 2 then break end
end
local letters = string.rep("ui,", resumed.length)
expect("digitar e enviar", modes(function() type_word(resumed, wrong[1]) end), letters .. "ui")
expect("vitória", modes(function() type_word(resumed, resumed.engine.answer_key) end), letters .. "full")
expect("página", modes(function() resumed:show_about() end), "full")
UIManager.setDirty = real_set_dirty

-- Back goes back one screen and closes from the title; KOReader's Close closes, except before a shutdown.
local back = GameScreen:new{ plugin_dir = plugin_dir }
UIManager:show(back)
back:start_game()
back:onBack()
if back.mode ~= "title" or not UIManager:isWidgetShown(back) then problem("Voltar na partida não voltou ao menu") end
back:show_help()
back:onBack()
if back.mode ~= "title" then problem("Voltar na ajuda não voltou ao menu") end
back:onClose({ keep_screensaver = true })
if not UIManager:isWidgetShown(back) then problem("Close antes de desligar fechou a janela") end
back:onBack()
if UIManager:isWidgetShown(back) then problem("Voltar no menu não fechou o jogo") end
local closing = GameScreen:new{ plugin_dir = plugin_dir }
UIManager:show(closing)
closing:start_game()
closing:onClose()
if UIManager:isWidgetShown(closing) then problem("Close do KOReader não fechou a janela") end

print("problemas: " .. problems)
os.exit(problems == 0 and 0 or 1)
