# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## State of the repo

Early prototype: a 32x32 map viewer with a day/night and calendar clock. `./build.sh` builds `build/web`; `odin test src -define:ODIN_TEST_THREADS=1` runs native tests.

- `src/game.odin`: world generation (weighted terrain), cursor and camera. `src/time.odin`: clock, calendar, latitude-driven temperature and sun, all pure. Both have native `*_test.odin` files (`#+build !js`).
- `src/web.odin` (`#+build js`): drawing and exports; `web/index.html`: canvas shim and all input (keys, mouse, gamepad), which calls exported `on_*` procs.
- `runWasm` is async: call `memory.exports` only inside `.then`. Calendar parameters come from the URL: `?day=<real seconds per game day>&dpm=&mpy=&lat=` (default 1440 s/day, 30 days, 12 months, latitude 40; months per year is rounded up to a multiple of 4).

## What this is

"Gods of SPLORR!!": a **god game** on a square grid world. Supported world sizes will be 32x32, 64x64 and 128x128, but **work strictly at 32x32 first**; keep the size a parameter rather than a hard-coded constant so the larger sizes are a later switch, not a rewrite.

## Planned stack

- **Language/target:** Odin compiled to `js_wasm32` (Odin's own `core/sys/wasm/js/odin.js` runtime, no emscripten), drawn on a 2D canvas via a small JS shim. The user's `odin` is at `~/.local/bin/odin`.
- **Graphics:** the **Urizen 1-bit tileset** (vurmux, CC0, v2.0), recolouring allowed. Tiles are 12 px with a 1 px gap (tile (col,row) starts at pixel `13*col+1, 13*row+1`); each tile is one colour on opaque black, so black must be knocked out as transparent at load time. Credit vurmux in the game's credits.
- **Asset creation:** the **Anvil** MCP server (`mcp__anvil-prod__*`: worlds, maps, terrain, sprites, tilesets, palettes, sounds).
- **Task tracking:** the **Coxswain** MCP server (`mcp__coxswain__*`). The agent name for Claude sessions in this repo is **`annunaki`** (use it when registering and claiming tasks).

The reference for all of the above is the user's Obsidian vault at `/home/yermom/git/bok-of-splorr/splorr/` (read `Home.md` first). Useful notes: `Tech/Odin wasm recipe.md` (build command, frame loop, input, canvas shim, native-testable split), `Tech/Urizen tileset.md` and `Tech/Urizen tile catalogue*.md` (tile coordinates), `Assets/urizen_onebit_tileset__v2d0.png` (the sheet), `Tech/Release standard.md`, `Tech/GitHub Pages.md`, `Gotchas.md`. Add new hard-won lessons to the vault's `Gotchas.md`.

## Build/run recipe (from the vault; not yet wired up here)

```bash
odin build src -target:js_wasm32 -out:build/web/game.wasm -o:speed
cp "$(odin root)/core/sys/wasm/js/odin.js" build/web/
python3 -m http.server -d build/web 8000   # wasm must be served over http, not file://
```

Native tests (once they exist): `odin test src -define:ODIN_TEST_THREADS=1`; one test with `-define:ODIN_TEST_NAMES=<package>.<proc>`.

## Architecture intent

Follow the vault's "pure logic, native tests" split so the simulation can be tested without a browser:

- Game rules and world state: no browser imports, runs and tests natively. Time advances via a `tick(dt)` (seconds) called from the frame loop.
- Browser glue (`foreign import`, input listeners, drawing, exported `step`): one file behind `#+build js`. Test files get `#+build !js` (`core:testing` pulls in `core:os`, which panics on wasm).
- Odin gotchas that bite here: seed the RNG yourself in `main`; constant arrays cannot be indexed by a runtime value (declare with `:=`); event callbacks need `context = ctx` set.

## Standing rules inherited from the vault

- "push" means `git push`; "ship" means itch.io. Never do either unless the user explicitly says so. Commit only when asked.
- Odin/wasm games target GitHub Pages by default; making the repo public or enabling Pages is the user's call.
- Anything an AI agent posts publicly (itch.io devlogs, comments) must say it was posted by an AI agent.
