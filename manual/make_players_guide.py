#!/usr/bin/env python3
"""Builds manual/players-guide.pdf: HTML printed by headless Chrome. Screenshots come from manual/img/,
taken by `node manual/screenshots.mjs` (run ./build.sh first)."""
import subprocess, pathlib

HERE = pathlib.Path(__file__).parent
INK, MUTED, GRID, GOLD, GREEN = "#222", "#666", "#ddd", "#b8892a", "#3d6b2f"

def shot(name, caption):
    return f'<figure><img src="img/{name}"><figcaption>{caption}</figcaption></figure>'

html = f"""<!doctype html><html><head><meta charset="utf-8"><title>Gods of SPLORR!! - Player's guide</title>
<style>
@page {{ size: Letter; margin: 0.7in 0.75in; }}
body {{ font: 11pt/1.55 Helvetica, Arial, sans-serif; color:{INK}; }}
h1 {{ font-size: 28pt; margin: 0 0 4pt; color:{GREEN}; }} h2 {{ font-size: 16pt; margin: 22pt 0 6pt; border-bottom: 2px solid {GOLD}; padding-bottom: 2pt; break-after: avoid; color:{GREEN}; }}
h3 {{ font-size: 12pt; margin: 14pt 0 4pt; break-after: avoid; }}
.sub {{ color:{MUTED}; margin-bottom: 18pt; font-size: 12pt; }}
table {{ border-collapse: collapse; width: 100%; margin: 8pt 0 10pt; font-size: 10pt; break-inside: avoid; }}
th {{ background:{GREEN}; color:#fff; text-align:left; padding: 4pt 7pt; }} td {{ padding: 3.5pt 7pt; border-bottom: 1px solid {GRID}; vertical-align: top; }}
tr:nth-child(even) td {{ background:#f5f8f3; }}
figure {{ margin: 8pt 0 12pt; break-inside: avoid; }} figure img {{ width: 100%; border: 1px solid #999; }}
figcaption {{ font-size: 9pt; color:{MUTED}; margin-top: 3pt; }}
.tip {{ background:#fdf3e3; border-left: 4px solid {GOLD}; padding: 6pt 10pt; margin: 8pt 0; break-inside: avoid; }}
kbd {{ font-family: Menlo, monospace; font-size: 9pt; background:#eee; border: 1px solid #bbb; border-radius: 3px; padding: 0 3pt; }}
code {{ font-family: Menlo, monospace; font-size: 9.5pt; background:#f0f0f0; padding: 0 2pt; }}
.pb {{ break-before: page; }}
</style></head><body>

<h1>Gods of SPLORR!!</h1>
<div class="sub">Player's guide</div>

<h2>You are a god</h2>
<p>Five people wake up in a small world of grass, trees, berry bushes, ponds and stone. They do not know you are there. Left alone, they forage, make tools, fish, hunt rabbits, build a fire, sew fur coats and dry food for the winter. Some years that is enough. Many years it is not.</p>
<p>You watch over them, and you have <b>faith</b> to spend on <b>miracles</b>: you can feed them, grow them food, or, if you are that kind of god, send snakes and smite them. The game ends when the last of your people dies, and it tells you how long they lasted. Your aim is to make that as long as you can, or to see what happens when you don't.</p>
<p>The game opens late in spring. Summer is the time of plenty; the winter after it is long, freezing and berry-less, and it is where most tribes are lost.</p>

<h2>The screen</h2>
{shot("summer.png", "The game in early summer, following the tribe's hunter (white frame). Left: the clock and the miracles. Middle: the map; the yellow frame is your cursor. Right: the minimap, view buttons and the status panel describing the person being followed.")}
<table><tr><th>Part</th><th>What it shows</th></tr>
<tr><td>Clock (top left)</td><td>Year, month and day; the time and season; the temperature; the game speed (or <i>paused</i>); and your faith.</td></tr>
<tr><td>Miracles (left)</td><td>One button per miracle with its key and faith cost. A button you cannot afford is dimmed.</td></tr>
<tr><td>Map (middle)</td><td>Part of the world. The yellow square is your cursor; a white frame marks the person you are following. The map darkens at night.</td></tr>
<tr><td>Minimap (top right)</td><td>The whole world, with a white box for what the map shows. Click or drag on it to look somewhere else.</td></tr>
<tr><td>Buttons (right)</td><td>Zoom in and out, follow or stop following, follow the next person, and the menu.</td></tr>
<tr><td>Status panel (right)</td><td>What is under the cursor, or everything about the person you are following.</td></tr></table>

<h3>Reading the map</h3>
<table><tr><th>You see</th><th>It is</th></tr>
<tr><td>People</td><td>Your tribe, coloured by skin. A corpse lies where someone died and slowly rots to a skeleton.</td></tr>
<tr><td>Bushes, red bar</td><td>A berry bush; the red bar is how full of berries it is. An orange bar above means the bush has been damaged by clumsy picking; at zero it is destroyed.</td></tr>
<tr><td>Ponds, green bar</td><td>A pond with fish; the green bar is how many reeds are left to cut.</td></tr>
<tr><td>Trees, grass, grey stone</td><td>Sticks, fiber and stone: the raw materials for everything your people make.</td></tr>
<tr><td>Rabbits</td><td>Grey-white rabbits graze the grass and bolt from people. Your hunter spears them for meat and fur.</td></tr>
<tr><td>Snakes</td><td>Only when you send one: they hunt people and poison them.</td></tr>
<tr><td>Small squares</td><td>Things on the ground, such as stones, sticks, tools, fish, food drying on a rack. Most of them pile up at the tribe's <b>stockpile</b>, their home.</td></tr></table>

<h2>Controls</h2>
<table><tr><th>Keyboard</th><th>Mouse</th><th>Does</th></tr>
<tr><td><kbd>Arrows</kbd> / <kbd>WASD</kbd> (<kbd>Shift</kbd>: 5 cells)</td><td>Hover</td><td>Move the cursor and inspect what is under it</td></tr>
<tr><td></td><td>Drag the map</td><td>Pan the view</td></tr>
<tr><td><kbd>Z</kbd> / <kbd>X</kbd></td><td>Wheel, Zoom buttons</td><td>Zoom in / out (5 cells across at the closest)</td></tr>
<tr><td><kbd>F</kbd></td><td>Click a person</td><td>Follow them: the view stays on them and the status panel describes them. Moving the cursor or panning stops following.</td></tr>
<tr><td><kbd>N</kbd></td><td>Next button</td><td>Follow the next person</td></tr>
<tr><td></td><td>Click the minimap</td><td>Look there</td></tr>
<tr><td><kbd>1</kbd>-<kbd>5</kbd></td><td>Miracle buttons</td><td>A key casts that miracle at the cursor at once; a button arms it, and your next click on the map casts it there</td></tr>
<tr><td><kbd>Esc</kbd></td><td></td><td>Disarm a miracle, close the menu</td></tr>
<tr><td><kbd>Space</kbd></td><td></td><td>Pause and resume</td></tr>
<tr><td><kbd>+</kbd> / <kbd>-</kbd></td><td></td><td>Game speed, from 0.25x to 32x</td></tr>
<tr><td><kbd>P</kbd></td><td>Miracles button</td><td>Show or hide the miracle buttons</td></tr>
<tr><td><kbd>M</kbd>, <kbd>H</kbd> or <kbd>C</kbd></td><td>Menu button</td><td>Controls and credits</td></tr>
<tr><td><kbd>R</kbd></td><td>Click</td><td>Begin again once everyone is dead</td></tr></table>
<p><b>Gamepad:</b> the d-pad or left stick moves the cursor, the bumpers change speed, Start pauses, X, Y and B are Manna, Smite and Snake, and A begins again after a loss.</p>
<p>At normal speed (1x) a game day takes 24 real minutes, so an hour passes every minute. Speed it up to watch a season go by, and slow down or pause when something needs your attention.</p>

<h2>Miracles</h2>
<p>Faith starts at 50, refills by 2 every game hour and holds at most 100. There are two ways to cast one: put the cursor on a cell and press the miracle's number key, or click its button to arm it (the button lights up) and then click the cell. An armed miracle stays armed, so every click casts it again until you click the button again or press <kbd>Esc</kbd>. A miracle with nothing to act on (Smite on an empty cell, say) costs nothing and does nothing.</p>
{shot("armed.png", "Miracle Bush armed (the lit button): the next click on the map grows one there.")}
<table><tr><th>Key</th><th>Miracle</th><th>Faith</th><th>What it does</th></tr>
<tr><td><kbd>1</kbd></td><td>Manna</td><td>10</td><td>Drops a berry on any open cell. Cheap and quick: drop it beside someone starving.</td></tr>
<tr><td><kbd>2</kbd></td><td>Smite</td><td>30</td><td>Kills the person on that cell.</td></tr>
<tr><td><kbd>3</kbd></td><td>Snake</td><td>25</td><td>A poisonous snake that hunts anyone within 6 cells for 3 days. Poison drains health for hours; people run unless they hold a spear, and a spear can kill it.</td></tr>
<tr><td><kbd>4</kbd></td><td>Smite Bush</td><td>15</td><td>Burns a bush away, leaving bare dirt.</td></tr>
<tr><td><kbd>5</kbd></td><td>Miracle Bush</td><td>40</td><td>Grows a bush that holds up to 20 berries, regrows three times as fast, and bears even in winter.</td></tr></table>

<h2>Watching your people</h2>
<p>Click a person (or press <kbd>N</kbd>) to follow them. The status panel then shows:</p>
<table><tr><th>Line</th><th>Meaning</th></tr>
<tr><td>Health</td><td>0 to 100. At zero they die. Health lost to hunger, cold or poison does not come back.</td></tr>
<tr><td>Satiety, Stomach</td><td>Food eaten goes into the stomach and is digested into satiety. With an empty stomach satiety falls; at zero satiety they starve, losing health. Under 60 satiety they drop everything to look for food.</td></tr>
<tr><td>Energy, Sleeps</td><td>Energy runs down while awake; they sleep about as many hours a night as shown.</td></tr>
<tr><td>Carrying</td><td>Things in hand, out of how many they can carry (a belt adds more).</td></tr>
<tr><td>Skills</td><td>Foraging, crafting, ranged (spear), fishing and cooking. Higher is better; the number in brackets is experience that adds to it.</td></tr>
<tr><td>Doing, Role</td><td>What they are doing right now, and their job in the tribe.</td></tr>
<tr><td>Chill, Heat, Hypothermia, Heat stress</td><td>Shown when they are cold or hot. A full load of chill turns into hypothermia, which costs health.</td></tr>
<tr><td>Age, Mood</td><td>How old they are of the age they will die at, and how happy they are.</td></tr>
<tr><td>Crafted, tool uses, coat</td><td>What they have made, how many uses their tools have left, and whether they wear a fur coat.</td></tr></table>

<h2>How your tribe gets through the year</h2>
<h3>Jobs</h3>
<p>Your people share out the work by what each is best at, and take new jobs whenever someone dies. Everyone eats first when they are hungry.</p>
<table><tr><th>Role</th><th>Work</th></tr>
<tr><td>Forager</td><td>Carries fiber, stone and sticks home to the stockpile, and picks berries for the winter.</td></tr>
<tr><td>Toolmaker</td><td>Makes the tribe's tools: a sharp stone, net, spear, fire drill, cooking stick and drying racks. Skins rabbits and sews fur coats.</td></tr>
<tr><td>Firekeeper</td><td>Builds the fire pit at home, lights it when it is cold, cooks fish and meat, and dries meat when there is no fire.</td></tr>
<tr><td>Fisher</td><td>Fishes the ponds with the net and brings the catch home.</td></tr>
<tr><td>Hunter</td><td>Spears rabbits (leaving enough to breed) and brings them home to be skinned.</td></tr></table>
<p>A tribe reduced to one person has no roles: the survivor does a little of everything.</p>

<h3>Summer: laying in</h3>
<p>While berries grow, your people hang berries and raw meat on drying racks at the stockpile. After a day they become dried food, which never goes bad. Nobody touches the store until winter, unless they are starving. A tribe needs a few hundred pieces each to last the winter.</p>
<h3>Winter: holding on</h3>
<p>From about the eighth month the berries stop and the nights fall well below freezing. People in fur coats hardly feel the cold; the rest crowd round the fire. They live on the dried store, fish and cooked meat until spring.</p>
{shot("winter.png", "Winter at the camp. Everyone wears a fur coat; the rows of small squares are the tribe's stockpile and its store of dried food.")}

<h2>Tips for a god</h2>
<div class="tip"><b>The first year decides everything.</b> In testing with no miracles, every tribe that lived through its first winter lasted three years or more. The tribes that die go in two ways: a world too poor in berry bushes to feed five people through the first summer, or a store too small for the first winter.</div>
<ul>
<li><b>Look at the bushes early.</b> If the minimap shows few bushes near the tribe, plant a <b>Miracle Bush</b> near their home. It keeps bearing through the winter, when nothing else does.</li>
<li><b>Save faith for winter.</b> Faith tops out at 100, so spend it before it is wasted in summer, but keep enough for <b>Manna</b> when people start to starve in the cold.</li>
<li><b>Follow the toolmaker</b> to see how the tribe is doing: what has been made, and whether there are coats for everyone.</li>
<li><b>Snakes are dangerous to everyone.</b> A bite costs about half a person's health. Only send one if you mean it, or to give your hunter something to do.</li>
<li><b>Speed up the quiet times.</b> Summer runs itself; run it at 8x or more, then slow down as autumn comes.</li>
</ul>

<h2>Changing the world</h2>
<p>Options can be added to the game's web address, for example <code>?lat=20&amp;day=600</code>:</p>
<table><tr><th>Option</th><th>Effect</th><th>Default</th></tr>
<tr><td><code>day=</code></td><td>Real seconds per game day</td><td>1440 (24 minutes)</td></tr>
<tr><td><code>lat=</code></td><td>Latitude in degrees: lower is warmer with milder winters</td><td>40</td></tr>
<tr><td><code>dpm=</code>, <code>mpy=</code></td><td>Days per month, months per year</td><td>30, 12</td></tr>
<tr><td><code>world=</code></td><td>World size: a number for an N by N world, or <code>screen</code> for a small one</td><td>32</td></tr></table>

<h2>Credits</h2>
<p>Code and design by the developer, with Claude, an AI agent. Tiles from the Urizen 1-bit tileset v2.0 by vurmux (CC0). Built with Odin, running as WebAssembly. For the rules and numbers behind the simulation, see the companion document <i>How the game works</i>.</p>
</body></html>"""

out = HERE / "players-guide.html"
out.write_text(html)
pdf = HERE / "players-guide.pdf"
subprocess.run(["google-chrome", "--headless", "--no-sandbox", "--disable-gpu", "--no-pdf-header-footer", f"--print-to-pdf={pdf}", out.as_uri()], check=True, capture_output=True)
out.unlink()
print(pdf)
