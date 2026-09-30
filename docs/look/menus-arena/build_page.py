#!/usr/bin/env python3
"""Builds docs/look/menus-arena-built.html: the blueprint menus in the arena, as built.

Before (today's app, simulator UI over today's stage render), the A2 mockup (staging 2),
and the build (simulator UI over the new stage render with its own anchors), per screen,
at 956 x 440 and 874 x 402. Images are referenced relatively; run from anywhere.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
LOOK = os.path.dirname(HERE)
OUT = os.path.join(LOOK, "menus-arena-built.html")

SCREENS = [
    ("menu", "Main menu", "The machine is the hero now: about 37 % of the width (the mockup had it at 17 %), "
     "standing clear above the title block, lit by the stage key so the orange reads orange. The gate is "
     "framed between the machine and the career plate, a jet on each of its launchers on arrival, the "
     "bowl and the truss ring's shafts above."),
    ("builder", "Builder", "Close: the bowl is out of frame, so four moving heads sweep through haze behind the "
     "machine as soft cones (no fog boxes, no hard edges)."),
    ("shop", "Shop", "The focused part pulled out and framed close, the arena dark behind."),
    ("board", "Series board", "The machine and the next opponent across the floor, in the top half over the "
     "schedule; the platform is down, so the projected blueprint of the machine shows on the floor."),
    ("result", "Match result", "The machine centred under the gate; after a win both jets fire with the gerbs."),
]


def rel(*p):
    return os.path.relpath(os.path.join(LOOK, *p), LOOK)


def exists(*p):
    return os.path.exists(os.path.join(LOOK, *p))


def img(path, alt):
    if not exists(path):
        return f'<div class="missing">{alt}<br>not captured</div>'
    return f'<img loading="lazy" src="{rel(path)}" alt="{alt}">'


def cost_rows():
    rows = []
    perf = os.path.join(HERE, "costs.json")
    if not os.path.exists(perf):
        return ""
    data = json.load(open(perf))
    for r in data:
        rows.append("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>")
    head = ("<tr><th>Tier</th><th>Draw calls</th><th>Lights in frame</th><th>Particles</th>"
            "<th>Video memory</th><th>Static memory</th><th>Venue build</th></tr>")
    return f'<table class="cost">{head}{"".join(rows)}</table>'


def main():
    parts = []
    for key, title, note in SCREENS:
        parts.append(f'<section><h2>{title}</h2><p>{note}</p>')
        parts.append('<div class="trio">')
        parts.append(f'<figure>{img(f"menus-arena/sim/before-{key}-956.jpg", "before")}'
                     '<figcaption><b>Before.</b> Today\'s app at 956 x 440.</figcaption></figure>')
        parts.append(f'<figure>{img(f"menus-arena/mockup/{key}.jpg", "mockup")}'
                     '<figcaption><b>Mockup.</b> Direction A over staging 2 (A2 page).</figcaption></figure>')
        parts.append(f'<figure>{img(f"menus-arena/sim/built-{key}-956.jpg", "built")}'
                     '<figcaption><b>Built.</b> The app at 956 x 440, over the real stage render.</figcaption></figure>')
        parts.append('</div><div class="duo">')
        parts.append(f'<figure>{img(f"menus-arena/sim/built-{key}-874.jpg", "built 874")}'
                     '<figcaption><b>Built</b> at 874 x 402.</figcaption></figure>')
        parts.append(f'<figure>{img(f"menus-arena/stage/built-{key}-956.jpg", "stage")}'
                     '<figcaption>The stage alone (desktop Godot, high tier).</figcaption></figure>')
        parts.append('</div></section>')

    others = []
    sim_dir = os.path.join(HERE, "sim")
    if os.path.isdir(sim_dir):
        for f in sorted(os.listdir(sim_dir)):
            if f.startswith("built-") and f.endswith("-956.jpg"):
                name = f[len("built-"):-len("-956.jpg")]
                if name not in [s[0] for s in SCREENS]:
                    others.append(f'<figure>{img("menus-arena/sim/" + f, name)}<figcaption>{name.replace("-", " ").capitalize()}</figcaption></figure>')

    extras = [
        ("extra-loading-1", "Loading, row 2: the machine is being built in the dark, the venue down with the rig."),
        ("extra-loading-4", "Loading, lights row: the venue comes up with the stage lights; the menu arrives over the same frame."),
        ("extra-menu-move", "A move in progress: builder to main menu (0.75 s, eased)."),
        ("extra-result-win", "Result after a win: both jets and the gerbs."),
        ("extra-tier-medium", "Medium tier: the kit's halved crowd and lights, no volumetric fog."),
        ("extra-tier-low", "Low tier: the bowl without its people, no jets, no shafts."),
        ("extra-board-noblueprint", "Owner call 1: the board with the projected blueprint switched off (MenuVenue.BLUEPRINT)."),
        ("extra-jet-co2", "Owner call 2: the jets as white CO2 instead of flame (MenuVenue.JET_STYLE = \"co2\")."),
    ]
    extra_html = "".join(f'<figure>{img("menus-arena/stage/" + n + ".jpg", n)}<figcaption>{c}</figcaption></figure>'
                         for n, c in extras)

    html = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Menus in the arena</title>
<style>
:root{{--bg:#0A0C10;--card:#12161D;--type:#F2F4F7;--dim:#A3ACB7;--rule:rgba(255,255,255,.08)}}
@media (prefers-color-scheme: light){{:root:not([data-theme="dark"]){{--bg:#F4F5F7;--card:#FFFFFF;--type:#11151B;--dim:#5A6470;--rule:rgba(0,0,0,.08)}}}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--type);font:16px/1.5 -apple-system,BlinkMacSystemFont,"Helvetica Neue",Arial,sans-serif}}
.wrap{{max-width:1400px;margin:0 auto;padding:40px 16px 100px}}
h1{{font-size:36px;line-height:1.1;margin:0 0 12px}}
h2{{font-size:24px;margin:56px 0 6px}}
p{{color:var(--dim);max-width:90ch;margin:0 0 14px}}
p b{{color:var(--type)}}
.trio{{display:grid;grid-template-columns:repeat(3,1fr);gap:14px}}
.duo{{display:grid;grid-template-columns:repeat(2,1fr);gap:14px;margin-top:14px}}
.grid{{display:grid;grid-template-columns:repeat(2,1fr);gap:14px}}
@media (max-width:900px){{.trio,.duo,.grid{{grid-template-columns:1fr}}}}
figure{{margin:0}}
img{{width:100%;display:block;border-radius:8px;background:#000}}
figcaption{{font-size:13.5px;color:var(--dim);margin-top:6px}}
figcaption b{{color:var(--type)}}
.missing{{aspect-ratio:956/440;border-radius:8px;background:var(--card);color:var(--dim);display:flex;align-items:center;justify-content:center;text-align:center;font-size:13px}}
table.cost{{border-collapse:collapse;width:100%;font-size:14px;margin:10px 0}}
.cost th,.cost td{{text-align:left;padding:8px 10px;border-top:1px solid var(--rule)}}
.cost th{{color:var(--dim);font-weight:600}}
.tablewrap{{overflow-x:auto}}
</style></head><body><div class="wrap">
<h1>Menus in the arena</h1>
<p>Direction A, the blueprint overlay, built into the app over staging 2: the machine on its plinth on the
Coliseum floor, the crowd in the bowl, the truss ring's shafts, the gate lit, pyro on arrival and on a win.
<b>Built</b> images are the app's own SwiftUI layer on the simulator (iPhone 17 Pro Max and iPhone 17 Pro)
standing over a real desktop Godot render of the same screen, with the leader lines landed from that render's
own <code>stage_anchors</code>; the simulator cannot draw the live stage itself.</p>
<p><b>Fixed from the mockup:</b> the machine is framed large on the main menu; the venue's red and blue light
never reaches the machine (its lights leave the machine's render layer out and the ambient is neutral), so
the stage key is the brightest light on it and the orange stays orange; the crowd is staged for depth (front
rows lit by the floods and falling off, a faint cold rim, phone glints, the back of the bowl sinking to dark)
through the venue kit's own crowd interface; the pyro is a narrow fast jet off the gate's own launchers,
fired on arrival and on a win and never looping; the close screens get moving heads through soft haze
cones; a blueprint of the machine is projected on the floor round the plinth.</p>
{''.join(parts)}
<h2>Every other screen that shows the stage</h2>
<p>The generic framing: the machine in the clear left, turning slowly, the arena behind. Fixed on the way:
the garage lists every machine at 402 pt, the retry, replays and events sentences sit on plates clear of the
machine, ladder names never wrap, the quick fight arena cards no longer run into the Opponent heading, and
the scouting report fits or scrolls in its own column with FIGHT always on screen. 956 x 440 shown; the
874 x 402 set is in <code>menus-arena/sim/built-*-874.jpg</code>.</p>
<div class="grid">{''.join(others) or '<p>Not captured yet.</p>'}</div>
<h2>Loading hand over, moves, tiers and the two owner calls</h2>
<div class="grid">{extra_html}</div>
<h2>Cost</h2>
<p>Desktop Godot at 1912 x 880, main menu, staging against today's showroom (in brackets). Relative numbers
only; the phone's own frame time is owed from a device run.</p>
<div class="tablewrap">{cost_rows()}</div>
</div></body></html>
"""
    open(OUT, "w").write(html)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
