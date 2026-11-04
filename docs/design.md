# Vocábulo: design e ferramentas

Como o jogo funciona por dentro, para quem quer entender o código ou mexer nas listas. Para instalar e jogar, veja o [README](../README.md). `vocabulo_game` é o identificador do plugin.

## Regras

- O jogador escolhe o idioma e o tamanho (5, 6 ou 7 letras) e tem 6 tentativas.
- Cada tentativa precisa ser uma palavra da lista de tentativas válidas.
- **Preto:** letra no lugar certo. **Cinza:** letra na palavra, em outro lugar. **Branco:** letra fora da palavra. Letras repetidas só são marcadas tantas vezes quantas existem na resposta.
- Acentos e cedilha não são digitados e aparecem quando a palavra é revelada. Em espanhol, o `Ñ` é uma letra própria, com tecla própria.
- **Palavra do dia:** vem da data local e da lista de respostas de cada combinação de idioma e tamanho. Quem usa a mesma configuração recebe a mesma palavra, sem internet. Ao fim da lista, a sequência recomeça.
- **Modo livre:** palavras sorteadas das mesmas listas, sem limite por dia. Não conta para a sequência e tem contador próprio. O sorteio evita a palavra de hoje e as 30 últimas sorteadas, mas uma palavra pode reaparecer depois como palavra do dia. O resultado não é compartilhado.
- O progresso é salvo a cada tentativa em `koreader/settings/vocabulo_game.lua`, e as estatísticas são separadas por combinação.
- O resultado pode ser compartilhado por QR code, com a grade em `■ ▣ □`, sem revelar letras.
- Os textos da interface seguem o idioma escolhido. Na primeira abertura, o idioma vem da configuração do KOReader.
- O jogo é sempre em retrato, como O Síndico, e não usa rede. Precisa de tela sensível ao toque.

## Estrutura

```
vocabulo_game.koplugin/
  _meta.lua, main.lua     registro no KOReader
  vocabulo_game/
    engine.lua            regras, sem depender do KOReader
    words.lua             carrega as listas
    ui/screen.lua         tela inicial, estatísticas, ajuda e sobre
    ui/game_view.lua      grade e teclado, desenhados direto na tela
  data/
    i18n.lua              textos nos três idiomas
    words/<idioma>/       answers_<n>.txt e guesses_<n>.txt
  tools/, tests/, docs/   desenvolvimento, fora do pacote publicado
```

A grade e o teclado são desenhados por uma única widget, porque 30 botões do KOReader pesariam no e-ink. Cada letra atualiza só a própria linha.

As tentativas válidas ficam como uma única string em memória, com até 49 mil palavras, em vez de uma tabela Lua. Só a lista da combinação em jogo é carregada.

## Listas de palavras

Geradas por `tools/words/build_words.py`, a partir das fontes baixadas por `tools/words/fetch_sources.sh`. As fontes ficam fora do repositório.

| Uso | Português | Inglês | Espanhol |
|---|---|---|---|
| Tentativas válidas | [fserb/pt-br](https://github.com/fserb/pt-br) (MIT) | [dwyl/english-words](https://github.com/dwyl/english-words) (Unlicense) | [an-array-of-spanish-words](https://github.com/words/an-array-of-spanish-words) (MIT) |
| Frequência das respostas | ICF de fserb/pt-br | [FrequencyWords](https://github.com/hermitdave/FrequencyWords) (conteúdo CC BY-SA 4.0) | FrequencyWords |

Dois filtros são usados só na geração, sem ir para o jogo: as formas-base dos dicionários Hunspell de [wooorm/dictionaries](https://github.com/wooorm/dictionaries), que tiram flexões e nomes próprios, e o [LDNOOBW](https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words) (CC BY 4.0).

As respostas saem das 750 candidatas mais frequentes de cada lista, menos as palavras de `tools/words/exclude_<idioma>.txt`, limitadas a 500 e embaralhadas com semente fixa. Palavras fora das candidatas revisadas nunca viram resposta. Mudar a ordem ou o conteúdo das listas muda a palavra do dia de quem já joga, então isso deve ser evitado depois de publicar.

Critério das exclusões: palavras gramaticais, flexões, nomes próprios, gentílicos, meses, estrangeirismos, termos obscuros e tudo que seja ofensivo ou pesado para ver logo cedo (violência, morte, doença grave, drogas, religião e política partidária).

```sh
tools/words/fetch_sources.sh /pasta/vazia
python3 -I tools/words/build_words.py /pasta/vazia build
```

## Ferramentas

- `luajit tools/validate_words.lua`: confere as listas e se os textos existem nos três idiomas.
- `luajit tests/engine_spec.lua`: testes do motor.
- `tools/package.sh`: gera o zip e o checksum. Exige o arquivo `LICENSE`.
- Com `KOREADER_DIR` apontando para um KOReader de desktop: `tools/koreader/run_emulator.sh` abre o jogo numa janela, e `tools/koreader/check_all_sizes.sh` joga todas as combinações pelos toques em quatro tamanhos de tela. Com `OUTPUT_DIR`, `tools/koreader/run_headless.sh` e os scripts dessa pasta salvam as telas em PNG.

O emulador não mostra o que é próprio do e-ink nem a velocidade do aparelho: a conferência final é num aparelho real.

## Licença

Tudo está sob GPL-3.0, somente a versão 3. Uma licença "não comercial" não é possível aqui, porque as respostas usam dados CC BY-SA 4.0. Os créditos das fontes estão em `NOTICE`.

## Como publicar uma versão

1. Atualizar `version` em `_meta.lua` e criar a seção da versão em `CHANGELOG.md`, no formato `## [1.2.3]`.
2. Rodar `tools/koreader/check_all_sizes.sh` e testar num aparelho.
3. Publicar a release `v1.2.3` no GitHub, criando a tag junto, depois do push. O workflow `release.yml` confere se a tag bate com o `_meta.lua`, roda as verificações e anexa o zip e o checksum à release.
