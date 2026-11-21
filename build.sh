#!/usr/bin/env bash
# Build the web version into build/web (serve that folder over http). Pass --size for the shipping build.
set -euo pipefail
cd "$(dirname "$0")"
OPT=-o:speed
[ "${1:-}" = "--size" ] && OPT=-o:size
mkdir -p build/web
odin build src -target:js_wasm32 -out:build/web/game.wasm $OPT
cp "$(odin root)/core/sys/wasm/js/odin.js" build/web/
cp web/index.html web/lootlocker.js assets/tileset.png build/web/
