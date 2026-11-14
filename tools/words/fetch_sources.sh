#!/bin/sh
# Downloads the word sources at fixed commits into a new, empty folder and checks each file against
# tools/words/sources.sha256. Updating a source means changing its commit here and its checksum there.
set -eu
dest="${1:?usage: fetch_sources.sh <new empty folder for the sources>}"
if [ -e "$dest" ] && [ -n "$(ls -A "$dest")" ]; then
    echo "The folder $dest is not empty: the sources always go to a new folder." >&2
    exit 1
fi
mkdir -p "$dest"
sums="$(cd "$(dirname "$0")" && pwd)/sources.sha256"

PT_BR=93ba2a6f3b2f85262fba72df09d448c6bb2fa50a
ENGLISH_WORDS=20f5cc9b3f0ccc8ce45d814c532b7c2031bba31c
SPANISH_WORDS=612349c44d0a9127fb317f7d56d078eda7ae6e65
FREQUENCY_WORDS=525f9b560de45753a5ea01069454e72e9aa541c6
LDNOOBW=5faf2ba42d7b1c0977169ec3611df25a3c08eb13
DICTIONARIES=8cfea406b505e4d7df52d5a19bce525df98c54ab

base=https://raw.githubusercontent.com
fetch() {
    curl -fsSL --max-time 120 -o "$dest/$2" "$1"
    echo "downloaded: $2"
}
fetch "$base/fserb/pt-br/$PT_BR/lexico" pt_lexicon
fetch "$base/fserb/pt-br/$PT_BR/icf" pt_icf
fetch "$base/fserb/pt-br/$PT_BR/conjuga%C3%A7%C3%B5es" pt_conjugations
fetch "$base/fserb/pt-br/$PT_BR/listas/negativas" pt_negative
fetch "$base/dwyl/english-words/$ENGLISH_WORDS/words_alpha.txt" en_words
fetch "$base/words/an-array-of-spanish-words/$SPANISH_WORDS/index.json" es_words.json
fetch "$base/hermitdave/FrequencyWords/$FREQUENCY_WORDS/content/2018/en/en_50k.txt" en_frequency
fetch "$base/hermitdave/FrequencyWords/$FREQUENCY_WORDS/content/2018/es/es_50k.txt" es_frequency
for lang in en es pt; do
    fetch "$base/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words/$LDNOOBW/$lang" "${lang}_blocklist"
    fetch "$base/wooorm/dictionaries/$DICTIONARIES/dictionaries/$lang/index.dic" "${lang}_stems.dic"
done

if command -v sha256sum > /dev/null; then
    check() { sha256sum -c "$@"; }
else
    check() { shasum -a 256 -c "$@"; }
fi
if [ "$(ls "$dest" | sort)" != "$(awk '{ print $2 }' "$sums" | sort)" ]; then
    echo "tools/words/sources.sha256 does not list exactly the downloaded files." >&2
    exit 1
fi
if ! (cd "$dest" && check --quiet "$sums"); then
    echo "A downloaded source differs from its checksum in tools/words/sources.sha256." >&2
    exit 1
fi
echo "sources checked: $(wc -l < "$sums" | tr -d ' ') files"
