# Wave C integration (2026-09-28, finished 2026-09-30)

Merges on local main (not pushed): `fc49c2b` (wave-c-hazards) and `88f3324` (wave-c-size), on
top of pushed `1f0975c`. The owner asked to stop and save at about 12:50; this is where it stands.

## Done

1. **Size merge steps.** Deleted `Arena/.godot/imported/{yard,grinder,drop_zone,furnace,coliseum}_floor.png-*`
   and, to be safe, the imports of the 16 wavs that went QOA; `scripts/export-pck.sh`:
   **arena.pck 87,882,308 bytes (87.88 MB)**, was 97.48. Checked the re-imported ctex headers:
   the five venue floors are 1536 (Crush stays 2048, as the size notes say). The pck is not
   committed (convention).
   `docs/design-system.md` asset table: `blueprint_card.png` row removed, the key art rows say
   `.jpg`, the header line says the renders are opaque JPEG q92 4:4:4.
2. **Suite: NOT finished.** `HEADLESS=1 JOBS=8 scripts/test-arena.sh` was started and killed
   by the stop before it printed anything (it prints at the end). No result. The
   hazard_determinism goldens (re-recorded at 10a4c6d) are therefore NOT yet confirmed
   unchanged by the merges (both branch notes say hash-neutral, each proved on its own worktree).
3. **Sim build + career self test: PASS.** `scripts/build-sim.sh` BUILD SUCCEEDED (bundle
   carries the 87.88 MB pck, `ui/` 4.1 MB and `paint/` 0.5 MB of JPEG, no stale PNGs).
   Self test on iPhone 17 sim A18A1779 (iOS 26.5, volume 0, dummy/headless):
   **ALL PASS, 1027 checks, 2 warnings** (the two known pacing warnings).
4. **Eye checks, all looked at:**
   - Grinder disc (desktop Godot, `qa/hazard_states_capture.tscn`, Dummy audio): idle = disc in its
     lined well, faint trickle only; cutting = rim spray, glow and fire light. Works as the hazards
     follow-up says. The cutting spray reads larger than "low" from the close camera; fine from the
     fight camera.
   - Yard spike patch arming / rising / up / sinking: pins rise out of the bored holes in the
     grate, lit guide plate; nothing from nowhere. No duplicate frames (md5 check).
   - Sim at 874 x 402 (dummy renderer, so the stills/key art show): main menu (menu_keyart JPEG),
     quick fight (six arena card JPEGs), career home and scouting (rival + boss portrait JPEGs):
     all load, no missing art, nothing clipped that was not already listed in wave B.
   - Trap for the next run: in zsh a `$H` holding several launch args does NOT word-split, so the
     app got one bogus argument, ran the GL renderer and sat on the loading screen at 0 %. Use an
     array (`"${H[@]}"`).
5. **Release build: BUILT, NOT installed.** `scripts/build-device.sh` (no `install`) BUILD
   SUCCEEDED; `Release-iphoneos/Roboteer.app` = **161 MB** (du -sm; the size notes expected
   ~168 MB). Not installed on the phone because the suite had not passed.

## Left to do (as of the 2026-09-28 stop; all done 2026-09-30, below)

1. Re-run the full suite (`HEADLESS=1 JOBS=8 scripts/test-arena.sh`); must be green, the six
   hazard_determinism hashes unchanged (yard c814ec9e2c1a3b19, grinder 948cea0b512e1375,
   furnace fa79709c3fddc315, crush 29b028f7726a2f2f, drop_zone 3c8a0a72052ca8cf, coliseum
   7c37e036b6df6957).
2. `scripts/build-device.sh install` to the iPhone 18 Pro Max (00008160-0018096E0C400036); the
   Release build is already made, so this is mostly the install.
3. Push main (NOT pushed: the suite has not passed).

## Housekeeping seen

- Two idle Godot processes from earlier work are still alive (a `qoa_probe.gd` from the size
  pass, about 4.5 h old, and a `hazard_determinism_test --record` in `/Volumes/RoboteerBuild2/Code/wb-integ`,
  about 3.8 h old). Near-zero CPU. Not mine to kill; the coordinator may want them gone.
- iPhone 17 sim A18A1779 shut down.

## Resumed 2026-09-30: finished

1. **Suite: 47 test files, 0 failures** (`HEADLESS=1 JOBS=8 scripts/test-arena.sh`, at
   `0317511`). hazard_determinism: all six hashes match the table above exactly (yard
   c814ec9e2c1a3b19, grinder 948cea0b512e1375, furnace fa79709c3fddc315, crush 29b028f7726a2f2f,
   drop_zone 3c8a0a72052ca8cf, coliseum 7c37e036b6df6957; the Coliseum warning layer off hashes
   the same). Both merges are hash-neutral, as their notes said. No golden re-recorded.
2. **Phone:** `scripts/build-device.sh install`, Release, pck 87.88 MB (no re-export needed),
   INSTALLED on the owner's iPhone 18 Pro Max (00008160-0018096E0C400036) from `0317511`
   (code identical to the merge `88f3324`). Installed .app **160.3 MB** (was 216 MB at wave B):
   binary 61.3 MB stripped, pck 87.9 MB. Under Apple's 200 MB cellular prompt.
3. Pushed to origin main (the push includes this note's commit).

No simulator or window was used on 2026-09-30 (the owner may be at the Mac).
