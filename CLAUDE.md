# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## State of the repo

Playable simulation prototype. The player is a god with faith and five powers (Manna, Smite, Snake, Smite Bush, Miracle Bush), cast by key or by arming an on-screen button and clicking the map; the game ends when everyone is dead (`R` or click restarts). A 32x32 world with day/night, a calendar and temperature, plus people who wander, forage, eat, sleep, craft, drop things, die and rot. `./build.sh` builds `build/web`; `tools/pages.sh` copies that into `docs/` for GitHub Pages (does not commit or push); `odin test src -define:ODIN_TEST_THREADS=1` runs the native tests.

- `src/game.odin`: world generation (weighted terrain: grass, tree, bush, pond, stone field, dirt), cursor and camera. `src/time.odin`: clock, calendar, latitude-driven temperature and sun, all pure.
- `src/people.odin`: `Person` (sex, melanin skin colour, health, satiety, stomach, energy, sleep need, foraging, crafting and ranged skills, age and lifespan, 2 to 4 hands), wandering, eating, sleeping, death by starvation, poison or old age into corpses that rot into skeletons. `src/food.odin`: berry bushes whose regrowth follows temperature (a god-made miracle bush holds more, regrows faster and bears in the cold). `src/ground.odin`: fiber on grass, sticks on trees, stone in stone fields. `src/items.odin`: items in hands and on the ground (stone, fiber, stick, food; crafted twine, sharp stone, short stick, knife), recipes, dropping and spoilage. Crafted items: a knife (sharp stone, short stick, twine) skins snake corpses into meat and skin; a spear (sharp stone, stick, twine) hunts snakes. A spear thrust hits with `hit_chance(person.ranged, snake.dodge)`. Both wear out (`SPEAR_DURABILITY`, `KNIFE_DURABILITY`). Tech tree beyond that: bow (stick + twine; failure loses the twine), stake (knife on a short stick; failure loses the short stick, the knife wears), fire drill (bow + stake; failure loses nothing), firepit (8 stone + 8 sticks, built by `build_fire_pit` on an empty cell beside the builder; terrain `Fire_Pit`, not walkable, `fuel` array holds 8 sticks' worth; nothing lights or burns it yet). A failed recipe wastes only its last ingredient (the twine, or one reed). Ponds grow reeds (`reeds` array, slow regrowth to a maximum) that a person with a knife cuts, wearing the knife; five reeds make a basket, which in a hand adds `BASKET_SLOTS` carry places (`carry_slots`; one basket per person). Each successful craft of an item adds a point to that item's `craft_levels`, added to the crafting check next time.
- `src/mood.odin`: dopamine (mood). A successful craft pays `craft_reward` (4x the first time a person makes an item, shrinking with repeats of it and with every success at anything); it bleeds off with a 12 h half-life. Below `CRAVING_BELOW` a fed person has a goal (`pursue_goal`): the item that would feel best, working back through recipes (`next_step`) and walking to raw materials, instead of doing whatever is nearest. Building a firepit takes 16 items, so `pursue_pit` picks a site, hauls materials there trip by trip into a pile at the person's feet (`site_x`, `site_y`) and builds once it is big enough. Hunger is not part of this yet, so hungry people still wander at random.
- `src/snakes.odin`: poisonous snakes that hunt people and poison them (health drains over time); people flee unless armed with a spear. `src/powers.odin`: faith and the powers.
- Each of these has a native `*_test.odin` (`#+build !js`). `src/web.odin` (`#+build js`) is the drawing and the exported `step`/`on_*` procs.
- `web/index.html`: canvas shim, tint drawing (one reused scratch canvas, never a canvas per colour: see the vault's `Gotchas.md`), the info/clock overlays, the credits overlay (`C`), and all input (keys, mouse, gamepad), which calls exported `on_*` procs.
- `runWasm` is async: call `memory.exports` only inside `.then`. Calendar parameters come from the URL: `?day=<real seconds per game day>&dpm=&mpy=&lat=` (default 1440 s/day, 30 days, 12 months, latitude 40; months per year is rounded up to a multiple of 4). `?world=screen` gives a screen-sized 20x15 world for testing (`?world=N` an N-by-N one); worlds are `width` by `height`, not necessarily square.
- Open work lives in the Coxswain project `gods-of-splorr`.

## What this is

"Gods of SPLORR!!": a **god game** on a square grid world. Supported world sizes will be 32x32, 64x64 and 128x128, but **work strictly at 32x32 first**; keep the size a parameter rather than a hard-coded constant so the larger sizes are a later switch, not a rewrite.

## Planned stack

- **Language/target:** Odin compiled to `js_wasm32` (Odin's own `core/sys/wasm/js/odin.js` runtime, no emscripten), drawn on a 2D canvas via a small JS shim. The user's `odin` is at `~/.local/bin/odin`.
- **Graphics:** the **Urizen 1-bit tileset** (vurmux, CC0, v2.0), recolouring allowed. Tiles are 12 px with a 1 px gap (tile (col,row) starts at pixel `13*col+1, 13*row+1`); each tile is one colour on opaque black, so black must be knocked out as transparent at load time. Credit vurmux in the game's credits.
- **Asset creation:** the **Anvil** MCP server (`mcp__anvil-prod__*`: worlds, maps, terrain, sprites, tilesets, palettes, sounds).
- **Task tracking:** the **Coxswain** MCP server (`mcp__coxswain__*`). The agent name for Claude sessions in this repo is **`annunaki`** (use it when registering and claiming tasks).

The reference for all of the above is the user's Obsidian vault at `/home/yermom/git/bok-of-splorr/splorr/` (read `Home.md` first). Useful notes: `Tech/Odin wasm recipe.md` (build command, frame loop, input, canvas shim, native-testable split), `Tech/Urizen tileset.md` and `Tech/Urizen tile catalogue*.md` (tile coordinates), `Assets/urizen_onebit_tileset__v2d0.png` (the sheet), `Tech/Release standard.md`, `Tech/GitHub Pages.md`, `Gotchas.md`. Add new hard-won lessons to the vault's `Gotchas.md`.

## Build/run recipe (wired up as `build.sh`)

```bash
odin build src -target:js_wasm32 -out:build/web/game.wasm -o:speed
cp "$(odin root)/core/sys/wasm/js/odin.js" build/web/
python3 -m http.server -d build/web 8000   # wasm must be served over http, not file://
```

Native tests: `odin test src -define:ODIN_TEST_THREADS=1`; one test with `-define:ODIN_TEST_NAMES=<package>.<proc>`.

## Architecture intent

Follow the vault's "pure logic, native tests" split so the simulation can be tested without a browser:

- Game rules and world state: no browser imports, runs and tests natively. Time advances via a `tick(dt)` (seconds) called from the frame loop.
- Browser glue (`foreign import`, input listeners, drawing, exported `step`): one file behind `#+build js`. Test files get `#+build !js` (`core:testing` pulls in `core:os`, which panics on wasm).
- Odin gotchas that bite here: seed the RNG yourself in `main`; constant arrays cannot be indexed by a runtime value (declare with `:=`); event callbacks need `context = ctx` set.

## Standing rules inherited from the vault

- "push" means `git push`; "ship" means itch.io. Never do either unless the user explicitly says so. Commit only when asked.
- Odin/wasm games target GitHub Pages by default; making the repo public or enabling Pages is the user's call.
- Anything an AI agent posts publicly (itch.io devlogs, comments) must say it was posted by an AI agent.
