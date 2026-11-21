#!/usr/bin/env bash
# Rebuilds the two documents and uploads each to its own itch.io channel (plain downloads on the page).
# Uploads ONLY with --push. Never commits, never deletes anything. Usage: tools/ship_manual.sh [--push]
#   channel manual: manual/how-the-game-works.pdf    channel guide: manual/players-guide.pdf
set -euo pipefail
cd "$(dirname "$0")/.."
PAGE="${ITCH_PAGE:-thegrumpygamedev/gods-of-splorr}"
python3 manual/make_pdf.py
python3 manual/make_players_guide.py
ls -l manual/how-the-game-works.pdf manual/players-guide.pdf
if [ "${1:-}" = "--push" ]; then
	butler push manual/how-the-game-works.pdf "$PAGE:manual"
	butler push manual/players-guide.pdf "$PAGE:guide"
	echo "pushed to $PAGE:manual and $PAGE:guide; check: butler status $PAGE"
else
	echo "not pushed (use --push to upload to $PAGE:manual and $PAGE:guide)"
fi
