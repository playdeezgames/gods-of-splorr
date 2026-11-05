#!/usr/bin/env python3
"""Builds manual/how-the-game-works.pdf: HTML + inline SVG, printed by headless Chrome."""
import math, subprocess, pathlib

HERE = pathlib.Path(__file__).parent
INK, MUTED, GRID = "#222", "#666", "#ddd"
C1, C2, C3, C4 = "#2a6f97", "#c8553d", "#5b8e3a", "#8a6bbd"

def line_chart(xs, series, w=620, h=260, xlabel="", ylabel="", xticks=None, yticks=None, hline=None, band=None):
    L, R, T, B = 52, 14, 14, 40
    x0, x1 = min(xs), max(xs)
    ally = [y for _, ys in series for y in ys]
    y0, y1 = min(ally + [0] if min(ally) > 0 else ally), max(ally)
    pad = (y1 - y0) * 0.08; y0 -= pad if y0 < 0 else 0; y1 += pad
    sx = lambda x: L + (x - x0) / (x1 - x0) * (w - L - R)
    sy = lambda y: T + (1 - (y - y0) / (y1 - y0)) * (h - T - B)
    o = [f'<svg viewBox="0 0 {w} {h}" class="chart">']
    for t in yticks or []:
        o.append(f'<line x1="{L}" x2="{w-R}" y1="{sy(t)}" y2="{sy(t)}" stroke="{GRID}"/><text x="{L-6}" y="{sy(t)+4}" text-anchor="end" class="tk">{t:g}</text>')
    for t in xticks or []:
        o.append(f'<text x="{sx(t)}" y="{h-B+16}" text-anchor="middle" class="tk">{t:g}</text>')
    if band:
        a, b, col = band
        o.append(f'<rect x="{L}" y="{sy(b)}" width="{w-L-R}" height="{sy(a)-sy(b)}" fill="{col}" opacity="0.12"/>')
    if hline:
        v, lab = hline
        o.append(f'<line x1="{L}" x2="{w-R}" y1="{sy(v)}" y2="{sy(v)}" stroke="{C2}" stroke-dasharray="5 4"/><text x="{w-R-4}" y="{sy(v)-5}" text-anchor="end" class="tk" fill="{C2}">{lab}</text>')
    for (name, ys), col in zip(series, [C1, C2, C3, C4]):
        pts = " ".join(f"{sx(x):.1f},{sy(y):.1f}" for x, y in zip(xs, ys))
        o.append(f'<polyline points="{pts}" fill="none" stroke="{col}" stroke-width="2.4"/>')
    o.append(f'<line x1="{L}" x2="{L}" y1="{T}" y2="{h-B}" stroke="{INK}"/><line x1="{L}" x2="{w-R}" y1="{h-B}" y2="{h-B}" stroke="{INK}"/>')
    o.append(f'<text x="{(L+w-R)/2}" y="{h-6}" text-anchor="middle" class="ax">{xlabel}</text>')
    o.append(f'<text transform="translate(13 {(T+h-B)/2}) rotate(-90)" text-anchor="middle" class="ax">{ylabel}</text>')
    o.append('</svg>')
    return "".join(o)

def bar_chart(items, w=620, label_w=150, unit="", color=C1, colors=None, maxv=None, fmt="{:g}"):
    row = 26; h = len(items) * row + 10
    mx = maxv or max(v for _, v in items)
    o = [f'<svg viewBox="0 0 {w} {h}" class="chart">']
    for i, (name, v) in enumerate(items):
        y = 5 + i * row
        bw = (w - label_w - 70) * v / mx
        col = colors[i] if colors else color
        o.append(f'<text x="{label_w-8}" y="{y+16}" text-anchor="end" class="tk2">{name}</text>')
        o.append(f'<rect x="{label_w}" y="{y+3}" width="{max(bw,1):.1f}" height="17" fill="{col}" rx="2"/>')
        o.append(f'<text x="{label_w+bw+6}" y="{y+16}" class="tk2">{fmt.format(v)}{unit}</text>')
    o.append('</svg>')
    return "".join(o)

def box(x, y, w, h, text, kind="p"):
    fill = {"p": "#eef4f9", "d": "#fdf3e3", "s": "#e8f3e0", "e": "#fbe9e5"}[kind]
    lines = text.split("\n")
    if kind == "d":
        pts = f"{x+w/2},{y} {x+w},{y+h/2} {x+w/2},{y+h} {x},{y+h/2}"
        shape = f'<polygon points="{pts}" fill="{fill}" stroke="{INK}"/>'
    else:
        shape = f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{h/2 if kind in "se" else 5}" fill="{fill}" stroke="{INK}"/>'
    t = "".join(f'<text x="{x+w/2}" y="{y+h/2+4-(len(lines)-1)*6+i*12}" text-anchor="middle" class="fl">{l}</text>' for i, l in enumerate(lines))
    return shape + t

def arrow(x1, y1, x2, y2, label="", dashed=False):
    a = math.atan2(y2-y1, x2-x1); s = 6
    hd = f"{x2},{y2} {x2-s*math.cos(a-.4)},{y2-s*math.sin(a-.4)} {x2-s*math.cos(a+.4)},{y2-s*math.sin(a+.4)}"
    d = ' stroke-dasharray="4 3"' if dashed else ""
    lab = f'<text x="{(x1+x2)/2+4}" y="{(y1+y2)/2-3}" class="fl2">{label}</text>' if label else ""
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{INK}"{d}/><polygon points="{hd}" fill="{INK}"/>{lab}'

# ---- flowchart 1: the per-person turn
def turn_flow():
    W = 620; o = [f'<svg viewBox="0 0 {W} 560" class="chart">']
    steps = [
        ("Snake near: spear / no spear?", "Hunt it / flee"),
        ("Hungry, food in hand or near?", "Eat"),
        ("A fur coat in reach, none worn?", "Put it on"),
        ("Fire, fish or meat beside me?", "Cook / feed fire / fish"),
        ("Hungry or peckish?", "Look for food"),
        ("Chilled or tired in the cold?", "Go to a lit fire"),
        ("Anything for my role?", "Do my role's work"),
        ("Store short of winter food?", "Lay in berries"),
        ("Generalist with low mood?", "Fire / goal / craft"),
        ("Berries or material beside me?", "Gather"),
    ]
    y = 8
    for i, (q, a) in enumerate(steps):
        o.append(box(20, y, 250, 38, q, "d"))
        o.append(box(380, y+4, 220, 30, a, "p"))
        o.append(arrow(270, y+19, 380, y+19, "yes"))
        if i < len(steps) - 1:
            o.append(arrow(145, y+38, 145, y+52, "no"))
        y += 52
    o.append(box(60, y-4+0, 170, 28, "Drop something / wander", "s") if False else "")
    o.append('</svg>')
    return "".join(o).replace("</svg>", box(55, 530, 180, 26, "Otherwise: wander", "s") + arrow(145, 520, 145, 530) + "</svg>").replace('viewBox="0 0 620 560"', 'viewBox="0 0 620 565"')

def tech_flow():
    W, H = 620, 470; o = [f'<svg viewBox="0 0 {W} {H}" class="chart">']
    N = {}
    def n(k, x, y, t, kind="p", w=104, h=34): N[k] = (x, y, w, h); o.append(box(x, y, w, h, t, kind))
    n("fiber", 6, 6, "Fiber\n(grass)", "s"); n("stone", 120, 6, "Stone\n(stone field)", "s"); n("stick", 234, 6, "Stick\n(tree)", "s"); n("reed", 350, 6, "Reed\n(pond)", "s"); n("berry", 470, 6, "Berries\n(bush)", "s")
    n("twine", 6, 76, "Twine"); n("sharp", 120, 76, "Sharp stone\n(cutting tool)"); n("short", 234, 76, "Short stick"); n("basket", 350, 76, "Basket"); n("rack", 470, 76, "Drying rack\n(4 sticks)")
    n("net", 6, 146, "Net\n(4 twine)"); n("spear", 120, 146, "Spear"); n("bow", 350, 146, "Bow"); n("dried", 470, 146, "Dried food", "e")
    n("fish", 6, 216, "Fish"); n("cstick", 120, 216, "Cooking stick\n(+ sharp stone)"); n("stake", 234, 216, "Stake\n(+ sharp stone)"); n("rabbit", 470, 216, "Rabbit", "s")
    n("filet", 6, 286, "Filet"); n("pit", 120, 286, "Fire pit\n(8 stone+8 stick)"); n("drill", 292, 286, "Fire drill"); n("fur", 470, 286, "Fur + meat\n(+ sharp stone)")
    n("fire", 120, 356, "Lit fire"); n("coat", 470, 356, "Fur coat\n(3 fur + twine)"); n("meal", 6, 426, "Cooked meal", "e")
    def c(a, b, **k):
        ax, ay, aw, ah = N[a]; bx, by, bw, bh = N[b]
        o.append(arrow(ax+aw/2, ay+ah, bx+bw/2, by, **k))
    def path(pts):  # a routed arrow along the gaps between boxes
        for (x1, y1), (x2, y2) in zip(pts, pts[1:-1]): o.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{INK}"/>')
        o.append(arrow(*pts[-2], *pts[-1]))
    path([(120, 233), (115, 233), (115, 443), (110, 443)])  # cooking stick -> cooked meal
    for a, b in [("fiber","twine"),("stone","sharp"),("stick","short"),("sharp","spear"),("twine","spear"),("stick","rack"),("berry","rack"),("rack","dried"),
                 ("twine","bow"),("short","stake"),("bow","drill"),("stake","drill"),("reed","basket"),
                 ("twine","net"),("net","fish"),("fish","filet"),("drill","fire"),("pit","fire"),("fire","meal"),("filet","meal"),
                 ("rabbit","fur"),("fur","coat")]:
        try: c(a, b)
        except Exception: pass
    o.append('</svg>')
    return "".join(o)

def vitals_flow():
    o = ['<svg viewBox="0 0 620 120" class="chart">']
    o.append(box(10, 40, 100, 40, "Eat food\n+20 stomach")); o.append(box(160, 40, 110, 40, "Stomach\ndigests -5/h"))
    o.append(box(320, 40, 100, 40, "Satiety\n+5/h")); o.append(box(470, 20, 140, 36, "Satiety 0:\nhealth -1/h", "e")); o.append(box(470, 70, 140, 36, "Health 0: death\n(corpse rots)", "e"))
    o.append(arrow(110,60,160,60)); o.append(arrow(270,60,320,60)); o.append(arrow(420,50,470,38,"empty")); o.append(arrow(540,56,540,70))
    o.append(box(300, 92, 150, 24, "Stomach empty: satiety -1.5/h", "d") if False else "")
    o.append('</svg>'); return "".join(o)

# ---- data
days = list(range(0, 361, 3))
lat = math.radians(40); mean = 27 - 45*math.sin(lat)**2
temps = [mean + 22*math.sin(lat)*math.sin(math.tau*(d/360 - 0.06)) for d in days]
tx = list(range(0, 41))
bg = [0 if t <= 5 or t >= 38 else ((t-5)/17 if t <= 22 else (38-t)/16) for t in tx]
growth_days = sum(1 for d in range(360) if 5 < mean + 22*math.sin(lat)*math.sin(math.tau*(d/360-0.06)) < 38)

chart_temp = line_chart(days, [("Mean temp", temps)], xlabel="Day of year (12 months x 30 days)", ylabel="Daily mean °C", xticks=[0,60,120,180,240,300,360], yticks=[-5,0,5,10,15,20], hline=(5, "berries stop below 5 °C"), band=(5, 24, C3))
chart_berry = line_chart(tx, [("factor", bg)], xlabel="Temperature (°C)", ylabel="Growth factor (0-1)", xticks=[0,5,10,15,22,30,38], yticks=[0,0.25,0.5,0.75,1])
chart_cost = bar_chart([("Manna", 10), ("Smite Bush", 15), ("Snake", 25), ("Smite", 30), ("Miracle Bush", 40)], unit=" faith", colors=[C3, C2, C4, C2, C3], maxv=50)
chart_spoil = bar_chart([("Berry, fish, raw meat", 24), ("Fiber", 72), ("Twine, reed, rope", 240), ("Stick, basket, fur", 720)], unit=" h", color=C1, maxv=800)
chart_rot = bar_chart([("Corpse -> skeleton", 120), ("Skeleton gone", 1200)], unit=" h", color=C4, maxv=1400)
chart_dur = bar_chart([("Sharp stone", 12), ("Spear", 8), ("Net", 10), ("Fire drill", 6)], unit=" uses", color=C3, maxv=16)
# 16-world, 3-year simulation results, oldest first: (label, worlds alive at the end, mean years lived)
SIM = [("First manual", 0, 0.69), ("Rabbits and coats", 0, 0.67), ("Fires burn down, bug fixes", 0, 0.59),
       ("Drying racks", 4, 1.53), ("Idle hands store food", 7, 1.91), ("Store opens for the starving", 8, 1.98),
       ("Racks kept, idle tools set down", 9, 1.94)]
chart_sim = bar_chart([(n, a) for n, a, _ in SIM], label_w=210, unit=" of 16 alive", color=C3, maxv=16)
chart_years = bar_chart([(n, y) for n, _, y in SIM], label_w=210, unit=" years", color=C1, maxv=3, fmt="{:.2f}")
chart_cold = bar_chart([("No coat, no fire", 0), ("Fur coat", 15), ("Beside a lit fire", 15), ("Coat and fire", 30)], unit=" °C warmer", color=C2, maxv=36)

html = f"""<!doctype html><html><head><meta charset="utf-8"><title>Gods of SPLORR!! - How the game works</title>
<style>
@page {{ size: Letter; margin: 0.7in 0.75in; }}
body {{ font: 10.5pt/1.5 Helvetica, Arial, sans-serif; color:{INK}; }}
h1 {{ font-size: 26pt; margin: 0 0 4pt; }} h2 {{ font-size: 15pt; margin: 22pt 0 6pt; border-bottom: 2px solid {C1}; padding-bottom: 2pt; break-after: avoid; }}
h3 {{ font-size: 11.5pt; margin: 14pt 0 4pt; break-after: avoid; }}
.sub {{ color:{MUTED}; margin-bottom: 18pt; }}
table {{ border-collapse: collapse; width: 100%; margin: 8pt 0 10pt; font-size: 9.5pt; break-inside: avoid; }}
th {{ background:{C1}; color:#fff; text-align:left; padding: 4pt 7pt; }} td {{ padding: 3.5pt 7pt; border-bottom: 1px solid {GRID}; vertical-align: top; }}
tr:nth-child(even) td {{ background:#f6f8fa; }}
.chart {{ width:100%; height:auto; display:block; margin: 6pt 0 2pt; }} .tk {{ font: 9px Helvetica; fill:{MUTED}; }} .tk2 {{ font: 11px Helvetica; fill:{INK}; }}
.ax {{ font: 10px Helvetica; fill:{INK}; }} .fl {{ font: 11px Helvetica; fill:{INK}; }} .fl2 {{ font: 10px Helvetica; fill:{MUTED}; }}
figure {{ margin: 8pt 0 12pt; break-inside: avoid; }} figcaption {{ font-size: 9pt; color:{MUTED}; }}
.callout {{ background:#fdf3e3; border-left: 4px solid #e0a030; padding: 6pt 10pt; margin: 8pt 0; break-inside: avoid; }}
.pb {{ break-before: page; }} code {{ font-family: Menlo, monospace; font-size: 9pt; background:#f0f0f0; padding: 0 2pt; }}
</style></head><body>

<h1>Gods of SPLORR!!</h1>
<div class="sub">How the game works: a guide to the rules, numbers and behaviour of the simulation</div>

<h2>1. The big picture</h2>
<p>You are a god. A small tribe of five people lives on a 32x32 grid world with a day/night cycle, a calendar and weather. They split the work between them (foragers, a toolmaker, a firekeeper, a fisher and a hunter), craft tools, fish, hunt rabbits, cook, sew fur coats, dry food for the winter, grow old and die, mostly without your help. You hold <b>faith</b>, which you spend on five powers: you can feed them, smite them, or send snakes. The game ends when everyone is dead.</p>
<p>The simulation is deterministic pure logic (Odin, compiled to WebAssembly) driven by a clock; the browser only draws it and passes input. Everything below is taken from the game's source constants.</p>

<table><tr><th>System</th><th>What it does</th><th>Source file</th></tr>
<tr><td>World &amp; camera</td><td>Weighted terrain generation, zoom, follow, minimap</td><td>game.odin</td></tr>
<tr><td>Time</td><td>Clock, calendar, latitude-driven temperature and sun</td><td>time.odin</td></tr>
<tr><td>People</td><td>Vitals, skills, turn logic, ageing, death</td><td>people.odin</td></tr>
<tr><td>Food, ground</td><td>Berry bushes; fiber, sticks, stone, reeds, fish</td><td>food.odin, ground.odin</td></tr>
<tr><td>Items</td><td>Hands, recipes, durability, spoilage</td><td>items.odin</td></tr>
<tr><td>Fire, fishing, cooking</td><td>Pits, fuel, nets, skewers, meals</td><td>fire / fishing / cooking.odin</td></tr>
<tr><td>Mood</td><td>Dopamine and goal-seeking</td><td>mood.odin</td></tr>
<tr><td>Roles</td><td>Division of labour around a stockpile</td><td>roles.odin</td></tr>
<tr><td>Cold and heat</td><td>Chill, hypothermia, heat stress, warmth from fires and coats</td><td>thermal.odin</td></tr>
<tr><td>Rabbits</td><td>Grazing, breeding prey; meat and fur</td><td>rabbits.odin</td></tr>
<tr><td>Winter store</td><td>Drying racks and dried food</td><td>preserve.odin</td></tr>
<tr><td>Snakes, powers</td><td>Predators and the god's faith</td><td>snakes.odin, powers.odin</td></tr></table>

<h2>2. The world</h2>
<h3>Terrain</h3>
<p>Each cell is rolled from a weighted table at the start. Grass dominates; dirt appears only when a stone field is exhausted, and slowly greens back to grass next to existing grass (about once per two days).</p>
<table><tr><th>Terrain</th><th>Weight</th><th>Provides</th><th>Regrowth</th></tr>
<tr><td>Grass</td><td>100</td><td>5 fiber (also rabbit food)</td><td>0.02 / h</td></tr>
<tr><td>Tree</td><td>10</td><td>5 sticks</td><td>0.01 / h (a stick every four days)</td></tr>
<tr><td>Bush</td><td>5</td><td>berries (max 2.5-10 each), health 10</td><td>up to 0.125 / h, temperature-dependent</td></tr>
<tr><td>Stone field</td><td>3</td><td>20 stone, then becomes dirt</td><td>none</td></tr>
<tr><td>Pond</td><td>1</td><td>6 fish, 6 reeds</td><td>fish 0.01 / h, reeds 0.03 / h</td></tr>
<tr><td>Fire pit</td><td>built only</td><td>8 stick-units of fuel; not walkable</td><td>n/a</td></tr></table>

<h3>Time and weather</h3>
<p>A game day is 24 hours (1440 real seconds by default), a month 30 days, a year 12 months. Temperature depends on latitude (default 40): an annual mean, a seasonal swing that lags the sun by about three weeks, and a daily swing peaking mid-afternoon. At latitude 40 the annual mean is {mean:.1f} °C with a seasonal swing of about ±{22*math.sin(lat):.0f} °C, so winters are well below freezing. A game opens in the last month of spring, about day 60, so the tribe has one summer to prepare.</p>
<figure>{chart_temp}<figcaption>Figure 1. Daily mean temperature through the year at latitude 40. Only about {growth_days} of 360 days sit inside the berry-growing band (shaded); the rest of the year bushes are dormant.</figcaption></figure>

<h3>Berries</h3>
<p>Bushes regrow at a rate scaled by temperature: nothing below 5 °C or above 38 °C, a peak at 22 °C. A bush holds a random maximum of 2.5 to 10 berries.</p>
<figure>{chart_berry}<figcaption>Figure 2. Berry growth factor vs temperature (multiplied by 0.125 berries per hour).</figcaption></figure>
<div class="callout"><b>Bush health.</b> A bush has 10 health. A person who fails a forage roll damages it by 1; at zero health the bush is destroyed and all its berries fall to the ground. Bushes mend 0.05 health per hour.</div>

<h2>3. People</h2>
<p>Each person has a sex, melanin-based skin colour, 2 to 4 hands, an age (16-40 at start) and a lifespan (50-80 years), plus vitals (0-100) and skills that make crafting, foraging, fishing, cooking and spear-throwing succeed more often (an unskilled person still succeeds 25% of the time; a master always).</p>
<h3>Hunger and health</h3>
<figure>{vitals_flow()}<figcaption>Figure 3. Food passes through the stomach into satiety. With an empty stomach satiety falls 1.5 per hour; at zero satiety health falls 1 per hour.</figcaption></figure>
<table><tr><th>Quantity</th><th>Value</th></tr>
<tr><td>One berry fills the stomach</td><td>+20</td></tr>
<tr><td>A cooked meal fills the stomach</td><td>+40</td></tr>
<tr><td>Digestion</td><td>-5 stomach, +5 satiety per hour</td></tr>
<tr><td>Eats only when satiety is below</td><td>85 (and stomach below 25 with food in hand)</td></tr>
<tr><td>Hungry-person food hunt starts</td><td>satiety under 60</td></tr>
<tr><td>Dried berries / dried meat</td><td>+20 / +30</td></tr>
<tr><td>Sleep need</td><td>4 to 12 hours, default 8</td></tr>
<tr><td>Snake poison</td><td>5 health per hour; each bite adds 10 hours (max 30)</td></tr></table>

<h3>What a person does each turn</h3>
<p>Every ten game minutes each person takes one turn. The rules are tried in order and the first that applies is used; this is what the "Doing" line on the status panel shows.</p>
<figure>{turn_flow()}<figcaption>Figure 4. The decision order of a person's turn (asleep people skip it).</figcaption></figure>

<h2>4. Crafting and technology</h2>
<p>Crafted items take their ingredients from the hands or from the ground at the person's feet, so the tribe's stockpile works as a workbench. A failed craft usually wastes only the last ingredient. Each success raises that item's craft level, which improves the next attempt. A person's first-ever craft of an item pays 4x the mood reward.</p>
<figure>{tech_flow()}<figcaption>Figure 5. The tech tree. Green boxes are raw materials and prey, blue boxes crafted items, red boxes food made to last or to fill. Every ingredient arrow points to what it helps make.</figcaption></figure>
<table><tr><th>Item</th><th>Ingredients</th><th>Use</th><th>On failure</th></tr>
<tr><td>Twine</td><td>2 fiber</td><td>binding for most things</td><td>loses a fiber</td></tr>
<tr><td>Sharp stone</td><td>2 stone (one is kept)</td><td>the cutting tool: skins, fillets, whittles, cuts reeds and sticks</td><td>loses the stone</td></tr>
<tr><td>Short sticks</td><td>stick, cut with a sharp stone</td><td>two parts</td><td>loses the stick</td></tr>
<tr><td>Spear</td><td>sharp stone, stick, twine</td><td>hunt snakes and rabbits</td><td>loses the twine</td></tr>
<tr><td>Cooking stick</td><td>stick, cut with a sharp stone</td><td>skewer for cooking</td><td>-</td></tr>
<tr><td>Bow</td><td>stick, twine</td><td>part of fire drill</td><td>loses the twine</td></tr>
<tr><td>Stake</td><td>sharp stone on a short stick</td><td>part of fire drill</td><td>loses the short stick; the stone wears</td></tr>
<tr><td>Fire drill</td><td>bow, stake</td><td>lights a pit</td><td>loses nothing</td></tr>
<tr><td>Fire pit</td><td>8 stone + 8 sticks</td><td>fire for cooking and warmth</td><td>-</td></tr>
<tr><td>Net</td><td>4 twine</td><td>catch fish</td><td>loses 2 twine</td></tr>
<tr><td>Basket</td><td>5 reeds</td><td>+3 food slots that keep food from rotting</td><td>loses a reed</td></tr>
<tr><td>Rope, belt</td><td>2 twine / 2 rope</td><td>a worn belt adds 4 carry places</td><td>loses one input</td></tr>
<tr><td>Fur coat</td><td>3 fur + twine</td><td>worn at once; 15 °C less cold</td><td>loses the twine</td></tr>
<tr><td>Drying rack</td><td>4 sticks</td><td>dries 6 pieces of food at a time</td><td>breaks a stick</td></tr></table>
<figure>{chart_dur}<figcaption>Figure 6. Tool durability: uses before a tool breaks.</figcaption></figure>

<h3>Fire, fish and cooking</h3>
<p>A fire drill lights a pit that has fuel (wearing the drill). A lit pit burns a stick every four hours, so a full pit of eight sticks lasts a day and a night. People add sticks to nearly empty pits. The firekeeper lights the pit only when the air is under 16 °C: in warm weather a fire is wood wasted. A net catches fish from a pond; a sharp stone cuts a fish into two filets. Raw fish, snake or rabbit meat is skewered on a cooking stick and cooked beside a lit pit; a cooking failure burns the meat. Cooked meals fill the stomach twice as much as a berry.</p>

<h2>5. Mood and goals</h2>
<p>Each person has <b>dopamine</b> (0-100, starting 50, half-life 12 hours). A successful craft pays 10 points, 4x the first time, shrinking by 2% for each success at anything. Catching a fish and cooking a meal pay as well. When dopamine falls under 35 and a generalist (someone with no role, such as a lone survivor) is fed, they pursue a <i>goal</i>: the item that would feel best, working back through the recipes and walking to the raw materials. Building a fire pit needs 16 items, so people haul materials trip by trip to a pile at the chosen site and build when it is big enough.</p>

<h2>6. Roles: who does what</h2>
<p>With two or more people alive, each takes a role, filled in this order by whoever is best suited: forager, toolmaker, firekeeper, fisher, hunter, then more foragers. Roles are handed out again after every death; one person alone does everything as a generalist. Hunger always comes first, whatever the role.</p>
<p>Things are kept on the ground at the <b>stockpile</b>, the first person's starting cell. Crafting and cooking use what lies there directly.</p>
<table><tr><th>Role</th><th>Best suited</th><th>Work</th></tr>
<tr><td>Forager</td><td>foraging</td><td>Hauls fiber, stone and sticks to the stockpile (targets 14, 14 and 18), and picks berries for the winter store</td></tr>
<tr><td>Toolmaker</td><td>crafting</td><td>Makes a sharp stone, net, fire drill, cooking stick, spear and drying racks; skins rabbits; sews fur coats</td></tr>
<tr><td>Firekeeper</td><td>cooking</td><td>Builds the pit beside the stockpile, lights it in the cold, fillets and cooks, leaves cooked meals out for the hungry, and hangs raw meat to dry when there is no fire</td></tr>
<tr><td>Fisher</td><td>fishing</td><td>Takes the net, fishes and brings the catch home</td></tr>
<tr><td>Hunter</td><td>ranged</td><td>Takes the spear and hunts rabbits, leaving a breeding stock; otherwise hauls like a forager</td></tr></table>
<p>A specialist with nothing to do in their role lays in berries for the winter while the store is short.</p>

<h2>7. Cold and heat</h2>
<p>Under 10 °C a person builds up <b>chill</b> (0.25 per degree per hour, less 1 an hour the body fights off, and 1 more while asleep); over 30 °C they build up <b>heat</b>. At 100 the load turns into <b>hypothermia</b> or <b>heat stress</b>, which cost health in proportion and drain energy faster. Comfortable air clears chill and heat at 4 an hour, but hypothermia and heat stress fade only 0.5 an hour. Deaths are blamed on whichever harm did the most damage: starvation, poison, cold, heat, old age or a god's smiting.</p>
<p>Two things keep the cold off. A <b>lit fire pit</b> adds 15 °C right beside it, fading to half that two cells away; in the cold, a chilled or tired person walks to it and stays until warm. A <b>fur coat</b> takes 15 °C off the cold wherever its wearer goes (it does nothing about heat).</p>
<figure>{chart_cold}<figcaption>Figure 7. How much warmer the air feels to a person. At latitude 40 winter nights fall near -13 °C.</figcaption></figure>

<h2>8. Rabbits and fur</h2>
<p>A new world has 8 rabbits on grass (per 32x32). They graze grass fiber, hop towards more when hungry, and starve to a corpse after 48 hours without it. They bolt from people within 3 cells (60% of the time; otherwise they freeze). Fed rabbits breed, each about once every 5 days, while the season's mean is over 8 °C, up to 24. If fewer than 2 are left, one wanders in every 2 days.</p>
<p>A spear thrust kills a rabbit with the same chance as a snake (the hunter's ranged skill against the rabbit's dodge). The hunter only hunts while there are more rabbits than the starting 8, so the warren can breed back. The toolmaker skins each corpse with a sharp stone into rabbit meat and, on a good cut, fur. Three fur and a twine make a <b>fur coat</b>; the toolmaker sews one for each person who has none, and a dead person's coat is left on the ground for someone else.</p>

<h2>9. The winter store</h2>
<p>Berries stop growing when the season's mean falls under 5 °C, roughly from day 215 to day 365. The tribe lives through that on dried food.</p>
<ul>
<li><b>Racks.</b> The toolmaker lashes 4 sticks into a drying rack at the stockpile, and builds another (up to 3) when every rack is full. A rack holds 6 pieces of berries or raw meat; after a day they become dried berries or dried meat, which never spoil.</li>
<li><b>Laying in.</b> While berries grow, the store is under 250 pieces per person, and the bushes have at least 10 berries per person to spare, foragers pick berries for the racks before topping up raw materials (unless one is under a quarter of its target). Idle specialists help, putting down idle tools to free a hand. With no fire lit, the firekeeper dries the stockpile's raw meat instead of letting it rot.</li>
<li><b>Eating from it.</b> Nobody eats from the store until berries have stopped growing for the year, and even then only with no bush holding berries within 10 steps. Someone close to starving (satiety under 20) may eat from it in any season.</li>
</ul>

<h2>10. Things rot</h2>
<figure>{chart_spoil}<figcaption>Figure 8. Hours before dropped items spoil.</figcaption></figure>
<figure>{chart_rot}<figcaption>Figure 9. A dead person lies as a corpse for 5 days, then as a skeleton for 50 days.</figcaption></figure>
<p>Tools, stone, coats, racks and dried food never spoil. Food in a basket keeps too. People also drop what they carry by chance (2% per action), except tools and food kept for the larder.</p>

<h2>11. The god: faith and powers</h2>
<p>Faith starts at 50, regenerates 2 per hour, and is capped at 100. Press a power's number key to cast it at the cursor, or click its button to arm it and then click a map cell.</p>
<table><tr><th>Power</th><th>Cost</th><th>Effect</th></tr>
<tr><td>Manna</td><td>10</td><td>Drops a berry on the ground</td></tr>
<tr><td>Smite Bush</td><td>15</td><td>Scorches a bush away, leaving dirt</td></tr>
<tr><td>Snake</td><td>25</td><td>A poisonous snake that hunts nearby people and leaves after 72 hours</td></tr>
<tr><td>Smite</td><td>30</td><td>Kills the person standing there</td></tr>
<tr><td>Miracle Bush</td><td>40</td><td>A bush holding up to 20 berries, growing 3x faster, in any weather</td></tr></table>
<figure>{chart_cost}<figcaption>Figure 10. Faith cost of each power (faith regenerates 2 per hour, so Manna every 5 hours).</figcaption></figure>
<h3>Snakes</h3>
<p>A snake notices people within 6 cells, bites with a 60% chance (one-hour cooldown), and poisons. People within 3 cells flee unless they hold a spear, in which case they hunt it within 5 cells. A spear thrust hits with a chance set by the hunter's ranged skill against the snake's dodge (clamped to 5%-95%). A dead snake can be skinned with a sharp stone into meat and skin.</p>

<h2>12. Controls</h2>
<table><tr><th>Input</th><th>Action</th></tr>
<tr><td>Arrow keys / WASD, mouse</td><td>Move the cursor, pan the view</td></tr>
<tr><td>Z / X, mouse wheel</td><td>Zoom in / out (default 15x15 cells, minimum 5)</td></tr>
<tr><td>F / N</td><td>Follow a person / follow the next person</td></tr>
<tr><td>Click minimap</td><td>Centre the view there (cropped at the edge)</td></tr>
<tr><td>1-5</td><td>Cast a miracle at the cursor (or click a miracle button, then the map)</td></tr>
<tr><td>Space, + / -</td><td>Pause; game speed from 0.25x to 32x</td></tr>
<tr><td>P</td><td>Show or hide the miracle panel</td></tr>
<tr><td>M, H, C</td><td>Menu, help blurb, credits (Urizen tileset by vurmux, CC0)</td></tr>
<tr><td>R or click after game over</td><td>Restart</td></tr>
<tr><td>Gamepad</td><td>The whole game plays from the d-pad and two buttons: the d-pad moves the cursor; A casts the armed miracle at the cursor, follows or lets go of the person there, or begins again after a loss; B opens a command menu (miracles, following, zoom, speed, pause, controls) or disarms a miracle. Bumpers change speed and Start pauses.</td></tr></table>
<p>The window is a 16:9 stage: the map in the middle, the clock, faith and miracle buttons on the left, the minimap, zoom, follow and menu buttons and the status panel on the right. The URL accepts <code>?day=</code> (real seconds per game day), <code>&amp;dpm=</code>, <code>&amp;mpy=</code>, <code>&amp;lat=</code> and <code>?world=N</code>.</p>

<h2>13. How well does the tribe do? (balance report)</h2>
<p>A headless test runs 16 random worlds for up to three game years, with no snakes and no divine intervention. When this manual was first written <b>every tribe starved</b>, on average after 0.69 years, before or during the first winter. Rabbits, fur coats, working fires and the dried-food store have changed that: <b>{SIM[-1][1]} of 16 tribes now live through all three years</b>, and nobody dies of cold.</p>
<figure>{chart_sim}<figcaption>Figure 11. Tribes still alive after three years, as each change landed.</figcaption></figure>
<figure>{chart_years}<figcaption>Figure 12. Mean years lived across the 16 worlds (three is the most possible).</figcaption></figure>
<p>The tribes that still die all starve, in one of two ways:</p>
<ul>
<li><b>A berry-poor first summer.</b> In worlds with very few bushes, five people eat the berries faster than they grow and starve within months.</li>
<li><b>A short first store.</b> Worlds with somewhat more berries lay in only 300-650 pieces, far short of a winter's worth, and starve near the end of the first winter.</li>
</ul>
<p>Every tribe that lives through its first winter lasts all three years. The first year is when a god is needed: a Miracle Bush bears in any weather, and Manna feeds the starving.</p>
</body></html>"""

out = HERE / "how-the-game-works.html"
out.write_text(html)
pdf = HERE / "how-the-game-works.pdf"
subprocess.run(["google-chrome", "--headless", "--no-sandbox", "--disable-gpu", "--no-pdf-header-footer", f"--print-to-pdf={pdf}", out.as_uri()], check=True, capture_output=True)
out.unlink()
print(pdf)
