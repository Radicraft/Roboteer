#!/usr/bin/env python3
"""Builds docs/look/menus-blueprint-A2.html, the menus A2 staging review.

Direction A's UI is lifted unchanged from docs/look/menus-blueprint.html (its stylesheet,
its SVG defs and its five screens), and each screen's backdrop is swapped for a real Godot
render of one of the four A2 stagings (Arena/qa/menus_a2_capture.tscn). The leader lines
keep A's tags and elbows; only the dot on the machine moves, to the part's projected
screen position that the capture printed (anchors.json), so every leader still lands on
the part it names.

  python3 build_page.py [RENDER_DIR]

RENDER_DIR holds the raw captures (<v>_<screen>.png, <v>_<screen>.json with v = a..d).
With it, the backdrops are rebuilt (the scene darkened and softened under the plates, as
the brief asks) and anchors.json rewritten. Without it, the page is rebuilt from the
committed JPEGs and anchors.json.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LOOK = os.path.dirname(HERE)
SRC = os.path.join(LOOK, "menus-blueprint.html")
OUT = os.path.join(LOOK, "menus-blueprint-A2.html")
SCREENS = ["menu", "builder", "shop", "board", "result"]
A_BG = {"menu": "stage-menu", "builder": "stage-garage", "shop": "stage-partw",
        "board": "stage-faceoff", "result": "stage-showroom"}
KEYS = {"a": 1, "b": 2, "c": 3, "d": 4}

# Where A's plates sit on each screen (956 x 440 pt), from its markup: the scene is
# darkened and softened under these so it never fights the blue.
PLATES = {
    "menu": [(530, 60, 374, 364), (782, 12, 120, 52), (54, 352, 376, 68)],
    "builder": [(540, 8, 362, 424)],
    "shop": [(582, 58, 320, 372), (54, 76, 266, 206), (782, 12, 120, 52)],
    "board": [(54, 254, 848, 180)],
    "result": [(54, 164, 236, 212), (636, 8, 266, 368)],
}


def bake(render_dir):
    from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
    anchors = {}
    for v, n in KEYS.items():
        for sc in SCREENS:
            src = os.path.join(render_dir, f"{v}_{sc}.png")
            im = Image.open(src).convert("RGB")
            w, h = im.size
            k = w / 956.0
            mask = Image.new("L", im.size, 0)
            d = ImageDraw.Draw(mask)
            for (x, y, pw, ph) in PLATES[sc]:
                d.rectangle([x * k, y * k, (x + pw) * k, (y + ph) * k], fill=255)
            mask = mask.filter(ImageFilter.GaussianBlur(28 * k))
            soft = im.filter(ImageFilter.GaussianBlur(5 * k))
            soft = ImageEnhance.Brightness(soft).enhance(0.62)
            out = Image.composite(soft, im, mask)
            out.save(os.path.join(HERE, f"v{n}-{sc}.jpg"), quality=86, optimize=True)
            anchors[f"v{n}-{sc}"] = json.load(open(os.path.join(render_dir, f"{v}_{sc}.json")))
    json.dump(anchors, open(os.path.join(HERE, "anchors.json"), "w"), indent=1)


def pt(a, k=0.5):
    return (round(a[0] * k), round(a[1] * k))


def nearest(items, key=None):
    items = [i for i in items if key is None or i["key"] in key]
    return min(items, key=lambda i: i["dist"])["at"] if items else None


def anchor_points(sc, a):
    """The machine end of each of A's leaders on screen `sc`, in A's order."""
    wf = a["weapon_focus"]
    top = a["top"]
    if sc == "menu":
        return [wf, nearest(a["wheels"]), top]
    if sc == "builder":
        return [wf, top]
    if sc == "shop":
        return [wf]
    if sc == "board":
        return [a.get("opponent"), top]
    if sc == "result":
        return [nearest(a["wheels"], ["wheel_rl", "wheel_rr"]),
                nearest(a["armour"], ["armour_sides"]), wf]
    return []


def reland(fig, sc, a):
    """Move each leader's dot (and the polyline's first point) to the new anchor."""
    pts = anchor_points(sc, a)
    groups = re.findall(r'<g class="[^"]*">.*?</g>', fig)
    for g, p in zip(groups, pts):
        if p is None or p[2]:
            continue
        x, y = pt(p)
        x = min(max(x, 8), 948)
        y = min(max(y, 8), 432)
        m = re.search(r'points="(\d+),(\d+) ', g)
        ng = g.replace(f'cx="{m.group(1)}" cy="{m.group(2)}"', f'cx="{x}" cy="{y}"')
        ng = ng.replace(f'points="{m.group(1)},{m.group(2)} ', f'points="{x},{y} ')
        fig = fig.replace(g, ng, 1)
    return fig


def a_parts():
    s = open(SRC, encoding="utf-8").read()
    head = s[: s.index("</style>")]
    head = head[head.index("<link"):]
    body = s[s.index("<body>") + 6: s.index('<div class="wrap">')]
    sec = s[s.index('<section class="dir" id="dir-a">'): s.index('<section class="dir" id="dir-b">')]
    figs = re.findall(r'<figure><div class="phone">.*?</figure>', sec)[:5]
    out = {}
    for sc, f in zip(SCREENS, figs):
        assert A_BG[sc] in f, sc
        out[sc] = f
    return head, body, out


VARIANTS = [
    {
        "n": 1, "name": "Showroom, turned up",
        "line": "The stage the game already has, pushed hard: a dry ice bank rolling off the plinth, four moving heads sweeping through real haze behind the machine, a hard cold rim and embers drifting up through the key.",
        "character": "Premium and controlled, the closest to Gear.Club's showroom: the machine is the only warm thing in a cold, moving room.",
        "tradeoff": "Still a showroom. It is livelier than A but it does not say robot combat until the face-off; the embers need rationing so they never sit on a plate.",
        "cost": {"lights": "13 in frame, 16 on the face-off (1 shadowed): the stage's 8 plus 4 moving heads and a rim, all unshadowed spots",
                 "particles": "about 590 billboards in 10 emitters (the stage's own 280 at 1.6x, 36 embers, 160 motes)",
                 "fog": "4 fog volumes plus scene volumetric fog at 0.05",
                 "draw": "64 to 96 draw calls a frame (desktop capture, high tier)",
                 "assets": "none new",
                 "tiers": "Medium: drop the volumetric fog, keep the beam cards and half the particles. Low: A's stage as it is today."},
    },
    {
        "n": 2, "name": "In the arena",
        "line": "The plinth on the Coliseum floor with a full house in the bowl behind, the truss ring and its moving heads overhead, the gate lit up and a pyro column firing in the corner.",
        "character": "The show before the show: crowd, truss, pyro and the gate, straight from the fight's own venue, so the menu already feels like fight night.",
        "tradeoff": "The costliest by far (the whole venue behind every menu), and the Coliseum's red and blue grade tints the machine purple on the close screens unless the stage key wins.",
        "cost": {"lights": "14 to 18 in frame (2 shadowed): the venue's key and fill, its 4 kit lights at high tier, the stage rig, pyro flash",
                 "particles": "810 to 1,460 billboards in 9 to 18 emitters (venue motes, pyro columns and gerbs, dry ice)",
                 "fog": "7 fog volumes plus volumetric fog",
                 "draw": "92 to 135 draw calls a frame, the crowd batched into a few multimeshes",
                 "assets": "none new: the Coliseum and its kit are already in the pack",
                 "tiers": "Medium: the kit already halves the crowd and lights (LIGHT_BUDGET 2). Low: kit crowd off, a still of the bowl behind the plinth."},
    },
    {
        "n": 3, "name": "The gate",
        "line": "The machine on its mark in the mouth of the entrance gate before the walk-out: lit from inside the tunnel, dry ice spilling over the steel, the gate's lamp strips and pyro going up either side.",
        "character": "Anticipation: the walk-out moment, every menu a second before the doors open. The most cinematic silhouette of the four.",
        "tradeoff": "The gate is built alone from the kit (no arena wall in the shot), so the crowd is only implied, and the tunnel haze greys the close screens if it is turned up any further.",
        "cost": {"lights": "8 or 9 in frame, 12 on the face-off (1 shadowed): the stage rig, a backlight down the tunnel, a tunnel lamp, a warm spill",
                 "particles": "430 to 760 billboards in 9 to 14 emitters (dry ice, motes, the gate's two pyro points)",
                 "fog": "4 fog volumes plus volumetric fog at 0.012",
                 "draw": "63 to 91 draw calls a frame",
                 "assets": "none new: entrance_gate.glb, the pyro launcher and moving heads are kit pieces",
                 "tiers": "Medium: the tunnel as a beam card and one flame, no volumetrics. Low: the gate lamps and the backlight only."},
    },
    {
        "n": 4, "name": "Workshop pit at night",
        "line": "The machine standing in the workshop's test pit after hours, the tool wall and cabinets behind, halogens on tripods, a welder's sparks at the bench and a blueprint of the machine thrown across the floor from a projector in the roof.",
        "character": "Ties the staging to direction A: the plates on screen and the drawing on the floor are the same blueprint. Warm, lived in, the team's own place.",
        "tradeoff": "The least spectacle of the four and the workshop reads busier than a stage; the projected drawing is clearest on the main menu and softer on the close screens.",
        "cost": {"lights": "15 or 16 in frame, 18 on the face-off (2 shadowed): the workshop venue's own, a projector spot with the drawing as its gobo, a wash, the arc",
                 "particles": "about 360 to 510 billboards (the welder's plume, dust, a thin dry ice bank)",
                 "fog": "6 fog volumes (the venue's beam haze and a thin floor bank)",
                 "draw": "78 to 108 draw calls a frame",
                 "assets": "one 1024 px gobo texture (the machine's plan view); the rest is the workshop venue in the pack",
                 "tiers": "Medium: the projector as a decal, sparks halved. Low: the decal and the halogens only."},
    },
]
PICK = 2
PICK_WHY = ("It is the only staging that answers the owner's own words (\"more going on, dry ice, perhaps even an arena\") "
            "on every screen: crowd, truss, pyro and the gate are already built, tiered and in the pack, "
            "and on older phones it falls back to the showroom.")

SCREEN_CAP = {
    "menu": "<b>Main menu.</b> Career plate, rows and callouts as in A.",
    "builder": "<b>Builder, weapon tab.</b> Front mount and top armour called out on the machine.",
    "shop": "<b>Shop, weapons.</b> The front mount close up.",
    "board": "<b>Series board.</b> Hob Nail across the floor.",
    "result": "<b>Match result.</b> Damaged parts called out.",
}


def phone(fig, n, sc, anchors, large=False):
    f = fig.replace(f'src="menus-bp/{A_BG[sc]}.jpg"', f'src="menus-bp-a2/v{n}-{sc}.jpg"')
    f = reland(f, sc, anchors[f"v{n}-{sc}"])
    f = re.sub(r"<figcaption>.*?</figcaption>", "", f)
    f = f.replace('<figure><div class="phone">', '<figure><div class="phone%s">' % (" big" if large else ""), 1)
    cap = SCREEN_CAP[sc] if not large else "<b>Main menu, large.</b> A's UI over the real render."
    return f.replace("</figure>", f"<figcaption>{cap}</figcaption></figure>")


def cost_card(v):
    c = v["cost"]
    rows = "".join(f"<tr><th>{k}</th><td>{c[key]}</td></tr>" for k, key in [
        ("Lights", "lights"), ("Particles", "particles"), ("Fog", "fog"),
        ("Draw budget", "draw"), ("New assets", "assets"), ("Phone tiers", "tiers")])
    return f'<figure class="costcard"><h4>Phone cost</h4><table class="cost">{rows}</table></figure>'


CSS = """
.phone{width:874px;height:402px}
.phone.big{border-radius:52px}
.intro{max-width:92ch}
.vgrid{display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin:26px 0 8px}
@media (max-width:1000px){.vgrid{grid-template-columns:1fr 1fr}}
@media (max-width:560px){.vgrid{grid-template-columns:1fr}}
.vgrid a{color:inherit;text-decoration:none;display:block;background:#12161D;border-radius:12px;overflow:hidden}
.vgrid img{display:block;width:100%;aspect-ratio:874/402;object-fit:cover}
.vgrid div{padding:10px 12px 14px;font:400 14px/1.4 var(--chrome);color:#C6CDD5}
.vgrid b{display:block;color:var(--type);font:600 15px/1.3 var(--chrome);margin-bottom:3px}
.vgrid .rec{display:inline-block;margin-top:8px}
.bigwrap{margin:6px 0 30px}
.costcard{background:#12161D;border-radius:12px;padding:18px 20px;align-self:start}
.costcard h4{font:600 16px/1.2 var(--chrome);margin:0 0 10px}
table.cost{border-collapse:collapse;width:100%;font:400 14px/1.45 var(--chrome)}
.cost th{text-align:left;vertical-align:top;color:var(--dim2);font-weight:600;padding:6px 12px 6px 0;white-space:nowrap}
.cost td{color:#D5DAE0;padding:6px 0;border-top:1px solid rgba(255,255,255,.06)}
.cost tr:first-child td{border-top:0}
table.inv td:first-child{white-space:normal}
.num{font:600 13px/1 var(--chrome);color:#0A0C10;background:#A3ACB7;border-radius:4px;padding:5px 8px}
"""


def build():
    anchors = json.load(open(os.path.join(HERE, "anchors.json")))
    head, defs, figs = a_parts()
    html = ['<!doctype html>\n<html lang="en-GB"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1">\n'
            '<title>Blueprint menus A2</title>' + head + CSS + "</style></head><body>" + defs +
            '<div class="wrap">']
    html.append('<h1>Blueprint menus A2</h1>')
    html.append('<p class="intro">The owner picked direction A (Blueprint overlay) with one change: "the menu options work, '
                'but the visuals around the machine aren\'t quite right... we need more going on, dry ice etc. perhaps even an arena." '
                "So A's panels, rows, plates, leader lines and type (Saira Stencil One, Saira Semi Condensed, B612 Mono) are kept "
                "exactly, and only the 3D scene behind them is redesigned. <strong>Four stagings, each on the same five screens</strong> "
                "(main menu, builder, shop, Series board, match result), with the main menu again at a larger size.</p>")
    html.append('<p class="intro">Every backdrop is a real Godot render from the game\'s own assets, captured today in a Godot window '
                "(Forward+, high tier, 1912 x 880) with <code>Arena/qa/menus_a2_capture.tscn</code>: the live workshop stage "
                "with the proving slice Tinribs, and the Coliseum, the kit's entrance gate and the workshop venue around it. "
                "Everything on top is A's live HTML at 956 x 440 pt, shown here at 874 x 402. The scene is darkened and softened "
                "under each plate, and every leader's dot is moved to the part's projected position in that render, so the "
                "callouts still land on the flipper, the wheel or the armour they name. Nothing on the screens has a stroked "
                "edge or a skewed accent.</p>")
    # overview strip
    html.append('<div class="vgrid">')
    for v in VARIANTS:
        rec = '<span class="rec">Recommended</span>' if v["n"] == PICK else ""
        html.append(f'<a href="#v{v["n"]}"><img src="menus-bp-a2/v{v["n"]}-menu.jpg" alt="{v["name"]}, main menu backdrop" loading="lazy">'
                    f'<div><b>{v["n"]}. {v["name"]}</b>{v["line"]}{rec}</div></a>')
    html.append("</div>")
    for v in VARIANTS:
        n = v["n"]
        rec = '<span class="rec">Recommended</span>' if n == PICK else ""
        html.append(f'<section class="dir" id="v{n}"><div class="dhead"><span class="let">{n}</span><h2>{v["name"]}</h2>{rec}</div>')
        html.append(f'<p class="intro">{v["line"]}</p>')
        html.append(f'<div class="verdict"><div><b>Character</b>{v["character"]}</div><div><b>Trade-off</b>{v["tradeoff"]}</div></div>')
        html.append('<div class="bigwrap">' + phone(figs["menu"], n, "menu", anchors, large=True) + "</div>")
        html.append('<div class="grid2">')
        for sc in SCREENS:
            html.append(phone(figs[sc], n, sc, anchors))
        html.append(cost_card(v))
        html.append("</div></section>")
    # comparison
    html.append('<section class="dir" id="cost"><h2>Phone cost side by side</h2>')
    html.append('<p class="intro">Counted from the captures themselves (lights and emitters visible in the frame, draw calls '
                "from the renderer for that frame, on the desktop at the high tier). The phone runs Forward+ on Metal like the "
                "desktop, so the shape of the numbers carries over; the absolute frame time has to be measured on the device.</p>")
    html.append('<div class="tablewrap"><table class="inv"><tr><th>Staging</th><th>Lights</th><th>Particles</th><th>Fog</th><th>Draw calls</th><th>New assets</th></tr>')
    for v in VARIANTS:
        c = v["cost"]
        html.append(f'<tr><td>{v["n"]}. {v["name"]}</td><td>{c["lights"]}</td><td>{c["particles"]}</td><td>{c["fog"]}</td><td>{c["draw"]}</td><td>{c["assets"]}</td></tr>')
    html.append("</table></div></section>")
    pv = VARIANTS[PICK - 1]
    html.append('<section class="dir" id="rec"><h2>Recommendation</h2><div class="callout">')
    html.append(f'<p><strong>{pv["n"]}, {pv["name"]}.</strong> {PICK_WHY}</p>')
    html.append("<p>Take two things from the others. From 1, the moving heads sweeping through haze behind the machine on the "
                "close screens, where the bowl is out of frame. From 4, the projected blueprint on the floor under the plinth: "
                "it is the one element that ties the scene to the blue plates on top of it.</p>")
    html.append("<p>Rules to hold when it is built: the pyro fires on arrival at a screen and on a win, never on a loop; the crowd "
                "and the grade stay behind the plates (the darkening under them is part of the look, not a fix); and the stage key "
                "stays the brightest light on the machine, so it reads orange, not purple.</p>")
    html.append("</div></section>")
    html.append('<section class="dir" id="how"><h2>How these were made</h2>'
                '<p class="intro"><code>Godot --path Arena --audio-driver Dummy --resolution 1912x880 res://qa/menus_a2_capture.tscn -- '
                "--a2-variant=showroom|arena|gate|pit --a2-screen=menu|builder|shop|board|result --a2-out=FILE.png</code> saves the "
                "frame and prints the anchors and the frame's cost; <code>docs/look/menus-bp-a2/build_page.py</code> bakes the "
                "backdrops and rebuilds this page from A's own markup.</p></section>")
    html.append("</div>" + FIT_JS + "</body></html>")
    page = "\n".join(html)
    assert "—" not in page, "em dash on the page"
    open(OUT, "w", encoding="utf-8").write(page)
    print("wrote", OUT, len(page))


FIT_JS = """<script>
(function(){
  function fit(){
    document.querySelectorAll('.phone').forEach(function(p){
      var w=p.parentElement.clientWidth; if(!w) return;
      var cap=p.classList.contains('big')?1.4:874/956;
      var s=Math.min(cap,w/956); p.style.width=(956*s)+'px'; p.style.height=(440*s)+'px';
      p.style.borderRadius=(44*s)+'px'; p.firstElementChild.style.transform='scale('+s+')';
    });
  }
  window.addEventListener('resize',fit); if(document.fonts&&document.fonts.ready){document.fonts.ready.then(fit)} fit();
})();
</script>"""

if __name__ == "__main__":
    if len(sys.argv) > 1:
        bake(sys.argv[1])
    build()
