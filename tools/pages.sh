#!/usr/bin/env bash
# Build the web game into docs/ for GitHub Pages (served from main:/docs). Does not commit or push.
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh
rm -rf docs
mkdir docs
cp -r build/web/. docs/
touch docs/.nojekyll
echo "docs/ ready: $(du -sh docs | cut -f1). Commit it and push to publish."
