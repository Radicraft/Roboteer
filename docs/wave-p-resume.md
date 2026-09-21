# Wave P: how to resume (written 2026-09-17 ~19:45 when the owner's weekly token budget hit 3 %)

State at the pause: nine Opus agents were fanned at ~19:25 with `docs/brief-v5-progression.md` +
`docs/wave-p-contracts.md` as their brief. Almost nothing had landed. Seven were STOPPED to save
budget (B1, B2, D1, D2, E, F, G); A (engine) and C (arena ledger + FightResult v2) were left running
because everything else depends on them. Whatever A and C got done is in the working tree
(uncommitted); `git status` shows it; their notes files (`docs/wave-p-a-notes.md`,
`docs/wave-p-c-notes.md`) exist only if they finished.

## To relaunch (next session, budget permitting)

1. `git status`; if the tree does not build (`scripts/build-sim.sh`), read `git diff` on A's and
   C's files and either finish or revert them. The stub files the coordinator wrote (ProgressionTypes,
   ProgressionEngine stub, MatchReportView/RewardsView/RetryPromptView/ShopView/PaintJobs stubs,
   the pbxproj entries, the `progression` block in parts.json) built green before the fan-out.
2. Commit what is coherent ("Wave P contracts and stubs" + whatever A/C finished).
3. Re-fan from the contracts file, ONE OR TWO AGENTS AT A TIME in dependency order:
   A engine -> C ledger -> B1 post-match + B2 series/shop (UI; they write mockup options pages
   `docs/look/postmatch-options.html` / `series-options.html` FIRST, owner may want to veto) ->
   D1 weapons + D2 mobility (physics, parts.json entries) -> E models (owner: search free CC0/CC-BY
   models online first, credits in `docs/third-party-models.md`) -> F fx/audio -> G paint jobs
   (Recraft, <= 80 credits). Each agent's brief = its row in the contracts file + the brief section
   numbers listed there; the original prompts were long restatements of exactly that.
4. Per agent: Opus, headless only while the owner is at the Mac, builds via scripts/build-sim.sh or
   build-device.sh (shared lock), suite via scripts/test-arena.sh, notes file docs/wave-p-<agent>-notes.md.
5. After the wave: merge check on shared files (fight.gd, hud.gd, bot.gd, damage.gd, opponent_ai.gd,
   part_visuals.gd, DesignSystem.swift, parts.json), delete any `NextFight` shim A left, full suite,
   `-careerSelfTest`, `scripts/build-device.sh install`, owner plays, push.
