# Vocábulo

[Read this in English](README_en.md)

Uma palavra nova por dia, ou quantas você quiser. Jogo de adivinhar palavras para o [KOReader](https://koreader.rocks), em português, inglês e espanhol.

Um jogo da [Beater Studios](https://beaterstudios.com/).

| Início | Partida | Resultado |
|---|---|---|
| ![Tela inicial com idioma, tamanho e menu](docs/screenshots/title.png) | ![Partida com letras certas em preto e letras em outro lugar em cinza](docs/screenshots/game.png) | ![Partida vencida com a palavra revelada](docs/screenshots/result.png) |

## Como é o jogo

- **Palavra do dia:** quem joga com o mesmo idioma e tamanho recebe a mesma palavra, sem precisar de internet.
- **Modo livre:** palavras sorteadas, sem limite por dia e sem afetar a sequência.
- **Três idiomas:** português, inglês e espanhol, com 5, 6 ou 7 letras. A interface acompanha o idioma escolhido.
- **Feito para e-ink:** preto para a letra certa, cinza para a letra em outro lugar e branco para a letra fora da palavra.
- **Acentos:** você digita sem acento nem cedilha, e eles aparecem quando a palavra é revelada. Em espanhol, o Ñ tem tecla própria.
- **Estatísticas:** sequência de vitórias e tentativas por idioma e tamanho.
- **Compartilhar:** o resultado do dia vira um QR code, sem revelar as letras.
- **Tela de descanso:** se o aparelho dorme com o jogo aberto, aparece a capa do Vocábulo no lugar da capa do livro. Vale quando a tela de descanso do KOReader mostra a capa do livro.
- **Sem internet:** funciona offline e não coleta dados. O progresso é salvo a cada tentativa.

## Instalação

1. Baixe `vocabulo_game.koplugin.zip` na [última versão](https://github.com/beater-studios/vocabulo_game.koplugin/releases/latest).
2. Extraia em `koreader/plugins/`, de modo que exista o arquivo `koreader/plugins/vocabulo_game.koplugin/main.lua`.
3. Reinicie o KOReader. O jogo fica em Ferramentas, como **Vocábulo**.

O progresso fica em `koreader/settings/vocabulo_game.lua`. Para desinstalar, apague a pasta do plugin e, se quiser, esse arquivo.

## Compatibilidade

- Testado com o KOReader 2026.07 num Kindle básico da 10ª geração (firmware 5.18.1).
- Layout conferido no emulador em 600x800, 758x1024, 1072x1448 e 1264x1680.
- Precisa de tela sensível ao toque.
- O jogo é sempre em retrato. Aberto em paisagem, ele gira a tela e restaura a rotação ao fechar.

## Desenvolvimento

Com [LuaJIT](https://luajit.org) instalado, a partir da raiz do repositório:

```sh
sh tools/check.sh
```

Isso confere as listas de palavras e os textos, roda os testes e gera o pacote em `dist/`.

As regras, a geração das listas de palavras, as demais ferramentas e o processo de publicação estão em [docs/design.md](docs/design.md). Para sugerir a remoção de uma palavra, abra uma issue. Contribuições entram sob a mesma licença do projeto.

## Licença

[GPL-3.0](LICENSE), somente a versão 3. Você pode usar, estudar, modificar e redistribuir, mantendo o código aberto sob a mesma licença.

As listas de palavras derivam de fserb/pt-br, dwyl/english-words, an-array-of-spanish-words e FrequencyWords. As respostas em inglês e espanhol foram escolhidas pela frequência do FrequencyWords, sob CC BY-SA 4.0, licença compatível com a GPL-3.0. Os créditos e as licenças de cada uma estão em [NOTICE](NOTICE).

A licença não dá direito de uso sobre os nomes "Vocábulo" e "Beater Studios". Para outros usos, fale com a [Beater Studios](https://beaterstudios.com/).
