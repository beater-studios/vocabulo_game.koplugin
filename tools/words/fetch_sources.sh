#!/bin/sh
set -eu
dest="${1:?uso: fetch_sources.sh <pasta vazia para as fontes>}"
mkdir -p "$dest"
fetch() {
    curl -fsSL --max-time 120 -o "$dest/$2" "$1"
    echo "baixado: $2"
}
base=https://raw.githubusercontent.com
fetch "$base/fserb/pt-br/master/lexico" pt_lexicon
fetch "$base/fserb/pt-br/master/icf" pt_icf
fetch "$base/fserb/pt-br/master/conjuga%C3%A7%C3%B5es" pt_conjugations
fetch "$base/fserb/pt-br/master/listas/negativas" pt_negative
fetch "$base/dwyl/english-words/master/words_alpha.txt" en_words
fetch "$base/words/an-array-of-spanish-words/master/index.json" es_words.json
fetch "$base/hermitdave/FrequencyWords/master/content/2018/en/en_50k.txt" en_frequency
fetch "$base/hermitdave/FrequencyWords/master/content/2018/es/es_50k.txt" es_frequency
for lang in en es pt; do
    fetch "$base/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words/master/$lang" "${lang}_blocklist"
    fetch "$base/wooorm/dictionaries/main/dictionaries/$lang/index.dic" "${lang}_stems.dic"
done
