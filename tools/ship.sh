#!/usr/bin/env bash
# Prepares the itch.io html build: tests, a size-optimised web build, a zip. Pushes ONLY with --push.
# Never commits, never deletes anything but its own zip. Usage: tools/ship.sh [--push]
# The two PDFs go up separately with tools/ship_manual.sh.
# Page: https://thegrumpygamedev.itch.io/gods-of-splorr (not created yet; the slug is expected, confirm it
# before the first push; one ship a day, booked through Coxswain).
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET="${ITCH_TARGET:-thegrumpygamedev/gods-of-splorr:html}"
ZIP="build/gods-of-splorr-html5.zip"

tools/test.sh
./build.sh --size
rm -f "$ZIP"
(cd build/web && zip -q -9 -r "../$(basename "$ZIP")" index.html odin.js lootlocker.js game.wasm tileset.png)
echo "zip: $ZIP ($(du -h "$ZIP" | cut -f1)); wasm $(du -h build/web/game.wasm | cut -f1)"
unzip -l "$ZIP" | tail -7

if [ "${1:-}" = "--push" ]; then
	if [ -n "$(git status --porcelain)" ]; then
		echo "note: the working tree has uncommitted changes; what is pushed is the working tree, not a commit"
	fi
	butler push "$ZIP" "$TARGET"
	echo "pushed to $TARGET. It goes live after itch.io processes it; check: butler status $TARGET"
else
	echo "not pushed (run tools/ship.sh --push when you want it live; the target is $TARGET)"
fi
