# Pacing gauntlet

2026-09-27, wave B pacing engineer. The owner, after playing: "it's easy to just drive around
or get stuck, without much drama or skill." This page measures that in AI-vs-AI career fights.

Harness: `Arena/qa/pacing_gauntlet.gd` (one JSON line per fight), table: `Tools/pacing_table.py`.

    Godot --headless --fixed-fps 60 --path Arena --script qa/pacing_gauntlet.gd -- \
        --arenas=yard,grinder,drop_zone,furnace,crush,coliseum \
        --weapons=flipper,horizontal_spinner,crusher,saw --seeds=11,22,33 \
        --secs=180 --endgame=120 --house=career --out=/tmp/p.jsonl
    python3 Tools/pacing_table.py /tmp/p.jsonl

Set-up: 6 arenas x 4 subject weapons x 3 seeds = 72 fights of 3:00 with the endgame at 2:00 and
the career house bot for the arena. The subject is the weapons gauntlet's legal build at
national/brawler; the opponent is the wedge flipper (a box bar spinner when the subject IS the
flipper) at regional/technician. So these numbers are NOT the weapons gauntlet's (the Yard only,
2:30, no house bot: 68 % judges); they are the career fight the owner plays.

Columns: **KO/core** a knockout count or a core kill; **hazard KO** one with hazard damage in the
loser's last 3 s; **ring-out / pit** out of the arena (the Drop Zone's pit counted apart);
**blows/min** bot-on-bot damage events (0.25 s apart = one blow), both machines, and per stage
window; **first hit** median seconds to the first blow; **stuck** % of the fight a machine sat
still (< 0.05 m/s, upright) more than 1.5 m from the other, per machine; **mean dist** between
the chassis; **hazard contacts/min** arena damage visits (1 s apart = one), **credited** those
with the other machine within 2 m in the last 2 s (the old hazard credit rule); **payoffs** the
new named moments (stages build only).

## Baseline: HEAD e994cd3 (before any wave B change), isolated worktree

| set | fights | to judges | KO/core | hazard KO | ring-out | pit | mean length s | blows/min | blows/min by stage (0-45/45-90/90-120/120-155/155+) | first hit s (median) | stuck (% of fight, per machine) | mean dist m | hazard contacts/min | credited hazard/min | payoffs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| all | 72 | 33% | 36 | 3 | 3 | 6 | 138.7 | 8.10 | 11.2 / 7.4 / 6.1 / 4.8 / 5.3 | 5.8 | 2% | 1.36 | 3.60 | 3.27 | 0 |
| yard | 12 | 42% | 6 | 0 | 1 | 0 | 143.2 | 8.27 | 11.5 / 8.6 / 5.6 / 6.2 / 6.4 | 6.8 | 2% | 1.61 | 2.52 | 2.33 | 0 |
| grinder | 12 | 58% | 5 | 0 | 0 | 0 | 159.5 | 7.35 | 12.7 / 6.0 / 6.7 / 3.4 / 4.5 | 4.1 | 3% | 1.41 | 3.10 | 2.71 | 0 |
| drop_zone | 12 | 8% | 4 | 1 | 0 | 6 | 123.8 | 8.31 | 10.9 / 7.5 / 6.1 / 7.1 / 9.2 | 4.0 | 1% | 1.20 | 2.52 | 2.46 | 0 |
| furnace | 12 | 25% | 8 | 1 | 0 | 0 | 132.5 | 7.48 | 9.9 / 5.9 / 7.0 / 5.1 / 2.9 | 5.7 | 4% | 1.34 | 5.09 | 4.51 | 0 |
| crush | 12 | 25% | 7 | 0 | 2 | 0 | 120.3 | 9.57 | 12.2 / 7.9 / 6.1 / 4.1 / 3.0 | 4.5 | 2% | 1.30 | 4.20 | 4.07 | 0 |
| coliseum | 12 | 42% | 6 | 1 | 0 | 0 | 152.9 | 7.64 | 10.1 / 8.4 / 5.4 / 3.8 / 7.2 | 9.4 | 1% | 1.33 | 4.13 | 3.57 | 0 |
| crusher | 18 | 22% | 12 | 0 | 1 | 1 | 117.6 | 3.60 | 4.2 / 3.4 / 1.6 / 3.3 / 5.3 | 18.1 | 0% | 1.20 | 4.46 | 4.18 | 0 |
| flipper | 18 | 22% | 10 | 1 | 1 | 2 | 133.6 | 9.80 | 15.1 / 5.7 / 7.6 / 4.6 / 5.5 | 5.7 | 3% | 1.46 | 4.44 | 4.16 | 0 |
| horizontal_spinner | 18 | 39% | 9 | 1 | 0 | 1 | 152.1 | 9.13 | 13.4 / 8.6 / 5.7 / 4.7 / 5.7 | 4.6 | 4% | 1.60 | 3.47 | 2.83 | 0 |
| saw | 18 | 50% | 5 | 1 | 1 | 2 | 151.5 | 9.89 | 12.1 / 11.3 / 8.2 / 6.0 / 4.8 | 3.0 | 1% | 1.19 | 2.01 | 1.93 | 0 |

## After A + E (stages and payoffs), e994cd3 + my two commits only, isolated worktree

| set | fights | to judges | KO/core | hazard KO | ring-out | pit | mean length s | blows/min | blows/min by stage (0-45/45-90/90-120/120-155/155+) | first hit s (median) | stuck (% of fight, per machine) | mean dist m | hazard contacts/min | credited hazard/min | payoffs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| all | 72 | 36% | 31 | 6 | 3 | 6 | 143.2 | 8.17 | 10.9 / 7.7 / 5.7 / 6.3 / 4.1 | 5.8 | 2% | 1.37 | 3.98 | 3.62 | 116 |
| yard | 12 | 75% | 2 | 0 | 1 | 0 | 163.2 | 8.02 | 10.1 / 9.0 / 7.5 / 9.5 / 2.2 | 6.5 | 2% | 1.43 | 3.89 | 3.72 | 18 |
| grinder | 12 | 50% | 6 | 0 | 0 | 0 | 159.1 | 8.97 | 13.0 / 8.6 / 6.9 / 4.2 / 4.8 | 4.0 | 3% | 1.46 | 3.67 | 3.21 | 30 |
| drop_zone | 12 | 17% | 3 | 1 | 0 | 6 | 116.3 | 8.79 | 10.9 / 7.9 / 5.8 / 10.3 / 6.0 | 4.0 | 1% | 1.25 | 2.72 | 2.65 | 9 |
| furnace | 12 | 17% | 9 | 0 | 1 | 0 | 123.1 | 6.47 | 8.7 / 5.6 / 3.6 / 0.7 / 4.8 | 5.5 | 4% | 1.31 | 4.84 | 4.45 | 16 |
| crush | 12 | 25% | 6 | 2 | 1 | 0 | 145.5 | 8.71 | 12.7 / 7.1 / 5.3 / 3.8 / 3.8 | 4.0 | 2% | 1.35 | 3.99 | 3.59 | 16 |
| coliseum | 12 | 33% | 5 | 3 | 0 | 0 | 152.3 | 8.06 | 10.1 / 8.2 / 5.0 / 8.1 / 6.0 | 9.4 | 2% | 1.42 | 4.74 | 4.08 | 27 |
| crusher | 18 | 39% | 8 | 1 | 1 | 1 | 133.8 | 3.82 | 3.0 / 4.9 / 4.2 / 4.6 / 2.4 | 25.0 | 0% | 1.19 | 5.09 | 4.65 | 21 |
| flipper | 18 | 33% | 8 | 2 | 0 | 2 | 148.9 | 8.93 | 12.7 / 7.8 / 5.1 / 6.9 / 6.1 | 5.2 | 4% | 1.49 | 4.73 | 4.27 | 34 |
| horizontal_spinner | 18 | 28% | 10 | 1 | 0 | 2 | 145.9 | 9.47 | 14.7 / 7.8 / 5.5 / 7.3 / 2.9 | 5.7 | 4% | 1.61 | 3.36 | 3.00 | 31 |
| saw | 18 | 44% | 5 | 2 | 2 | 1 | 144.4 | 10.45 | 13.3 / 10.4 / 7.8 / 5.8 / 4.3 | 3.0 | 1% | 1.20 | 2.73 | 2.54 | 30 |

Payoffs in the 72 fights: 29 ONTO THE SPIKES, 24 INTO THE GRINDER, 24 INTO THE FIRE,
11 CRUSHED, 16 HAZARD KILL, 9 INTO THE PIT, 3 OUT OF THE ARENA: 1.6 a fight (mean hazard damage
a fight 2.70 -> 3.30 condition points).

## Reading it

- **Hazard finishes doubled** (3 -> 6 hazard KOs; pits and ring-outs unchanged at 9) and
  hazard contacts rose 3.60 -> 3.98 a minute. The late fight got busier: blows a minute in
  2:00-2:35 went 4.8 -> 6.3; the Drop Zone's endgame window 7.1 -> 10.3 (the pit open for good
  from 1:30 pens the fight in).
- **The share going to the judges did not move** (33 % -> 36 %, noise at 12 fights an arena).
  Between two AIs most early finishes are a knockout count on a machine the other has
  disabled, and the stages do not change that. The Yard went 42 % -> 75 % judges (6 -> 2
  knockouts); not isolated, and 12 chaotic fights is too few to call it a trend.
- **Blows per minute still fall away across the round** (11 early, ~5 late) in both builds:
  damaged machines fight less. Escalation holds the late minute up; it does not add blows.
- **Stuck time is ~2 %** in both: the AI does not park; "stuck" on the phone is the player's
  machine, which is the boost / anti-stuck agent's half.
- One pre-existing quirk inflates CONTROL for both machines: `Rules.is_on_spike_patch` is the
  centre ±0.8 m in EVERY arena, patch or not, so two machines clinched in the middle of the
  Crush or the Grinder both collect control all fight. Not changed here; worth fixing (read the
  arena's own patch) so the payoff points stand out on the card.

## After A + E + the boost agent's boost / anti-stuck + National shoves from WAKE

The shared tree at `66bf530` (the boost commits f902361 / ede4db2 and my `66bf530`, with the
other agents' uncommitted intro/venue work present but inert in a headless run).

| set | fights | to judges | KO/core | hazard KO | ring-out | pit | mean length s | blows/min | blows/min by stage (0-45/45-90/90-120/120-155/155+) | first hit s (median) | stuck (% of fight, per machine) | mean dist m | hazard contacts/min | credited hazard/min | payoffs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| all | 72 | 21% | 36 | 6 | 10 | 5 | 126.0 | 8.21 | 10.4 / 6.3 / 6.7 / 5.4 / 3.6 | 5.7 | 2% | 1.38 | 4.63 | 4.27 | 118 |
| yard | 12 | 25% | 7 | 0 | 2 | 0 | 149.4 | 7.25 | 10.2 / 6.2 / 6.8 / 3.9 / 2.2 | 9.1 | 1% | 1.27 | 3.01 | 2.94 | 16 |
| grinder | 12 | 17% | 6 | 0 | 4 | 0 | 104.6 | 8.99 | 10.8 / 7.4 / 4.8 / 5.6 / 8.4 | 2.9 | 3% | 1.53 | 4.46 | 4.28 | 26 |
| drop_zone | 12 | 17% | 3 | 0 | 2 | 5 | 110.1 | 11.16 | 13.0 / 6.6 / 9.1 / 14.3 / 12.0 | 4.2 | 0% | 1.27 | 3.01 | 2.97 | 12 |
| furnace | 12 | 25% | 9 | 0 | 0 | 0 | 133.6 | 4.38 | 5.8 / 3.4 / 6.0 / 2.9 / 3.4 | 5.9 | 3% | 1.34 | 6.74 | 6.09 | 22 |
| crush | 12 | 8% | 5 | 5 | 1 | 0 | 107.9 | 9.02 | 11.9 / 6.2 / 4.8 / 4.8 / 0.0 | 4.0 | 1% | 1.31 | 4.77 | 4.74 | 13 |
| coliseum | 12 | 33% | 6 | 1 | 1 | 0 | 150.5 | 8.47 | 10.4 / 8.1 / 7.6 / 5.1 / 2.9 | 8.6 | 4% | 1.58 | 5.82 | 4.61 | 29 |
| crusher | 18 | 17% | 12 | 1 | 1 | 1 | 117.6 | 6.44 | 6.8 / 6.7 / 5.8 / 2.5 / 5.2 | 14.4 | 1% | 1.25 | 4.17 | 3.71 | 25 |
| flipper | 18 | 17% | 7 | 2 | 6 | 0 | 126.7 | 9.46 | 10.8 / 5.9 / 10.7 / 5.7 / 7.8 | 4.5 | 3% | 1.50 | 5.43 | 5.16 | 40 |
| horizontal_spinner | 18 | 17% | 8 | 2 | 2 | 3 | 126.6 | 10.57 | 13.8 / 7.5 / 7.8 / 10.3 / 1.0 | 4.6 | 3% | 1.58 | 5.33 | 4.86 | 34 |
| saw | 18 | 33% | 9 | 1 | 1 | 1 | 133.2 | 6.37 | 10.1 / 5.1 / 2.4 / 2.0 / 2.1 | 1.9 | 2% | 1.20 | 3.61 | 3.35 | 19 |

Payoffs: 31 INTO THE GRINDER, 28 INTO THE FIRE, 19 ONTO THE SPIKES, 9 CRUSHED, 12 HAZARD KILL,
9 INTO THE PIT, 10 OUT OF THE ARENA (1.6 a fight); hazard damage 3.39 a fight.

## The three side by side (all 72 fights)

| build | to judges | KO/core | hazard KO | ring-out | pit | mean length s | blows/min | late blows/min (2:00-2:35) | hazard contacts/min | payoffs a fight |
|---|---|---|---|---|---|---|---|---|---|---|
| baseline e994cd3 | 33 % | 36 | 3 | 3 | 6 | 138.7 | 8.10 | 4.8 | 3.60 | 0 |
| + stages + payoffs | 36 % | 31 | 6 | 3 | 6 | 143.2 | 8.17 | 6.3 | 3.98 | 1.6 |
| + boost / anti-stuck + National shoves | **21 %** | 36 | 6 | **10** | 5 | **126.0** | 8.21 | 5.4 | **4.63** | 1.6 |

Hazards finish twice as many fights, and with the boost (a dash to shove with) and the
National tier pushing from 1:30, ring-outs go 3 -> 10 and the share decided by the judges
drops from a third to a fifth. What did not move: blows per minute (about 8), time to the
first blow (about 5.7 s) and stuck time (about 2 %) between two AIs.
