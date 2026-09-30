#!/usr/bin/env python3
"""Power train builder mockups (docs/look/power-train.html).

Writes nine 874 x 402 pt screens (three layouts x three states) to src/*.html over a real
desktop Godot stage render (wave C menus, staging 2: Tinribs on the plinth), then rasterises
each at 2x with a WKWebView snapshot tool (no browser, no simulator):

    swiftc -O snap.swift -o snap        # the tool is in the session scratchpad; any WKWebView
    python3 build_mockups.py /path/to/snap   #   takeSnapshot wrapper does the same job

Every number on the screens comes from `model()` below, which is the readout maths in
docs/design/power-train.md section 4, so the mockups and the spec cannot drift apart.
"""
import math
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src")

# ---------------------------------------------------------------------------
# The model (docs/design/power-train.md sections 2 to 4)
# ---------------------------------------------------------------------------
MOTOR = {  # speed, torque, draw, kg, level, feel
    "hobby": (1.15, 0.70, 0.70, 2, 1, "Hobby motor", "Nippy, lazy off the line, weak shove"),
    "mower": (1.00, 1.00, 1.00, 4, 1, "Mower motor", "Strong and steady. Start here"),
    "wiper": (0.72, 1.35, 0.65, 3, 6, "Wiper motor", "Slow and brutal, barely sips"),
    "starter": (1.20, 1.25, 1.80, 5, 18, "Starter motor", "Fast and strong, drinks the pack"),
    "forklift": (0.85, 1.70, 1.40, 8, 38, "Forklift motor", "Enormous shove, heavy, thirsty"),
    "hub": (1.18, 1.15, 0.90, 3, 58, "Hub motor", "Fast and frugal, hates wheel hits"),
}
GEAR = {"sprint": (1.2, 0.8), "balanced": (1.0, 1.0), "grunt": (0.8, 1.25)}
PACK = {  # capacity, kg, spin-up factor, level, name, feel
    "pocket": (220, 2, 1.15, 1, "Pocket pack", "Light. Starves a thirsty motor"),
    "standard": (360, 5, 1.0, 1, "Standard pack", "Lasts the fight on most machines"),
    "big": (480, 8, 0.7, 3, "Big pack", "Feeds a spinner. Faster spin-up"),
    "twin": (620, 12, 0.65, 48, "Twin pack", "Never runs out. Heavy"),
}
WHEEL = {"small": (0.85, 1 / 0.85, -0.5), "standard": (1.0, 1.0, 0.0), "big": (1.2, 1 / 1.2, 1.0)}
TYRE = {"grippy": (1.25, 0.9, 1.05), "allround": (1.0, 1.0, 1.0), "slick": (0.8, 1.15, 1.0)}
WEAPON_DRAW = {"flipper": 0.05, "horizontal_spinner": 0.5}
REST_OF_TINRIBS = 85.5   # Tinribs today (89.5 kg) less its Mower pair (4 kg)
BUDGET = 105
FIGHT_S, ENDGAME_S = 180, 120
SAG_AT = 0.25


def model(motor, gear="balanced", pack="standard", wheel="standard", tyre="allround",
          weapon="flipper", drive=(3.5, 3.2, 1.5, 1.0), hull_turn=0.85):
    top, turn, push, traction = drive
    s, t, d = MOTOR[motor][:3]
    gs, gt = GEAR[gear]
    ws, wt, wkg = WHEEL[wheel]
    tg, tt, td = TYRE[tyre]
    mass = REST_OF_TINRIBS + MOTOR[motor][3] + PACK[pack][1] + wkg
    v0 = top * s * gs * ws
    f = push * t * gt * wt
    load = (mass / 90) / (f / 1.5)
    v = min(v0 * (1 - 0.12 * load) / 0.88, v0)
    t_top = 0.9 * (mass / 90) * (v0 / 3.5) / (f / 1.5)
    grip = 1.2 * traction * tg
    raw = (f / 1.5) * (90 / mass)
    quarter = 0.7 * (3.2 * hull_turn) / (turn * hull_turn * tt)
    cap = PACK[pack][0]
    draw = d * 0.6 * td + WEAPON_DRAW[weapon] + 0.33
    return {
        "mass": mass, "v": v, "t_top": t_top, "push": min(raw, grip), "slips": raw > grip,
        "quarter": quarter, "run": cap / draw, "sag": (1 - SAG_AT) * cap / draw,
        "bell": 1 - FIGHT_S * draw / cap, "draw": draw, "cap": cap,
    }


def mmss(sec):
    sec = int(round(sec))
    return f"{sec // 60}:{sec % 60:02d}"


def charge(m, t):
    return max(0.0, 1 - t * m["draw"] / m["cap"])


def speed_scale(c):
    if c <= 0:
        return 0.35
    if c >= SAG_AT:
        return 1.0
    return 0.45 + 0.55 * c / SAG_AT


# ---------------------------------------------------------------------------
# Shared look: direction A, the blueprint overlay (docs/look/menus-blueprint.html CSS)
# ---------------------------------------------------------------------------
FONTS = "../../../../Roboteer/Fonts/"
CSS = """
@font-face{font-family:"Saira Stencil One";src:url("%(f)sSairaStencilOne-Regular.ttf")}
@font-face{font-family:"Saira Semi Condensed";font-weight:500;src:url("%(f)sSairaSemiCondensed-Medium.ttf")}
@font-face{font-family:"Saira Semi Condensed";font-weight:700;src:url("%(f)sSairaSemiCondensed-Bold.ttf")}
@font-face{font-family:"B612 Mono";font-weight:700;src:url("%(f)sB612Mono-Bold.ttf")}
:root{--fd:"Saira Stencil One",Impact,sans-serif;--fu:"Saira Semi Condensed","Arial Narrow",sans-serif;--fn:"B612 Mono",Menlo,monospace;
 --plate:rgba(14,58,140,.9);--gridm:rgba(255,255,255,.06);--gridM:rgba(255,255,255,.12);--ink:#fff;--dim:rgba(255,255,255,.66);
 --pbg:#fff;--pfg:#0E3A8C;--sbg:rgba(9,38,98,.94);--selbg:rgba(255,255,255,.2);--danger:#FF7A66;--dangerbg:#B8352A;
 --rule:rgba(255,255,255,.4);--rule2:rgba(255,255,255,.13);--hatch:rgba(255,255,255,.16)}
*{box-sizing:border-box}html,body{margin:0;background:#000}
.scr{position:relative;width:874px;height:402px;overflow:hidden;font-family:var(--fu);color:var(--ink);background:#000}
.bg{position:absolute;left:0;top:0;width:874px;height:402px}
.shade{position:absolute;inset:0;pointer-events:none}
.abs{position:absolute}
.plate{background-color:var(--plate);background-image:linear-gradient(var(--gridM) 1px,transparent 1px),linear-gradient(90deg,var(--gridM) 1px,transparent 1px),linear-gradient(var(--gridm) 1px,transparent 1px),linear-gradient(90deg,var(--gridm) 1px,transparent 1px);background-size:50px 50px,50px 50px,10px 10px,10px 10px;box-shadow:0 10px 30px rgba(0,0,0,.55)}
.sec{background:var(--sbg);box-shadow:0 8px 24px rgba(0,0,0,.6)}
.fd{font-family:var(--fd);font-weight:400}
.fn{font-family:var(--fn);font-weight:700;letter-spacing:-.03em}
.lab{font:700 11px/1.15 var(--fu);color:var(--dim)}
.btnS{display:flex;align-items:center;justify-content:center;background:var(--sbg);font:700 15px/1 var(--fu)}
.btnP{display:flex;align-items:center;justify-content:center;gap:12px;background:var(--pbg);color:var(--pfg);font:24px/1 var(--fd)}
.btnP .fn{font-size:15px;opacity:.7}
.tabs{display:flex;gap:2px}
.tab{flex:1;text-align:center;font:700 12.5px/24px var(--fu);color:var(--dim);background:rgba(255,255,255,.07)}
.tab.on{background:var(--pbg);color:var(--pfg)}
.chips{display:flex;gap:4px}
.chip{flex:1;text-align:center;font:700 11.5px/22px var(--fu);color:var(--dim);border-bottom:2px solid transparent}
.chip.on{color:#fff;border-bottom-color:#fff}
.row{display:flex;align-items:center;gap:8px;padding:0 10px}
.row+.row{border-top:1px solid var(--rule2)}
.row .nm{font:700 15px/1.05 var(--fu);white-space:nowrap}
.row .fl{font:500 12px/1.2 var(--fu);color:var(--dim);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.row .grow{flex:1;min-width:0}
.row .kg{font-size:12px;width:40px;text-align:right}
.row .st{font:700 12px/1 var(--fu);color:var(--dim);white-space:nowrap;text-align:right;min-width:52px}
.row.sel{background:var(--selbg)}
.row.sel .fl,.row.sel .st{color:#fff}
.row.lock{background-image:repeating-linear-gradient(135deg,var(--hatch) 0 1px,transparent 1px 7px)}
.row.lock .nm,.row.lock .kg,.row.lock .fl{opacity:.5}
.tag{position:absolute;background:#0E3A8C;padding:5px 9px;font:700 13px/1 var(--fu);white-space:nowrap;box-shadow:0 4px 12px rgba(0,0,0,.5)}
.tag .fn{font-size:12px;margin-left:6px;opacity:.85}
.cell .v{font-size:17px;line-height:1.1;margin-top:3px;white-space:nowrap}
.cell .v small{font-size:11px;opacity:.75}
.cell .d{font:700 11px/1.2 var(--fn);letter-spacing:-.03em;margin-top:2px;white-space:nowrap}
.up{color:#fff}.down{color:var(--danger)}.same{color:var(--dim)}
.warn{color:var(--danger)}
.note{font:500 12.5px/1.3 var(--fu);color:var(--dim)}
.note b{color:#fff;font-weight:700}
.dangerp{background:var(--dangerbg);color:#fff;font:700 12.5px/1.3 var(--fu);padding:7px 10px}
svg text{font-family:var(--fu);font-weight:700}
svg .n{font-family:var(--fn);font-weight:700}
.island{position:absolute;left:12px;top:158px;width:17px;height:86px;background:#000;border-radius:10px;z-index:20}
""" % {"f": FONTS}

HATCH_DEFS = """<defs>
<pattern id="hz" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
<rect width="6" height="6" fill="rgba(184,53,42,.55)"/><line x1="0" y1="0" x2="0" y2="6" stroke="#FF7A66" stroke-width="2"/></pattern>
<pattern id="hf" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
<line x1="0" y1="0" x2="0" y2="6" stroke="rgba(255,255,255,.28)" stroke-width="1.5"/></pattern>
</defs>"""


def page(body, bg="stage-builder-874.jpg", bg_style="", shade=""):
    return f"""<!doctype html><html lang="en-GB"><head><meta charset="utf-8"><title>mock</title>
<style>{CSS}</style></head><body><div class="scr">
<img class="bg" src="{bg}" style="{bg_style}" alt="">
<div class="shade" style="{shade}"></div>
<div class="island"></div>
{body}
</div></body></html>"""


def header():
    return """<div class="abs btnS" style="left:62px;top:16px;width:64px;height:34px">Back</div>
<div class="abs fd" style="left:140px;top:12px;font-size:31px;line-height:40px;text-shadow:0 2px 8px rgba(0,0,0,.6)">Tinribs</div>"""


def leader(x1, y1, x2, y2):
    """A leader line with its ring dot on the machine (diagram content, not an accent)."""
    return f"""<svg class="abs" style="left:0;top:0;overflow:visible" width="874" height="402">
<polyline points="{x1},{y1} {x2},{y1} {x2},{y2}" fill="none" stroke="#fff" stroke-width="1.3" opacity=".9"/>
<circle cx="{x2}" cy="{y2}" r="5.5" fill="none" stroke="#fff" stroke-width="1.6"/><circle cx="{x2}" cy="{y2}" r="1.8" fill="#fff"/></svg>"""


def delta(new, old, fmt, better_if_higher=True, unit=""):
    places = int(fmt[1]) if fmt.startswith(".") else 0
    diff = round(new - old, places)
    if diff == 0:
        return '<div class="d same">same</div>'
    good = (diff > 0) == better_if_higher
    sign = "+" if diff > 0 else "\u2212"
    return f'<div class="d {"up" if good else "down"}">{sign}{format(abs(diff), fmt)}{unit}</div>'


def cells(m, base, extra_speed=None):
    speed_d = delta(m["v"], base["v"], ".1f") if base else ""
    if extra_speed:
        speed_d = f'<div class="d down">{extra_speed}</div>'
    out = [
        ("Top speed", f'{m["v"]:.1f} <small>m/s</small>', speed_d),
        ("0 to top", f'{m["t_top"]:.2f} <small>s</small>', delta(m["t_top"], base["t_top"], ".2f", False) if base else ""),
        ("Push vs weight", f'{m["push"]:.2f}<small>×</small>',
         '<div class="d warn">wheels slip</div>' if m["slips"] else (delta(m["push"], base["push"], ".2f") if base else "")),
        ("Quarter turn", f'{m["quarter"]:.2f} <small>s</small>', delta(m["quarter"], base["quarter"], ".2f", False) if base else ""),
        ("Mass", f'{m["mass"]:.1f} <small>kg</small>', f'<div class="d same">{BUDGET - m["mass"]:.1f} spare</div>'),
    ]
    return out


def readout_strip(m, base, x, y, w, h=62, extra_speed=None):
    items = cells(m, base, extra_speed)
    share = [1.0, 0.95, 1.2, 1.05, 1.05][:len(items)]
    unit = (w - 20) / sum(share)
    html = [f'<div class="abs plate" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px;padding:8px 10px;display:flex">']
    for i, (lab, v, d) in enumerate(items):
        border = "border-left:1px solid var(--rule2);padding-left:8px;" if i else ""
        html.append(f'<div class="cell" style="width:{unit * share[i]:.1f}px;{border}"><div class="lab">{lab}</div><div class="v fn">{v}</div>{d}</div>')
    html.append("</div>")
    return "".join(html)


def fight_clock(m, w, h, ghost=None, speed=False, top=0, label_endgame=True, pad_l=4, pad_r=40):
    """The run time gauge: charge over the fight, 0:00 to 3:00 (and a little past), the
    endgame at 2:00, the sag zone below a quarter charge hatched in red, flat hatched grey.
    With `speed`, a second track shows top speed through the fight, which is the sag made
    visible: it falls from the moment the pack drops under a quarter."""
    t_end = 210
    x0, x1 = pad_l, w - pad_r
    X = lambda t: x0 + (x1 - x0) * t / t_end
    parts = [f'<svg width="{w}" height="{h}" style="display:block;overflow:visible">', HATCH_DEFS]

    def track(y0, y1, fn, ghost_fn=None, sag_fill=True, lab=None):
        Y = lambda f: y1 - (y1 - y0) * f
        parts.append(f'<rect x="{x0}" y="{y0}" width="{x1 - x0}" height="{y1 - y0}" fill="rgba(255,255,255,.05)"/>')
        # quarter line
        if sag_fill:
            parts.append(f'<line x1="{x0}" y1="{Y(SAG_AT)}" x2="{x1}" y2="{Y(SAG_AT)}" stroke="rgba(255,255,255,.25)" stroke-width="1"/>')
        # area split: fine / sag / flat
        steps = list(range(0, t_end + 1, 1))
        ok = [t for t in steps if fn(t)[1] == "ok"]
        sag = [t for t in steps if fn(t)[1] == "sag"]
        flat = [t for t in steps if fn(t)[1] == "flat"]
        for seg, fill in ((ok, "rgba(255,255,255,.16)"), (sag, "url(#hz)"), (flat, "url(#hf)")):
            if not seg:
                continue
            a, b = seg[0], seg[-1] + 1
            if b > t_end:
                b = t_end
            pts = [f"{X(a):.1f},{y1}"] + [f"{X(t):.1f},{Y(fn(t)[0]):.1f}" for t in range(a, b + 1)] + [f"{X(b):.1f},{y1}"]
            parts.append(f'<polygon points="{" ".join(pts)}" fill="{fill}"/>')
        if ghost_fn:
            pts = " ".join(f"{X(t):.1f},{Y(ghost_fn(t)):.1f}" for t in range(0, t_end + 1, 3))
            parts.append(f'<polyline points="{pts}" fill="none" stroke="rgba(255,255,255,.5)" stroke-width="2"/>')
        for seg, col in ((ok, "#fff"), (sag, "#FF7A66"), (flat, "#FF7A66")):
            if not seg:
                continue
            a, b = seg[0], min(seg[-1] + 1, t_end)
            pts = " ".join(f"{X(t):.1f},{Y(fn(t)[0]):.1f}" for t in range(a, b + 1))
            parts.append(f'<polyline points="{pts}" fill="none" stroke="{col}" stroke-width="2.4" stroke-linejoin="round"/>')
        if lab:
            parts.append(f'<text x="{x1 + 6}" y="{(y0 + y1) / 2 + 4}" font-size="11" fill="rgba(255,255,255,.66)">{lab}</text>')

    def state(c):
        return "flat" if c <= 0 else ("sag" if c < SAG_AT else "ok")

    charge_fn = lambda t: (charge(m, t), state(charge(m, t)))
    ghost_fn = (lambda t: charge(ghost, t)) if ghost else None
    if speed:
        vmax = 4.6
        sp = lambda t: (m["v"] * speed_scale(charge(m, t)) / vmax, state(charge(m, t)))
        gs = (lambda t: ghost["v"] * speed_scale(charge(ghost, t)) / vmax) if ghost else None
        track(top, top + 34, sp, gs, sag_fill=False, lab="Speed")
        track(top + 44, top + 78, charge_fn, ghost_fn, lab="Battery")
        yb = top + 78
    else:
        track(top, h - 16, charge_fn, ghost_fn)
        yb = h - 16
    # markers: endgame and bell
    for t, txt in ((ENDGAME_S, "House bot out"), (FIGHT_S, "Bell")):
        parts.append(f'<line x1="{X(t)}" y1="{top}" x2="{X(t)}" y2="{yb + 3}" stroke="#fff" stroke-width="1.2" opacity=".8"/>')
    for t in (0, 60, 120, 180):
        parts.append(f'<text class="n" x="{X(t)}" y="{yb + 14}" font-size="10.5" fill="rgba(255,255,255,.75)" text-anchor="{"start" if t == 0 else "middle"}">{mmss(t)}</text>')
    if label_endgame:
        parts.append(f'<text x="{X(ENDGAME_S)}" y="{top - 4}" font-size="10.5" fill="#fff" text-anchor="middle">house bot out</text>')
        parts.append(f'<text x="{X(FIGHT_S)}" y="{top - 4}" font-size="10.5" fill="#fff" text-anchor="middle">bell</text>')
    parts.append("</svg>")
    return "".join(parts)


# ---------------------------------------------------------------------------
# The numbers every screen shows
# ---------------------------------------------------------------------------
FITTED = model("mower")
TRY_STARTER = model("starter")
SAG = model("starter", pack="pocket")
QUICK = model("starter", gear="grunt", pack="big", wheel="big", tyre="grippy")
SAG_FLAT_SPEED = SAG["v"] * 0.35


def motor_rows(selected, fitted="mower", h=37, level=24, compact=False):
    out = []
    for key, (s, t, d, kg, lvl, name, feel) in MOTOR.items():
        cls = "row"
        if key == selected:
            cls += " sel"
        locked = lvl > level
        if locked:
            cls += " lock"
        st = "Fitted" if key == fitted else (f"Level {lvl}" if locked else ("Trying" if key == selected else ""))
        out.append(f'<div class="{cls}" style="height:{h}px"><div class="grow"><div class="nm">{name}</div>'
                   f'<div class="fl">{feel}</div></div><div class="st">{st}</div><div class="kg fn">{kg} kg</div></div>')
    return "".join(out)


def pack_rows(selected, h=40, level=24):
    out = []
    for key, (cap, kg, spin, lvl, name, feel) in PACK.items():
        cls = "row" + (" sel" if key == selected else "")
        locked = lvl > level
        if locked:
            cls += " lock"
        st = "Fitted" if key == selected else (f"Level {lvl}" if locked else "")
        m = model("starter", pack=key)
        runs = f'runs {mmss(m["run"])}'
        out.append(f'<div class="{cls}" style="height:{h}px"><div class="grow"><div class="nm">{name}</div>'
                   f'<div class="fl">{feel}</div></div><div class="st">{st or runs}</div><div class="kg fn">{kg} kg</div></div>')
    return "".join(out)


DRIVE_CHIPS = ["Layout", "Motor", "Gears", "Battery", "Wheels", "Quick"]


def chips(on):
    return '<div class="chips">' + "".join(f'<div class="chip{" on" if c == on else ""}">{c}</div>' for c in DRIVE_CHIPS) + "</div>"


def tabs(on="Drive"):
    return '<div class="tabs">' + "".join(
        f'<div class="tab{" on" if t == on else ""}">{t}</div>' for t in ["Chassis", "Drive", "Weapon", "Utility", "Armour", "Livery"]) + "</div>"


def done(x, y, w, m, h=48):
    return f'<div class="abs btnP" style="left:{x}px;top:{y}px;width:{w}px;height:{h}px">Done <span class="fn">{m["mass"]:.1f} kg</span></div>'


# ---------------------------------------------------------------------------
# Layout A: the Drive tab, split into rows, gauges framing the machine
# ---------------------------------------------------------------------------
A_SHADE = "background:linear-gradient(90deg,rgba(0,0,0,.35) 0%,rgba(0,0,0,0) 30%,rgba(0,0,0,0) 48%,rgba(0,0,0,.55) 100%),linear-gradient(180deg,rgba(0,0,0,.45) 0%,rgba(0,0,0,0) 32%,rgba(0,0,0,0) 72%,rgba(0,0,0,.6) 100%)"


def a_battery_plate(m, ghost=None, caption=""):
    return f"""<div class="abs plate" style="left:62px;top:310px;width:384px;height:74px;padding:5px 10px 0">
<div style="display:flex;align-items:baseline;gap:8px"><div class="lab" style="color:#fff">Battery</div>
<div class="note" style="font-size:11.5px">{caption}</div>
<div style="margin-left:auto" class="lab">Run time <span class="fn" style="font-size:14px;color:#fff">{mmss(m["run"])}</span></div></div>
<div style="margin-top:0">{fight_clock(m, 364, 50, ghost=ghost, top=13)}</div></div>"""


def a_motor():
    m, base = TRY_STARTER, FITTED
    body = header() + readout_strip(m, base, 62, 58, 384)
    body += '<div class="tag" style="left:236px;top:132px">Starter motor<span class="fn">one a side</span></div>' + leader(293, 155, 293, 255)
    body += f"""<div class="abs plate" style="left:462px;top:12px;width:350px;height:314px;padding:8px 8px 0">
{tabs()}<div style="margin:6px 0 4px">{chips("Motor")}</div>
<div>{motor_rows("starter")}</div></div>"""
    body += a_battery_plate(m, ghost=base, caption=f'{round(m["bell"] * 100)} % left at the bell <span style="opacity:.7">(fitted {round(base["bell"] * 100)} %)</span>')
    body += done(462, 334, 350, m)
    return page(body, shade=A_SHADE)


def a_sag():
    m, base = SAG, TRY_STARTER
    body = header() + readout_strip(m, base, 62, 58, 384, extra_speed=f"flat {SAG_FLAT_SPEED:.1f}")
    body += '<div class="tag" style="left:150px;top:132px">Pocket pack<span class="fn">2 kg</span></div>' + leader(197, 155, 197, 240)
    body += f"""<div class="abs plate" style="left:462px;top:12px;width:350px;height:314px;padding:8px 8px 0">
{tabs()}<div style="margin:6px 0 4px">{chips("Battery")}</div>
<div>{pack_rows("pocket")}</div>
<div class="dangerp" style="margin-top:8px">Slows from {mmss(m["sag"])} and goes flat at {mmss(m["run"])}. The house bot comes out at 2:00.</div>
<div class="note" style="margin:6px 4px 0">The <b>Standard pack</b> lasts to the bell on this motor, for 3 kg more.</div></div>"""
    body += a_battery_plate(m, ghost=base, caption=f'<span class="warn">Slows {mmss(m["sag"])}, flat {mmss(m["run"])}</span>')
    body += done(462, 334, 350, m)
    return page(body, shade=A_SHADE)


def slider(label, lo, hi, want, got, fmt, unit, w=320, note=""):
    X = lambda v: 8 + (w - 16) * (v - lo) / (hi - lo)
    miss = got < want - 0.03 * (hi - lo)
    return f"""<div style="margin:0 6px 5px"><div style="display:flex;align-items:baseline;gap:6px"><div class="lab" style="color:#fff">{label}</div>
<div class="note" style="font-size:11.5px">want <span class="fn" style="color:#fff">{format(want, fmt)}{unit}</span> · build reaches <span class="fn" style="color:{'#FF7A66' if miss else '#fff'}">{format(got, fmt)}{unit}</span></div></div>
<svg width="{w}" height="18" style="display:block"><rect x="8" y="7" width="{w - 16}" height="4" fill="rgba(255,255,255,.18)"/>
<rect x="8" y="7" width="{X(got) - 8:.1f}" height="4" fill="#fff"/>
<circle cx="{X(want):.1f}" cy="9" r="7.5" fill="#fff"/><circle cx="{X(got):.1f}" cy="9" r="5" fill="none" stroke="#fff" stroke-width="2"/></svg>{note}</div>"""


def quick_parts(sel, cols=2):
    rows = [("Motor", "Starter"), ("Gears", "Grunt"), ("Battery", "Big pack"), ("Wheels", "Big"), ("Tyres", "Grippy"), ("Changes", "5 parts")]
    return ('<div style="display:grid;grid-template-columns:1fr 1fr;column-gap:12px">' + "".join(
        f'<div style="display:flex;gap:6px;padding:2px 0;border-top:1px solid var(--rule2)"><div class="lab" style="width:48px;line-height:17px">{k}</div>'
        f'<div style="font:700 13px/17px var(--fu)">{v}</div></div>' for k, v in rows) + "</div>")


def a_quick():
    m, base = QUICK, FITTED
    body = header() + readout_strip(m, base, 62, 58, 384)
    body += f"""<div class="abs plate" style="left:462px;top:12px;width:350px;height:314px;padding:8px 8px 0">
{tabs()}<div style="margin:6px 0 8px">{chips("Quick")}</div>
{slider("Speed", 2.0, 5.0, 3.9, m["v"], ".1f", " m/s")}
{slider("Push", 0.5, 1.8, 1.4, m["push"], ".2f", "×")}
{slider("Battery at the bell", 0, 60, 30, m["bell"] * 100, ".0f", " %")}
<div style="margin:2px 6px 0">{quick_parts("x")}</div>
<div class="note" style="margin:4px 6px 0;font-size:12px">1.4× push needs the <b>Forklift motor</b> at Level 38.</div>
<div class="btnS" style="margin:6px 6px 0;height:30px;background:rgba(255,255,255,.14)">Fit these five</div></div>"""
    body += a_battery_plate(m, ghost=base, caption=f'{round(m["bell"] * 100)} % left at the bell')
    body += done(462, 334, 350, m)
    return page(body, shade=A_SHADE)


# ---------------------------------------------------------------------------
# Layout B: the power train drawn from above; tap a component
# ---------------------------------------------------------------------------
B_SHADE = "background:linear-gradient(90deg,rgba(0,0,0,.5) 0%,rgba(0,0,0,.2) 55%,rgba(0,0,0,0) 70%,rgba(0,0,0,.35) 100%),linear-gradient(180deg,rgba(0,0,0,.35) 0%,rgba(0,0,0,0) 25%,rgba(0,0,0,0) 75%,rgba(0,0,0,.55) 100%)"
# The stage framed to the right: the same render mirrored and scaled to 0.72 over a blurred copy of
# itself, standing in for a new right-hand camera anchor (the real screen gets its own framing).
B_SCALE, B_X, B_Y = 0.72, 890, 60
B_BG = "filter:blur(14px) brightness(.55);transform:scale(1.15)"
B_SHARP = (f'<img src="stage-builder-874.jpg" alt="" style="position:absolute;left:0;top:0;width:874px;height:402px;'
           f'transform-origin:0 0;transform:translate({B_X}px,{B_Y}px) scale(-{B_SCALE},{B_SCALE});'
           f'-webkit-mask-image:radial-gradient(ellipse 50% 50% at 30% 55%,#000 60%,transparent 100%)">')


def b_pt(x, y):
    return round(B_X - B_SCALE * x, 1), round(B_Y + B_SCALE * y, 1)


def plan_svg(focus, draw=None, changed=(), w=226, h=136):
    """Top-down schematic of Tinribs: front to the left, a motor a side chained to both wheels,
    the pack amidships, the flipper ram at the nose. Balloons 1 to 5 are tap targets. Drawn in a
    360 x 200 box and scaled to fit, so every stroke and label is sized for the scale."""
    draw = draw or {"motor": 5.0, "weapon": 1.4}
    hull = "70,70 115,48 330,48 352,62 352,138 330,152 115,152 70,130"
    s = [f'<svg width="{w}" height="{h}" viewBox="8 2 356 214" style="display:block;overflow:visible">']
    W = "#fff"
    s.append(f'<polygon points="{hull}" fill="rgba(255,255,255,.05)" stroke="{W}" stroke-width="2.2"/>')
    s.append(f'<polygon points="18,60 70,70 70,130 18,140" fill="none" stroke="{W}" stroke-width="1.8" opacity=".8"/>')
    s.append('<text x="22" y="165" font-size="16" fill="rgba(255,255,255,.75)">FLIPPER</text>')
    wf = "rgba(255,255,255,.3)" if focus in ("wheels", "tyres") or "wheels" in changed else "none"
    for (x, y) in [(110, 16), (110, 152), (290, 16), (290, 152)]:
        s.append(f'<rect x="{x}" y="{y}" width="54" height="32" rx="5" fill="{wf}" stroke="{W}" stroke-width="2.2"/>')
        for k in range(1, 6):
            s.append(f'<line x1="{x + k * 9}" y1="{y + 4}" x2="{x + k * 9}" y2="{y + 28}" stroke="{W}" stroke-width="1.2" opacity=".45"/>')
    for y in (58, 122):
        mf = "rgba(255,255,255,.35)" if focus == "motor" or "motor" in changed else "rgba(255,255,255,.08)"
        s.append(f'<rect x="196" y="{y}" width="48" height="22" fill="{mf}" stroke="{W}" stroke-width="2.2"/>')
        gf = "rgba(255,255,255,.35)" if focus == "gears" or "gears" in changed else "none"
        s.append(f'<rect x="176" y="{y + 2}" width="20" height="18" fill="{gf}" stroke="{W}" stroke-width="2"/>')
        yy = y + 11
        edge = 48 if y < 100 else 152
        for a, b in ((176, 137), (244, 317)):
            s.append(f'<line x1="{a}" y1="{yy}" x2="{b}" y2="{yy}" stroke="{W}" stroke-width="1.4" opacity=".7"/>')
        for x in (137, 317):
            s.append(f'<line x1="{x}" y1="{yy}" x2="{x}" y2="{edge}" stroke="{W}" stroke-width="1.4" opacity=".7"/>')
    bf = "rgba(255,255,255,.35)" if focus == "battery" or "battery" in changed else "rgba(255,255,255,.08)"
    mw, ww = draw["motor"], draw["weapon"]
    hot = focus == "battery" and mw > 6
    col = "#FF7A66" if hot else "#fff"
    s.append(f'<polyline points="262,94 220,94 220,80" fill="none" stroke="{col}" stroke-width="{mw}"/>')
    s.append(f'<polyline points="262,106 220,106 220,122" fill="none" stroke="{col}" stroke-width="{mw}"/>')
    s.append(f'<polyline points="262,100 70,100" fill="none" stroke="#fff" stroke-width="{ww}" opacity=".8"/>')
    s.append(f'<rect x="262" y="84" width="62" height="32" fill="{bf}" stroke="{W}" stroke-width="2.2"/>')
    s.append('<text x="293" y="106" font-size="15" fill="#fff" text-anchor="middle">PACK</text>')
    s.append('<rect x="84" y="88" width="46" height="24" fill="#0E3A8C" stroke="#fff" stroke-width="2"/>')
    s.append('<text x="107" y="105" font-size="14" fill="#fff" text-anchor="middle">RAM</text>')
    balloons = [("1", 220, 34, "motor"), ("2", 168, 34, "gears"), ("3", 293, 66, "battery"),
                ("4", 318, 202, "wheels"), ("5", 136, 202, "tyres")]
    for n, x, y, key in balloons:
        on = focus == key or key in changed
        s.append(f'<circle cx="{x}" cy="{y}" r="13" fill="{"#fff" if on else "#0E3A8C"}" stroke="#fff" stroke-width="2"/>')
        s.append(f'<text class="n" x="{x}" y="{y + 5.5}" font-size="16" fill="{"#0E3A8C" if on else "#fff"}" text-anchor="middle">{n}</text>')
    s.append("</svg>")
    return "".join(s)


def nomargin(d):
    return d.replace("<div", '<div style="margin:0"')


def b_numbers(m, base, extra_speed=None):
    items = cells(m, base, extra_speed)[:4]
    out = ['<div style="display:grid;grid-template-columns:1fr 1fr;border-top:1px solid var(--rule)">']
    for i, (lab, v, d) in enumerate(items):
        bl = "border-left:1px solid var(--rule2);padding-left:8px;" if i % 2 else ""
        bt = "border-top:1px solid var(--rule2);" if i >= 2 else ""
        out.append(f'<div class="cell" style="padding:2px 4px 2px;{bl}{bt}height:41px">'
                   f'<div class="lab">{lab}</div><div style="display:flex;align-items:baseline;gap:6px"><div class="v fn" style="font-size:14px;margin:0">{v}</div>'
                   f'{nomargin(d).replace("wheels slip", "slips")}</div></div>')
    out.append("</div>")
    return "".join(out)


def b_pop_rows(items, h=32):
    """Pop-over rows: name, status and kg on the first line, the feel words on the second."""
    out = []
    for name, feel, st, kg, sel, lock, st_cls in items:
        cls = "row" + (" sel" if sel else "") + (" lock" if lock else "")
        out.append(f'<div class="{cls}" style="height:{h}px;display:block;padding:3px 10px 0">'
                   f'<div style="display:flex;align-items:baseline;gap:6px"><div class="nm" style="font-size:13.5px;flex:1">{name}</div>'
                   f'<div class="st {st_cls}" style="min-width:0;font-size:11.5px">{st}</div><div class="kg fn" style="width:38px;white-space:nowrap;font-size:11px">{kg} kg</div></div>'
                   f'<div class="fl" style="font-size:11px">{feel}</div></div>')
    return "".join(out)


def b_frame(inner, m, base, caption, pop, extra_speed=None, extra=""):
    body = B_SHARP + header() + extra
    body += f"""<div class="abs plate" style="left:62px;top:58px;width:490px;height:326px">
<div style="padding:8px 8px 0">{tabs()}</div>
<div class="abs lab" style="left:10px;top:40px">TAP A NUMBER</div>
<div class="abs" style="left:14px;top:44px">{inner}</div>
<div class="abs" style="left:8px;top:182px;width:252px">{b_numbers(m, base, extra_speed)}</div>
<div class="abs" style="left:0;top:266px;width:490px;height:60px;border-top:1px solid var(--rule);padding:3px 10px 0">
<div style="display:flex;align-items:baseline;gap:8px"><div class="lab" style="color:#fff">Battery</div><div class="note" style="font-size:11.5px">{caption}</div>
<div style="margin-left:auto" class="lab">Run time <span class="fn" style="font-size:13px;color:#fff">{mmss(m["run"])}</span></div></div>
{fight_clock(m, 470, 42, ghost=base, top=13, pad_r=70)}</div>
{pop}</div>"""
    body += done(592, 334, 220, m)
    return page(body, bg_style=B_BG, shade=B_SHADE)


POP = "left:262px;top:36px;width:222px;height:226px;padding:5px 0 0"


def b_motor():
    m, base = TRY_STARTER, FITTED
    items = []
    for key, (sp, t, d, kg, lvl, name, feel) in MOTOR.items():
        lock = lvl > 24
        st = "Fitted" if key == "mower" else (f"Level {lvl}" if lock else ("Trying" if key == "starter" else ""))
        items.append((name, feel, st, kg, key == "starter", lock, ""))
    pop = f'<div class="abs sec" style="{POP}"><div class="lab" style="padding:0 10px 3px">1 · MOTOR, ONE A SIDE</div>{b_pop_rows(items)}</div>'
    wx, wy = b_pt(293.7, 255)
    tag = f'<div class="tag" style="left:{wx - 60}px;top:112px">Starter motor<span class="fn">one a side</span></div>' + leader(wx, 135, wx, wy)
    return b_frame(plan_svg("motor", draw={"motor": 7, "weapon": 2}), m, base,
                   f'{round(m["bell"] * 100)} % at the bell, fitted {round(base["bell"] * 100)} %', pop, extra=tag)


def b_sag():
    m, base = SAG, TRY_STARTER
    items = []
    for key, (cap, kg, spin, lvl, name, feel) in PACK.items():
        lock = lvl > 24
        mm = model("starter", pack=key)
        if lock:
            st, cls = f"Level {lvl}", ""
        elif mm["run"] < FIGHT_S:
            st, cls = f"flat {mmss(mm['run'])}", "warn"
        else:
            st, cls = f"{round(mm['bell'] * 100)} % at bell", ""
        items.append((name, feel, st, kg, key == "pocket", lock, cls))
    pop = (f'<div class="abs sec" style="{POP}"><div class="lab" style="padding:0 10px 3px">3 · BATTERY</div>{b_pop_rows(items, h=34)}'
           f'<div class="dangerp" style="margin:6px 8px 0;font-size:11.5px;padding:5px 8px">Thick red wires: the motors drink this pack dry.</div></div>')
    wx, wy = b_pt(197, 240)
    tag = f'<div class="tag" style="left:{wx - 50}px;top:112px">Pocket pack<span class="fn">2 kg</span></div>' + leader(wx, 135, wx, wy)
    return b_frame(plan_svg("battery", draw={"motor": 9, "weapon": 2}), m, base,
                   f'<span class="warn">slows {mmss(m["sag"])}, flat {mmss(m["run"])}</span>', pop,
                   extra_speed=f"flat {SAG_FLAT_SPEED:.1f}", extra=tag)


def triangle(want, got):
    """Quick build as one drag: a point inside Speed / Push / Staying power."""
    A, B, C = (95, 14), (14, 148), (176, 148)
    P = lambda wts: (A[0] * wts[0] + B[0] * wts[1] + C[0] * wts[2], A[1] * wts[0] + B[1] * wts[1] + C[1] * wts[2])
    pw, pg = P(want), P(got)
    return f"""<svg width="190" height="172" style="display:block;overflow:visible">
<polygon points="{A[0]},{A[1]} {B[0]},{B[1]} {C[0]},{C[1]}" fill="rgba(255,255,255,.06)" stroke="#fff" stroke-width="1.3"/>
<line x1="{A[0]}" y1="{A[1]}" x2="{(B[0] + C[0]) / 2}" y2="{B[1]}" stroke="rgba(255,255,255,.2)"/>
<line x1="{B[0]}" y1="{B[1]}" x2="{(A[0] + C[0]) / 2}" y2="{(A[1] + C[1]) / 2}" stroke="rgba(255,255,255,.2)"/>
<line x1="{C[0]}" y1="{C[1]}" x2="{(A[0] + B[0]) / 2}" y2="{(A[1] + B[1]) / 2}" stroke="rgba(255,255,255,.2)"/>
<text x="{A[0]}" y="{A[1] - 5}" font-size="11.5" fill="#fff" text-anchor="middle">SPEED</text>
<text x="{B[0] - 6}" y="{B[1] + 17}" font-size="11.5" fill="#fff">PUSH</text>
<text x="{C[0] + 8}" y="{C[1] + 17}" font-size="11.5" fill="#fff" text-anchor="end">STAYING POWER</text>
<circle cx="{pw[0]:.1f}" cy="{pw[1]:.1f}" r="9" fill="#fff"/>
<circle cx="{pg[0]:.1f}" cy="{pg[1]:.1f}" r="6" fill="none" stroke="#fff" stroke-width="2"/></svg>"""


def b_quick():
    m, base = QUICK, FITTED
    pop = f"""<div class="abs sec" style="{POP};padding:6px 10px 0">
<div class="lab" style="padding-bottom:6px">QUICK BUILD · DRAG THE DOT</div>
<div style="margin-left:4px">{triangle((0.42, 0.40, 0.18), (0.40, 0.32, 0.28))}</div>
<div class="note" style="font-size:11px;margin-top:10px">The ring is the nearest you can build. Lit numbers are the parts it changes.</div></div>"""
    return b_frame(plan_svg("", draw={"motor": 7, "weapon": 2}, changed=("motor", "gears", "battery", "wheels", "tyres")),
                   m, base, f'{round(m["bell"] * 100)} % at the bell', pop)


# ---------------------------------------------------------------------------
# Layout C: the fight clock. Every choice is shown as what it does across a 3 minute fight
# ---------------------------------------------------------------------------
C_BG = "filter:blur(14px) brightness(.5);transform:scale(1.15)"
C_SHARP = ('<img src="stage-generic-874.jpg" alt="" style="position:absolute;left:0;top:-92px;width:874px;height:402px;'
           '-webkit-mask-image:linear-gradient(180deg,#000 70%,transparent 100%)">')
C_SHADE = "background:linear-gradient(90deg,rgba(0,0,0,.3) 0%,rgba(0,0,0,0) 35%,rgba(0,0,0,0) 55%,rgba(0,0,0,.55) 100%),linear-gradient(180deg,rgba(0,0,0,.4) 0%,rgba(0,0,0,0) 25%,rgba(0,0,0,0) 55%,rgba(0,0,0,.7) 100%)"


def c_side(m, base, extra_speed=None):
    items = cells(m, base, extra_speed)
    return "".join(f'<div class="cell" style="padding:3px 0 4px;{"border-top:1px solid var(--rule2);" if i else ""}">'
                   f'<div class="lab">{lab}</div><div style="display:flex;align-items:baseline;gap:6px"><div class="v fn" style="font-size:14px;margin:0">{v}</div>'
                   f'{nomargin(d)}</div></div>'
                   for i, (lab, v, d) in enumerate(items[:4]))


def c_frame(m, base, right, headline, extra_speed=None):
    body = C_SHARP + header()
    body += f'<div class="abs" style="left:262px;top:20px;width:290px">{tabs()}</div>'
    body += f'<div class="abs plate" style="left:562px;top:12px;width:250px;height:314px;padding:8px 8px 0">{right}</div>'
    body += done(562, 334, 250, m)
    body += f"""<div class="abs plate" style="left:62px;top:230px;width:490px;height:154px;padding:7px 10px 0;display:flex;gap:10px">
<div style="flex:1;min-width:0"><div class="lab" style="color:#fff;white-space:nowrap">THE FIGHT CLOCK</div>
<div class="note" style="font-size:11.5px;white-space:nowrap;margin:0 0 1px">{headline}</div>
{fight_clock(m, 318, 106, ghost=base, speed=True, top=13, pad_r=50)}</div>
<div style="width:138px;border-left:1px solid var(--rule2);padding-left:8px">{c_side(m, base, extra_speed)}</div></div>"""
    return page(body, bg="stage-generic-874.jpg", bg_style=C_BG, shade=C_SHADE)


def c_rows_motor():
    out = []
    for key, (s, t, d, kg, lvl, name, feel) in MOTOR.items():
        if lvl > 24:
            continue
        sel = key == "starter"
        st = "Fitted" if key == "mower" else ("Trying" if sel else "")
        out.append(f'<div class="row{" sel" if sel else ""}" style="height:44px;padding:0 8px"><div class="grow"><div class="nm" style="font-size:14px">{name}</div>'
                   f'<div class="fl" style="font-size:11.5px;white-space:normal;line-height:1.15">{feel}</div></div>'
                   f'<div style="text-align:right"><div class="st" style="min-width:0">{st}</div><div class="fn" style="font-size:11px">{kg} kg</div></div></div>')
    out.append('<div class="note" style="padding:5px 8px;font-size:11px">Two more at Level 38 and 58.</div>')
    return "".join(out)


def c_cats(on):
    return '<div class="chips" style="margin:6px 0 4px">' + "".join(
        f'<div class="chip{" on" if c == on else ""}" style="font-size:11px">{c}</div>' for c in ["Layout", "Motor", "Gears", "Battery", "Wheels", "Plans"]) + "</div>"


def c_motor():
    m, base = TRY_STARTER, FITTED
    right = c_cats("Motor") + c_rows_motor()
    body = c_frame(m, base, right, 'Starter motor tried. Faint lines are the Mower fitted now.')
    return body


def c_sag():
    m, base = SAG, TRY_STARTER
    rows = []
    for key, (cap, kg, spin, lvl, name, feel) in PACK.items():
        sel = key == "pocket"
        mm = model("starter", pack=key)
        verdict = (f'<span class="warn">flat {mmss(mm["run"])}</span>' if mm["run"] < FIGHT_S else
                   (f'<span class="warn">slows {mmss(mm["sag"])}</span>' if mm["sag"] < FIGHT_S else f'{round(mm["bell"] * 100)} % at bell'))
        lock = lvl > 24
        rows.append(f'<div class="row{" sel" if sel else ""}{" lock" if lock else ""}" style="height:42px;padding:0 8px"><div class="grow"><div class="nm" style="font-size:14px">{name}</div>'
                    f'<div class="fl" style="font-size:11.5px">{"Level " + str(lvl) if lock else feel}</div></div>'
                    f'<div style="text-align:right"><div class="note" style="font-size:11.5px;font-weight:700">{verdict}</div><div class="fn" style="font-size:11px">{kg} kg</div></div></div>')
    right = c_cats("Battery") + "".join(rows) + '<div class="note" style="padding:6px 8px;font-size:11.5px">Starter motor fitted. It drinks the pack. The <b>Standard pack</b> lasts to the bell for 3 kg more.</div>'
    body = c_frame(m, base, right, f'<span class="warn">slows {mmss(m["sag"])}, flat {mmss(m["run"])}; the house bot is out at 2:00</span>',
                   extra_speed=f"flat {SAG_FLAT_SPEED:.1f}")
    return body


def c_quick():
    m, base = QUICK, FITTED
    plans = [
        ("Get there first", "Hobby motor, sprint gears, big wheels", False),
        ("Win the shove", "Starter motor, grunt gears, big pack, grippy tyres", True),
        ("Last the distance", "Mower motor, balanced, twin pack", False),
        ("Hit and run", "Starter motor, sprint gears, standard pack", False),
    ]
    rows = "".join(f'<div class="row{" sel" if sel else ""}" style="height:44px;padding:0 8px"><div class="grow"><div class="nm" style="font-size:14px">{n}</div>'
                   f'<div class="fl" style="font-size:11.5px;white-space:normal;line-height:1.15">{d}</div></div></div>' for n, d, sel in plans)
    right = c_cats("Plans") + rows + '<div class="btnS" style="margin:8px 6px 0;height:30px;background:rgba(255,255,255,.14)">Fit this plan</div>'
    body = c_frame(m, base, right, f'Win the shove · {round(m["bell"] * 100)} % at the bell')
    return body


SCREENS = {
    "a-motor": a_motor, "a-sag": a_sag, "a-quick": a_quick,
    "b-motor": b_motor, "b-sag": b_sag, "b-quick": b_quick,
    "c-motor": c_motor, "c-sag": c_sag, "c-quick": c_quick,
}


def main():
    snap = sys.argv[1] if len(sys.argv) > 1 else None
    os.makedirs(SRC, exist_ok=True)
    for name, fn in SCREENS.items():
        path = os.path.join(SRC, name + ".html")
        with open(path, "w") as fh:
            fh.write(fn())
        if snap:
            png = os.path.join(SRC, name + ".png")
            subprocess.run([snap, path, png, "874", "402"], check=True)
            from PIL import Image
            Image.open(png).convert("RGB").save(os.path.join(HERE, name + ".jpg"), quality=88)
            os.remove(png)
        print(name)
    for k, m in (("fitted", FITTED), ("try starter", TRY_STARTER), ("sag", SAG), ("quick", QUICK)):
        print(k, {a: (round(b, 2) if isinstance(b, float) else b) for a, b in m.items()}, mmss(m["run"]), mmss(m["sag"]))


if __name__ == "__main__":
    main()
