# Owner decisions, 30 Sept 2026 (binding for every agent)

Source: the show night review, docs/look/show-review.html (https://claude.ai/artifact/DfMhknWX4GbKLydKzCF7Z1). The owner: "Agree with your recs".

1. FIRST WAVE "show night" = build now:
   - The Marshal: our own neutral arena official. A hovering drone with a light bar (never a striped humanoid, never the show's referee robot name or silhouette). Visible count-out with its lights, sprays out fires, visibly tows stuck machines apart (the existing lock-up/unstick impulse, now shown), shows the start lights, cards a house bot. Kept out of the physics: fight hashes unchanged.
   - Our own start and stop words: "3, 2, 1, FIGHT" and "POWER DOWN". Never the show's two words.
   - Walk-outs through the venue gate (VenueKit.play_entrance, built but unused) with a tale-of-the-tape card: stats plus a strength and a weakness line the player writes in the builder; rivals get written ones.
   - Commentary with a personality, TEXT ONLY: a few hundred original lines keyed to real fight events, naming both machines and parts, mock outrage at house bot mischief, a pre-fight prediction. Every line must match the event that fired it. No voice yet.
   - House bot mischief AFTER THE RESULT ONLY: a finishing ritual on the loser (shove into the arena's hazard during the finish beat), an occasional late hit after the bell, the Marshal flashes a card, commentary plays outraged. Never changes who won, never feeds back into the result or the replay.
   - The crowd cheers a clear judges' decision and boos a close one. No style score.
   - Fix: grudge line {player} bug, Clatterbox / Penny Dread grudge lines swapped, opponent_ai obeying a non-existent 4 s pin penalty.
2. CROWD = option C "mix" (owner changed his pick after seeing the stills, 30 Sept): 3D people near the rail, dark broadcast house behind; high = C, medium = front row 3D + broadcast, low = broadcast only.
3. POWER TRAIN BUILDER = next wave, MOCKUPS FIRST (motor in feel words, gearing sprint/balanced/grunt, battery capacity vs weight shared with weapons and boost, wheel size and tyre, whole-machine readouts, quick build by target stats).
4. NEXT after the first wave: house bots you can hurt with memory, grudges and trophy parts; a rampage night event; a Drop Zone pit button; a pit crew scene between fights; a deciding-moment replay and winner spotlight; a last-machine-standing knockout and grudge rematches. Skip fog.
5. IP (brief §3) stands: no show names, character names or silhouettes, catchphrases, or branded terms (corner zone name, pit name, named hazards, event names).

## Later on 30 Sept: owner "Make all your own decisions". Calls made by the coordinator (binding)

6. POWER TRAIN: build option A (Drive tab rows) with C's fight clock opening from the battery strip and C's "Plans" as the quick build. A flat battery LIMPS to the bell at 35 % (never a stop and count-out). Forklift motor, Twin pack and Hub motor stay full-game rewards (Levels 38/48/58). Starts after the show wave and the menus merge (it moves every golden once).
7. NUMBERS: B612 Mono's fixed-pitch gap after "." ":" "," is not acceptable ("4. 2 m/s"). All figures move to the UI face (Saira Semi Condensed) with tabular figures if it has them, else a proportional face with lining tabular numerals from Google Fonts (OFL) that matches; B612 Mono stays only for code-like labels (part codes such as "WPN 07") if at all.
8. MENUS: the projected blueprint under the plinth STAYS ON. Pyro: white CO2 jets when a screen opens (the owner asked for dry ice), flame jets only on a win.
9. FITMENT CALLS: spinner rings (full-body, vortex) are drawn to clear the hull and wheels (bigger or raised ring, no pass-through); the bar spinner and drum sit high enough to clear the nose; flippers and lifters get a drawn slot or a limited drawn stroke on flat noses (Apex first) so the arm never passes through the hull; axe and crusher rest above the front plate; the pyramid gets its own fitted side plates; with a scoop and a front weapon, the weapon wins and the scoop is drawn lower and narrower under it; the wedge gets a fitted reactive plate. Visual only where possible; any collider change is flagged with the moved hashes.
10. NEXT AFTER THE FIRST SHOW WAVE, in this order: house bots with memory (damage carries, grudges, trophy parts), deciding-moment replay + winner spotlight, Drop Zone pit button, pit crew scene with rematch offers, rampage night event, last-machine-standing knockout.
11. COMMENTARY: sentence case; the prediction may show over the countdown; rival lines name the player by Game Center alias, else "your team".
12. ARENA RENAME: "Drop Zone" collides with a named hazard from the classic show (brief §3). The arena is now "The Trapdoor" ("Trapdoor" where space is short) everywhere a player can see it; the internal id stays `drop_zone`.
13. WALK-OUTS: house bot shot stays on first-visit career intros; quick fights keep short walk-outs; machines start in the arena corner under the gate.
14. MARSHAL: the four-duct drone look is accepted. The real 4 s wall-pin rule (Marshal tows the held machine free) is accepted for everyone, player included; the AI's 3 s release stays. The longer finish beat (7.1 s, 8.5 s with a late hit, tap to skip) is accepted. The Marshal stays out of the close wreck orbit. Owed to the owner: an ear check of crowd_boo.wav.
15. FITMENT PASS 2: bar spinner goes on a forward mount ahead of the nose (not raised; raising halved its damage); ring collision radius capped at 0.72 m, with what is drawn inside the ring narrowed on long hulls; drum and vortex part_toughness as tuned by the gauntlet.
