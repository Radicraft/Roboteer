# Wave B judges (2026-09-27)

Owner, on the iPhone: "there is an issue with win and lose decisions in all the games... i
virtually had no damage one game but the judges decided the opponent won".

## What the phone showed

`Documents/arena-log.txt` has no result lines, but the SwiftData store (`Library/Application
Support/default.store`, table `ZFIGHTLOG`) keeps every career fight's result, config and replay.
The fight he meant (20:36, the Yard, Tinribs box ram against Penny Dread wedge flipper, 3:00):

- Penny Dread lost its flipper (weapon 0) and 70 % of its top armour; nothing came off Tinribs.
- Old card: Tinribs damage 7 / control 0 / aggression 4 = 11; Penny Dread 3 / 7 / 3 = 13. He lost
  on 21 s of control (the flipper had him on his back; a local re-sim of the replay puts 19.9 s of
  it on "inverted").
- The fight before (20:32) he WON on control 8 against 3 while his drive and all four wheels were
  gone. Both directions wrong.

## Causes

1. Damage was absolute and saturated: 2.5 condition points removed was a 10, so both machines
   sat at 9 or 10 in most fights and control seconds decided.
2. `Rules.is_on_spike_patch` was the middle 1.6 m of every arena, spikes up or down, and scored
   both machines in a clinch. The Furnace (no spikes) handed out 30 s of "spike" control a fight.
3. Payoffs (8 s a hazard shove, 20 s a kill) against a 30 s control scale made one shove worth
   a third of the card.

## How the judges score (the rules, plainly; this text belongs in any player help)

The judges split ten points between the two machines: five for damage, three for control, two
for aggression. Each column is relative: the machine that did more of it gets more of the points.

- DAMAGE (5): who lost less of their own machine, from every cause (blows, hazards, the house
  bot). A part knocked clean out counts a further tenth of a machine, the weapon or the drive two
  tenths. If one machine took more than twice what the other did, it gets all five.
- CONTROL (3): seconds you had them on their back, in the air, or on the RISEN spikes while you
  were off them, plus hazard payoffs (8 s a shove into a live hazard, 20 s for a hazard kill).
- AGGRESSION (2): seconds driving in on them at close range, plus one per weapon blow that landed.

Highest total wins. A level total goes to damage, then control, then aggression. Small numbers
make small leads (floors: 10 % damage, 20 s control, 30 s aggression), so a scratch does not
sweep a column. Constants: `FightTypes.JUDGE_*`; maths: `FightRules.judge_scores / judge_cards /
judges_winner_index`.

## Decisions before and after (qa/judges_gauntlet.gd, 72 AI fights, 6 arenas x 4 pairs x 3 seeds)

"Viewer verdict" = condition lost + 0.1 per part lost. "Clear" = one machine took at least twice
the damage and 5 points more.

| | decisions | winner took clearly more damage | clear fights lost by the less damaged machine |
|---|---|---|---|
| before | 29 | 11 (38 %) | 6 of 15 (40 %) |
| after | 29 | 1 (3 %) | 0 of 17 |

(The viewer measure is close to the new damage column by design, so "after" is partly by
construction; the point is the old card got it wrong 40 % of the time.) Furnace + Drop Zone
control seconds fell from 379 to 104 across their fights (the phantom centre patch).

## Result screen

- `FightResult.judgesDetail` decodes the new always-present `judges_detail` result key.
- `JudgesCard` + `JudgesCardView` (in MatchReportView.swift): the three columns "OF 5 / 3 / 2"
  per machine with totals (the column a machine led in `win`), the verdict ("Tinribs wins on the
  cards, 5.7 to 4.3.") and one sentence a column (what each lost and which parts, who held whom
  and for how long, who drove in). No line accents, no em dashes. Shown on the career match
  report for a judges decision, and on the quick fight ResultSheet (old table kept for KOs).
- QA flag `-openMatchReport decision`.

## Determinism

Judging reads tallies after the fact, except the AI's last-20-s "behind on the card" read
(`judge_points`), which now uses the new card, so the last 20 s of a close fight can drive
differently; spike control changed what `control_s` holds. No golden was re-recorded.
`hazard_determinism_test` goldens: NOT re-run (see below).

## Where I stopped (2026-09-27)

Stopped at the owner's usage limit. Committed (by path).

Verified: judges_test 28/0 (one-sided damage, the owner's own fight from the phone, no-damage
fights, parts, the spikes clinch / risen / Furnace, end to end at the bell with judges_detail),
rules_test 323/0, pacing_test 72/0, fight_shape_test 34/0; gauntlet above; scripts/build-sim.sh
BUILD SUCCEEDED before the CareerSelfTest check was added.

NOT verified:
1. Swift build after the last edits (CareerSelfTest `checkJudgesCard`, ProgressionEngine judges
   card): run `scripts/build-sim.sh`.
2. The card on screen: the only booted sim (FontCap) belonged to the font agent and relaunched
   under me. Screenshot `-openMatchReport decision` (landscape, 402 pt tall) and a quick fight
   ResultSheet after a judges decision; check the summary column fits beside the panel.
3. `-careerSelfTest` run for the new checks.
4. The rest of the Godot suite, especially `hazard_determinism_test` (goldens), `ai_test`
   (judge_points), `bridge_test`, `determinism_test`.
5. Not done: a player help screen (none exists; the rules paragraph above is the text for one).
   Side note: a ram records 0 "hits landed" (no weapon fire), so the report says "0 hits" for a
   ram that did real damage.
