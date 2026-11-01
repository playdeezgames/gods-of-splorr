#!/usr/bin/env bash
# Build the web version into build/web (serve that folder over http).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/web
odin build src -target:js_wasm32 -out:build/web/game.wasm -o:speed
cp "$(odin root)/core/sys/wasm/js/odin.js" build/web/
cp web/index.html assets/tileset.png build/web/
