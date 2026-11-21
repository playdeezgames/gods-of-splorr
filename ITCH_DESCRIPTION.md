# itch.io page copy: Gods of SPLORR!!

Page: https://thegrumpygamedev.itch.io/gods-of-splorr (not created yet; the slug is expected). First itch.io release booked for November 22, 2026 (Coxswain ship 29). GitHub Pages came first (live since November 1, 2026).
**Draft, written November 21, 2026; the user has not approved any of it.** Pasted in by hand; nothing here is published by the repo. Cover: `assets/cover.png` (630 by 500, a placeholder made by `tools/make_cover.py` from the game's tiles). Screenshots: `assets/screenshots/` (copied from the player's guide shots, `manual/img/`, taken by `manual/screenshots.mjs`).

## Short description (the one-line field, at most 120 characters)

A tribe lives, crafts and starves on its own. You are its god: five miracles, limited faith. Help them, or smite them.

## Page text

**Latest version:** https://playdeezgames.github.io/gods-of-splorr/

**Gods of SPLORR!!** is a god game about a tribe that does not need you, until it does.

A handful of people wake up on a small square world of grass, trees, berry bushes, ponds and stone. Nobody tells them what to do. They forage, sleep, grow old and get hungry. They knap sharp stones, twist fiber into twine, make spears and bows, a fire drill, a firepit, nets for the ponds, baskets, rope and drying racks, and in time fur coats. Once there are enough of them they split the work: foragers, a toolmaker, a firekeeper, a fisher, a hunter. Poisonous snakes hunt them; rabbits graze, breed and bolt. Seasons turn, and the first winter is cold enough to kill a tribe that did not lay in a store.

You watch from above. Each miracle costs faith, and faith comes back slowly:

- **Manna:** a berry from the sky, where you point.
- **Smite:** strike down whoever stands there.
- **Snake:** a poisonous snake that hunts whoever is near.
- **Smite Bush:** scorch a bush away to bare dirt.
- **Miracle Bush:** a god-made bush that holds a lot of berries and bears in any weather.

Left alone, about half the tribes make it through the first year; every tribe that survives its first winter goes on. Whether you nudge yours through, or test them, is up to you. The game ends when everyone is dead.

### How to play

- **Mouse:** hover to inspect anything, drag to pan, wheel to zoom. Click a person to follow them, click the minimap to look somewhere. Click a miracle's button, then the map, to cast it.
- **Keyboard:** arrows or WASD move the cursor (Shift for five cells), 1 to 5 cast a miracle at the cursor, Z and X zoom, F follows, N follows the next person, Space pauses, + and - change speed, P hides the miracles, M opens the controls and credits, R begins again after a loss.
- **Gamepad:** the whole game plays from the d-pad, A and B. A casts the armed miracle or follows the person under the cursor; B opens a command menu (miracles, follow, zoom, speed, pause). Bumpers change speed, Start pauses.

Two PDFs are downloads on this page: **How the game works** (the rules, the numbers and a balance report) and the **Player's guide** (how to play, with screenshots).

### About it

A prototype, made for the browser in Odin compiled to WebAssembly. The world is 32 by 32 for now; larger worlds are planned.

**AI disclosure:** made with Claude Code. The design and every decision are TheGrumpyGameDev's; Claude writes the code and the tests and drafts the text at the author's direction.

### Credits

- Designed by TheGrumpyGameDev.
- Code and draft text by Claude Code (AI), at the author's direction.
- Tiles: Urizen 1-bit tileset v2.0 by vurmux, https://vurmux.itch.io/urizen-onebit-tileset (CC0), recoloured.
- Feedback by LootLocker.

## Page settings (by hand, on ship day)

- Kind of project: HTML. Tick "This file will be played in the browser" on the `html` upload.
- Embed: "Click to launch in fullscreen" (the user's rule for every game). The stage is 16:9 landscape.
- Mobile friendly: no (mouse, keyboard or gamepad; there are no touch controls).
- Uploads: `html` (the game, `./shippit.sh --push`), `manual` (how-the-game-works.pdf) and `guide` (players-guide.pdf), both plain downloads (`tools/ship_manual.sh --push`).
- External link: `Latest version (GitHub Pages)` to https://playdeezgames.github.io/gods-of-splorr/
- Classification: Games. Genre: Simulation.
- Tags: god-game, simulation, sandbox, 1-bit, survival, prototype.
- AI disclosure field: Yes (Code, Text).
