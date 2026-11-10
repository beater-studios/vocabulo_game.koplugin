#!/bin/sh
# Every check that runs without KOReader. The CI runs tools/check.sh; the release runs tools/check.sh release,
# which also downloads the word sources, builds data/words again and fails if it differs from the repository.
set -eu
cd "$(dirname "$0")/.."
luajit tools/validate_words.lua
for spec in tests/*_spec.lua; do
    luajit "$spec"
done
luajit tools/check_texts.lua t strings 'strings()'
if [ "${1:-}" = release ]; then
    sources="$(mktemp -d)"
    sh tools/words/fetch_sources.sh "$sources"
    python3 -I tools/words/build_words.py "$sources" build
    rm -rf "$sources"
    # Also catches new files, which git diff leaves out.
    if [ -n "$(git status --porcelain -- data/words)" ]; then
        git status --short -- data/words
        echo "data/words difere do que as fontes geram." >&2
        exit 1
    fi
    luajit tools/validate_words.lua
fi
sh tools/package.sh
