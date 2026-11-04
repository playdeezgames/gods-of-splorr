#!/usr/bin/env bash
# Build the web game into docs/ for GitHub Pages (served from main:/docs), and rebuild the two
# documents in manual/ so they go out with it. Does not commit or push.
# --shots also retakes the player's guide screenshots (a few minutes; a new world each time).
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh
rm -rf docs
mkdir docs
cp -r build/web/. docs/
touch docs/.nojekyll
if [[ "${1:-}" == "--shots" ]]; then node manual/screenshots.mjs; fi
python3 manual/make_pdf.py
python3 manual/make_players_guide.py
echo "docs/ ready: $(du -sh docs | cut -f1). Commit it (and manual/) and push to publish."
