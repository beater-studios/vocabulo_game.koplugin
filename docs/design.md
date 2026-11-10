# Vocábulo: design e ferramentas

Como o jogo funciona por dentro, para quem quer entender o código ou mexer nas listas. Para instalar e jogar, veja o [README](../README.md). `vocabulo_game` é o identificador do plugin.

## Regras

- O jogador escolhe o idioma e o tamanho (5, 6 ou 7 letras) e tem 6 tentativas.
- Cada tentativa precisa ser uma palavra da lista de tentativas válidas.
- **Preto:** letra no lugar certo. **Cinza:** letra na palavra, em outro lugar. **Branco:** letra fora da palavra. Letras repetidas só são marcadas tantas vezes quantas existem na resposta.
- Acentos e cedilha não são digitados e aparecem quando a palavra é revelada. Em espanhol, o `Ñ` é uma letra própria, com tecla própria.
- **Palavra do dia:** vem da data local e da lista de respostas de cada combinação de idioma e tamanho. Quem usa a mesma configuração recebe a mesma palavra, sem internet. Ao fim da lista, a sequência recomeça.
- **Modo livre:** palavras sorteadas das mesmas listas, sem limite por dia. Não conta para a sequência e tem contador próprio. O sorteio evita a palavra de hoje, as dos próximos 30 dias e as 30 últimas sorteadas. Uma palavra jogada no modo livre ainda pode voltar como palavra do dia mais adiante, quando a lista dá a volta. O resultado não é compartilhado.
- O progresso é salvo a cada tentativa em `koreader/settings/vocabulo_game.lua`, junto com a resposta, para que uma partida em andamento não mude se as listas forem atualizadas. As estatísticas são separadas por combinação.
- A sequência só é recalculada quando uma partida termina. Na tela de estatísticas, ela aparece zerada se o último jogo foi antes de ontem. Cada dia conta uma vez só: com o relógio do aparelho atrasado, um dia igual ou anterior ao último registrado não conta de novo.
- O resultado pode ser compartilhado por QR code, com a grade em `■ ▣ □`, sem revelar letras.
- Os textos da interface seguem o idioma escolhido. Na primeira abertura, o idioma vem da configuração do KOReader.
- O jogo é sempre em retrato e não usa rede. Se o aparelho estiver deitado, a tela gira ao abrir e volta ao fechar, ou se a abertura falhar; nesse caso, o menu mostra um aviso no lugar do jogo. Precisa de tela sensível ao toque. Em aparelhos com botão Voltar, ele volta uma tela e, no menu, fecha o jogo. O `Close` que o KOReader manda a todas as janelas antes de sair fecha o jogo, menos antes de desligar ou reiniciar, para não mexer na tela de descanso.
- **Tela de descanso:** se o aparelho dorme com o jogo aberto e a tela de descanso do KOReader está no modo de capa do livro, aparece a capa do Vocábulo no lugar. Com o jogo fechado, em outro modo, ao desligar ou ao reiniciar, nada muda.

## Estrutura

```
vocabulo_game.koplugin/
  _meta.lua, main.lua     registro no KOReader
  vocabulo_game/
    engine.lua            regras, sem depender do KOReader
    words.lua             carrega as listas
    keyboard.lua          letras do teclado do jogo, também usado pelo gerador de listas
    state.lua             leitura do progresso salvo, sem depender do KOReader
    ui/screen.lua         tela inicial, estatísticas, ajuda e sobre
    ui/game_view.lua      grade e teclado, desenhados direto na tela
    screensaver.lua       capa do jogo na tela de descanso
    portrait.lua          tela em retrato enquanto o jogo está aberto
    refresh.lua           quando a tela pisca no e-ink
    letters.lua           letras com acento (separar, tirar acentos, maiúsculas)
    calendar.lua          número do dia, palavra do dia, sorteio do modo livre e sequência
    saved_state.lua       leitura de saves de versões anteriores
  data/
    i18n.lua              textos nos três idiomas
    words/<idioma>/       answers_<n>.txt e guesses_<n>.txt
  assets/screensaver.png  capa em tela cheia, 1200x1600
  tools/, tests/, docs/   desenvolvimento, fora do pacote publicado
```

`screensaver.lua`, `portrait.lua`, `refresh.lua`, `letters.lua`, `calendar.lua` e `saved_state.lua` são cópias sem edição de módulos comuns a outros plugins, assim como `tools/package_lib.sh`, `tools/check_texts.lua`, os workflows em `.github/workflows/` e, em `tools/koreader/`, `run_headless.sh`, `run_emulator.sh`, `check_all_sizes.sh`, `fuzz.lua`, `check_screensaver.lua` e `check_rotation.lua`. O cabeçalho de cada um diz isso. Uma melhoria neles não é feita só aqui, porque a próxima cópia a desfaz. O motor mantém os nomes que já usava (`Engine.split`, `Engine.plain`, `Engine.today`, `Engine.record_result` e os outros) chamando esses módulos.

A capa da tela de descanso entra embrulhando `Screensaver.setup` do KOReader: ele escolhe a imagem como sempre, e o jogo só a troca pela própria capa quando a tela do Vocábulo é a janela de tela cheia no topo. Nenhuma configuração é gravada, então não há o que desfazer ao acordar. A troca só acontece com `screensaver_type` em `cover` e no descanso comum, não ao desligar ou reiniciar. A imagem tem 1200x1600, o dobro de 600x800, para ficar nítida em telas maiores; nas de 600x800, o KOReader a reduz pela metade. A arte sai de `KOREADER_DIR=<KOReader de desktop> python3 -I tools/make_screensaver.py`, que usa o Pillow e a Noto Serif do KOReader.

A grade e o teclado são desenhados por uma única widget, porque 30 botões do KOReader pesariam no e-ink. Cada letra atualiza no e-ink só a própria linha, e o cabeçalho quando a mensagem muda. Os textos das células e das teclas são montados uma vez e reaproveitados, porque a tela inteira é pintada de novo na memória a cada toque.

As atualizações da tela usam só os modos `ui` (sem piscar) e `full` (piscando), contadas por `refresh.lua`. Cada tela tem um tipo (`title`, `game` ou a página aberta): abrir uma tela de outro tipo pisca, e uma mudança dentro do mesmo tipo (trocar idioma ou tamanho, enviar uma tentativa) não pisca, até 8 seguidas; a nona pisca, para limpar os rastros do e-ink. Abrir uma partida, terminar uma partida e acordar o aparelho também fazem a próxima atualização piscar. As letras digitadas atualizam só a linha delas, sem entrar na contagem. O modo `partial` não é usado, porque entra na contagem do próprio KOReader e a piscada cairia num momento qualquer.

## Progresso salvo

Fica em `koreader/settings/vocabulo_game.lua`, gravado a cada tentativa. Chaves:

- `lang` e `length`: a última combinação escolhida.
- `games`: a partida do dia de cada combinação (`pt_5`, `en_7`...), com `version`, `day`, `answer`, `guesses` e `finished`. A partida do dia terminada fica salva até o dia seguinte, para a tela inicial mostrar "Ver resultado" e a mesma palavra não ser jogada de novo.
- `stats`: por combinação, `played`, `won`, `streak`, `best_streak`, `last_day` e `distribution` (vitórias por número de tentativas).
- `free_games`, `free_stats` e `free_recent`: a partida do modo livre, o contador dele e as 30 últimas palavras sorteadas, sem acentos, por combinação.

`state.lua` lê tudo de volta campo por campo: um idioma ou tamanho que não existe volta ao padrão, um campo que falta nas estatísticas recebe o valor padrão, e uma partida com resposta, dia ou tentativas que não servem para a combinação dela é descartada, sem levar junto as estatísticas nem as outras partidas. Cada partida é lida protegida, então um save estragado nunca impede o jogo de abrir. As partidas salvas antes da 1.2.2 não têm `version` e são lidas como versão 1, que tem o mesmo formato. `version` só sobe quando um campo muda de sentido, e aí a leitura converte ou descarta só a partida. As tentativas salvas são uma cópia, nunca a mesma tabela que o motor continua mudando.

`tests/saves/<versão>.lua` guarda saves reais de versões publicadas, gerados no emulador com aquela versão, e `tests/state_spec.lua` abre cada um. Antes de publicar uma versão que muda as listas ou o formato do save, gerar um save com a versão publicada e acrescentá-lo à pasta.

As tentativas válidas ficam como uma única string em memória, com até 49 mil palavras, em vez de uma tabela Lua. Só a lista da combinação em jogo é carregada.

## Listas de palavras

Geradas por `tools/words/build_words.py`, a partir das fontes baixadas por `tools/words/fetch_sources.sh`. As fontes ficam fora do repositório. O script baixa cada fonte de um commit fixo, escrito nele, numa pasta nova e vazia (recusa uma pasta com arquivos), e confere o SHA-256 de cada arquivo com `tools/words/sources.sha256`. Os commits são os que geraram as listas publicadas na 1.2.0, e gerar de novo com eles dá exatamente as listas do repositório. Atualizar uma fonte é uma mudança de propósito, sozinha: trocar o commit no script, o checksum em `sources.sha256` e revisar a diferença nas listas.

| Uso | Português | Inglês | Espanhol |
|---|---|---|---|
| Tentativas válidas | [fserb/pt-br](https://github.com/fserb/pt-br) (MIT) | [dwyl/english-words](https://github.com/dwyl/english-words) (Unlicense) | [an-array-of-spanish-words](https://github.com/words/an-array-of-spanish-words) (MIT) |
| Frequência das respostas | ICF de fserb/pt-br | [FrequencyWords](https://github.com/hermitdave/FrequencyWords) (conteúdo CC BY-SA 4.0) | FrequencyWords |

Dois filtros são usados só na geração, sem ir para o jogo: as formas-base dos dicionários Hunspell de [wooorm/dictionaries](https://github.com/wooorm/dictionaries), que tiram flexões e nomes próprios, e o [LDNOOBW](https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words) (CC BY 4.0). Em português, as formas-base do Hunspell não servem: ele guarda palavras comuns como derivadas de outras (escola de "escolar", música de "músico", livro de "livrar"), e elas nunca virariam resposta. Por isso a base em português é o léxico do fserb/pt-br, menos os plurais e parte dos nomes próprios:

- **Plurais:** a palavra sai quando o singular, por -s, -es, -ões, -ães, -ãos, -ns, -is (-l ou -il) ou -eis, também está no léxico. Nos sufixos terminados em -is ou -es (-is, -eis, -es, -ões, -ães), o singular é comparado sem acento, para pegar papéis (papel), meses (mês) e ingleses (inglês). Em -s e -ãos a comparação é exata, senão pires sairia como plural de piré. Os substantivos que só se usam no plural, como óculos, férias e parabéns, também saem.
- **Nomes próprios:** sai a palavra que o Hunspell só conhece com maiúscula, como Cícero e Beatriz. A comparação é com acento, para que um lugar como Choró não tire choro. O filtro é parcial: o Hunspell não tem muitos nomes (Silva, Bruno, Mariana) e só tem com maiúscula algumas palavras comuns (leste, malta, marinho), que então deixam de ser candidatas.

O léxico também tem formas de verbo conjugadas (passa, deixa, penso, sofreu), e os filtros não pegam nomes próprios, gentílicos nem estrangeirismos que o Hunspell não conheça. Tudo isso sai na revisão das candidatas. As formas de verbo que também são substantivo, como conta e ajuda, ficam; as que são só verbo saem. Os infinitivos podem ser resposta.

As respostas só saem de `tools/words/approved_<idioma>.txt`, a lista das palavras já revisadas e aprovadas, na ordem de frequência das candidatas, embaralhadas com semente fixa. As rejeitadas ficam em `tools/words/exclude_<idioma>.txt`, para não voltarem à revisão. São até 750 respostas por idioma e tamanho. Toda resposta publicada está na lista de aprovadas, e o gerador para com erro se não estiver. Uma palavra nova das fontes só vira resposta depois de alguém aprová-la: `build_words.py <fontes> pending <pasta>` lista, entre as 1200 primeiras candidatas de cada combinação, as que não estão nem nas aprovadas nem nas excluídas, e cada uma vai para uma das duas listas. A primeira lista de aprovadas foi montada com tudo o que já tinha sido publicado mais as 1200 primeiras candidatas de cada combinação que não estavam excluídas, o que antes o gerador tratava como revisado.

O gerador não repete as regras do teclado: `tools/words/reachable.lua` carrega o `keyboard.lua` do jogo e responde, palavra por palavra, se ela pode ser digitada naquele idioma. Uma resposta publicada que deixe de poder ser digitada sai como uma excluída.

A ordem publicada em `answers_<n>.txt` é a sequência das palavras do dia, então o gerador a preserva: as palavras já publicadas ficam no mesmo lugar, uma palavra que passe a ser excluída ou bloqueada é trocada por uma nova na mesma posição, e palavras novas só entram no fim, até o limite do idioma. Uma palavra que já está nas respostas só sai pelo `exclude_<idioma>.txt` ou pela lista de bloqueio: mudanças nos filtros ou no corte das candidatas não a alcançam, para não mexer na sequência. Por isso algumas respostas podem estar fora das candidatas atuais (em português, leste, malta, marinho, pomar e névoa). Rodar o gerador de novo com as mesmas fontes não muda nada. Só quando falta substituta a lista encurta e a sequência muda a partir daquele ponto, e o gerador avisa. Como a palavra do dia é `respostas[dia % tamanho + 1]`, mudar o tamanho de uma lista só preserva os dias seguintes enquanto ela for maior que o número do dia de hoje. Por isso o gerador para com erro, sem gravar, quando o tamanho de uma lista mudaria e ela não tem pelo menos um ano de folga sobre o dia de hoje; `ALLOW_LENGTH_CHANGE=1` aceita a mudança de propósito. Para gerar uma lista do zero, apague o `answers_<n>.txt` correspondente antes.

Critério das exclusões: palavras gramaticais, flexões, nomes próprios, gentílicos, meses, estrangeirismos, termos obscuros e tudo que seja ofensivo ou pesado para ver logo cedo (violência, morte, doença grave, drogas, religião e política partidária).

```sh
sh tools/words/fetch_sources.sh /pasta/nova
python3 -I tools/words/build_words.py /pasta/nova pending /pasta/de/revisao
python3 -I tools/words/build_words.py /pasta/nova build
```

A release gera as listas de novo a partir das fontes e falha se o resultado for diferente do repositório (`sh tools/check.sh release`), então o que foi revisado é o que vai para o pacote.

## Ferramentas

- `sh tools/check.sh`: tudo o que roda sem o KOReader, o mesmo comando no Mac e na CI: `tools/validate_words.lua` (as listas e o teclado), os testes em `tests/*_spec.lua` (o motor e o progresso salvo), `tools/check_texts.lua t strings 'strings()'` (as mesmas chaves e marcadores nos três idiomas, sem travessão, sem marca de aparelho e toda chave pedida pelo código existindo) e o pacote. Com `release`, também baixa as fontes, gera as listas e confere que são iguais às do repositório.
- `sh tools/package.sh`: gera o zip e o checksum em `dist/`, com os passos de `tools/package_lib.sh`, que exige `LICENSE`, `NOTICE` e a capa e confere que tudo o que o código carrega está no pacote. O mesmo conteúdo gera o mesmo zip, byte a byte.
- Com `KOREADER_DIR` apontando para um KOReader de desktop, de dentro da pasta do plugin:
  - `tools/koreader/run_emulator.sh` abre o jogo numa janela de 600x800, com o teclado virtual ligado como no Kindle.
  - `tools/koreader/check_all_sizes.sh` roda `tools/koreader/check_layout.lua` em quatro tamanhos de tela e lista todos os que falharam. Ele joga todas as combinações pelos toques e confere que cada tela cabe, os textos mais longos, a versão na tela Sobre, a partida retomada numa tela nova, a sequência de modos de pintura e o botão Voltar.
  - `tools/koreader/run_headless.sh tools/koreader/fuzz_ui.lua` faz toques, seguradas e arrastos aleatórios na tela inicial, na palavra do dia de cada combinação e no modo livre de cada idioma, digitando palavras das listas de vez em quando, com o dia fixo. Cada erro sai com o comando para repetir (`SEED`, `ACTIONS` e `ONLY`).
  - `tools/koreader/run_headless.sh tools/koreader/check_screensaver.lua` confere quando a capa do jogo entra na tela de descanso, e `tools/koreader/check_rotation.lua` abre o jogo com o KOReader deitado e confere o retrato, inclusive numa abertura que falha.
  - Com `OUTPUT_DIR`, os scripts salvam as telas em PNG nessa pasta; `tools/koreader/render_screens.lua` gera as capturas do README.

O emulador não mostra o que é próprio do e-ink nem a velocidade do aparelho: a conferência final é num aparelho real.

## Licença

Tudo está sob GPL-3.0, somente a versão 3. Uma licença "não comercial" não é possível aqui, porque as respostas usam dados CC BY-SA 4.0. Os créditos das fontes estão em `NOTICE`.

## Como publicar uma versão

1. Atualizar `version` em `_meta.lua` e criar a seção da versão em `CHANGELOG.md`, no formato `## [1.2.3]`.
2. Se a versão muda as listas ou o formato do save, acrescentar a `tests/saves/` um save gerado com a versão publicada.
3. Rodar `sh tools/check.sh`, `tools/koreader/check_all_sizes.sh`, o `fuzz_ui.lua`, o `check_screensaver.lua` e o `check_rotation.lua`, e testar num aparelho.
4. Publicar a release `v1.2.3` no GitHub, criando a tag junto, depois do push. O workflow `release.yml` confere se a tag bate com o `_meta.lua`, roda `sh tools/check.sh release` (que gera as listas de novo a partir das fontes), gera o pacote e anexa o zip e o checksum à release. A CI (`ci.yml`) roda `sh tools/check.sh` em cada push e pull request.
