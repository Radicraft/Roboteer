# Wave C: app size pass (2026-09-28, branch `wave-c-size`)

Brief: the owner's phone showed the Release app at 217 MB, over Apple's 200 MB cellular prompt
(157 MB before the venues). Goal: comfortably under 200 MB, about 170 MB, with no visible loss at
phone size and fight determinism unchanged. Worked in a separate worktree
(`/Volumes/RoboteerBuild2/Code/Roboteer-size`); nothing in the main tree was touched.

## The headline, measured

| | before (`39e0cd3`) | after (this branch) |
|---|---|---|
| arena.pck | 97.48 MB | **87.87 MB** |
| dev Release build (`build-device.sh`, what the phone showed) | 217 MB (binary unstripped) | **168 MB** (measured; Release now strips like an archive) |
| App Store install size (Xcode App Thinning Size Report, iPhone variant, uncompressed) | 199.4 MB | **167.9 MB** |
| App Store download, thinning report "compressed" | 101.8 MB | **75.8 MB** |
| App Store download, conservative (binary counted as incompressible, as FairPlay leaves it) | ~140 MB | **~114 MB** |

Method: `xcodebuild archive` (Release, generic iOS, own DerivedData
`/Volumes/RoboteerBuild2/DerivedData-size`) then `-exportArchive` with `method=debugging`,
`thinning=<thin-for-all-variants>`; the report is in
`/Volumes/RoboteerBuild2/size-archives/*-export/App Thinning Size Report.txt`. There is one
thinned variant in practice (no asset-catalogue slicing to speak of: Assets.car is 180 KB).
The "conservative download" line replaces the report's compressed binary (~20.9 MB) with the
binary's raw `__TEXT` (58.4 MB), because App Store encryption makes it incompressible.

Two things the 217 MB figure hid, worth knowing before anyone panics about it again:

1. It was a plain `xcodebuild build`, which does not strip: the binary was 88.5 MB with 27 MB of
   symbol table. Every archive (so every App Store build) strips it to 61.3 MB anyway.
2. The cellular prompt is about the download, and the download was never near 200 MB: the pck
   compresses to about half (ETC2/ASTC blocks and zstd scenes still deflate well).

The honest "before" for the App Store is the baseline archive row above; the cuts below took it
to 167.9 MB installed.

## Where the bytes were (before), biggest first

App bundle (dev Release build, 217 MB):

| item | size | note |
|---|---|---|
| arena.pck | 95.3 MB (97.48 MB file) | the Godot pack, table below |
| `Roboteer` binary | 88.5 MB | libgodot is statically linked; 58.4 MB `__TEXT`, 27.9 MB `__LINKEDIT` (symbols) |
| `ui/` (Art/ui folder reference) | 24.2 MB | 23 opaque PNG renders (backdrops 2436x1125 at ~2.2 MB each) |
| SwiftGodot.framework | 12.7 MB | |
| `paint/` (Art/paint) | 1.9 MB | 10 opaque 512 PNG previews |
| Fonts | 0.66 MB | four faces, already lean |
| Assets.car, jsons, jpgs | < 0.5 MB | |

arena.pck by category (before -> after):

| category | before MB | after MB | change |
|---|---|---|---|
| textures, VRAM (ETC2/ASTC): machine sets, arena plate, decals, masks | 36.58 | 35.18 | -1.40 |
| venue floors + floor normals + grime + wall (kit) | 28.84 | 22.72 | -6.12 |
| paint jobs (livery textures) | 12.93 | 12.93 | 0 |
| meshes (.glb -> .scn, already zstd) | 7.88 | 7.88 | 0 |
| audio (WAV imports) | 5.52 | 3.42 | -2.09 |
| textures, lossless (crowd atlases, wet maps, boards) | 3.89 | 3.89 | 0 |
| scripts (compressed tokens) | 1.18 | 1.18 | 0 |
| json, remaps, shaders, tres | 0.33 | 0.33 | 0 |
| fonts | 0.24 | 0.24 | 0 |
| **total (directory sum)** | **97.38** | **87.77** | **-9.61** |

The crowd, for the crowd agent (branch `wave-c-crowd`): 2.99 MB of textures
(`crowd_atlas_human.png` 1.46 MB lossless, used; `crowd_atlas.png` 1.53 MB lossless, the
"stylised" atlas, reachable only through the QA `crowd` override, so it ships for nothing),
0.02 MB barrier mesh, and 2.14 MB of crowd audio before this pass (the ambience bed is now QOA,
see below; roar and swells stay PCM). What I would have cut, and left for the crowd agent per
the scope change: exclude `crowd_atlas.png`/`.json`/`_emit.png` from the export (-1.53 MB) if
the new crowd does not use the stylised atlas. Note both atlases are lossless PNG-in-ctex: VRAM
compression would make them BIGGER on disk (2048x1024 RGBA ETC2 with mips = 2.8 MB), so leave
them lossless unless the new crowd is smaller in pixels.

## The cuts that shipped on this branch

| # | cut | saving | proof |
|---|---|---|---|
| 1 | `Art/ui` + `Art/paint` PNG -> JPEG q92 4:4:4 (all 33 files are opaque renders; checked alpha) | 21.9 MB (26.49 -> 4.59) | worst PSNR 39.5 dB (paint_gold), backdrops 44-48 dB; `docs/look/size/ui-jpeg-*.jpg` |
| 2 | removed `blueprint_card.png` @1x/2x/3x: no code reads it | 1.45 MB (inside #1's total) | grep: only docs mention it |
| 3 | Release config strips like an archive (`DEPLOYMENT_POSTPROCESSING`, `STRIP_INSTALLED_PRODUCT`, `STRIP_STYLE=all`) | 27 MB on the dev build; 0 on the App Store (archives already strip) | dSYM still produced (dwarf-with-dsym) |
| 4 | venue floor albedo `size_limit` 2048 -> 1536 for Yard, Grinder, Drop Zone, Furnace, Coliseum (the test arena was already 1536) | 6.12 MB | `docs/look/size/floor-1536-*.jpg` |
| 5 | 16 sounds imported as QOA after a numeric gate (below) | 2.09 MB | audio_test 117/0 |
| 6 | 8 textures nobody loads excluded from the export | 1.40 MB | grep of every shipped script/scene/resource |

Code changes: `BroadcastArt.image` (DesignSystem.swift) and `PaintJobs.preview` try `.jpg`
first, then `.png`, so a future asset with alpha can still land as PNG. The export preset's
`exclude_filter` gained the eight unused texture paths.

### 4. Floors: how the proof was taken

Every venue captured at the phone's real pixel size (2868x1320, `--resolution`) with
`qa/venue_capture.tscn`, plus a close floor pose nearer the floor than the fight camera ever
gets (`--roboteer-venue-pose=-2.6,2.6,-2.6,0.3,0,0.3,50`), before and after, and 1000x600 crops
compared at 1:1 side by side (`docs/look/size/floor-1536-<venue>.jpg`). Run-to-run noise between
two identical captures is 27-30 dB PSNR (crowd, sparks and the fight itself move), so the call
was made by eye on the crops, not by the number. The scratches and dents come from the tiled
arena plate and the floor normal, both untouched; the floor map carries the plate layout, seams,
stains and paint, and those read the same at 1536 in five venues.

### 5. Audio: the QOA gate (numbers only, nothing was played)

The audio notes insisted on PCM because "a lossy codec smears the seam" and transients. That is
testable, so it was tested per file rather than assumed either way. Each candidate was imported
as QOA, decoded through Godot's own playback (`AudioStreamPlayback.mix_audio`, Dummy driver) and
compared with the source PCM through the same path. A file ships as QOA only if:

- SNR against the source >= 30 dB, peak within 0.1 dB, worst error in the 10 ms round the
  loudest sample <= -28 dB of the peak; and
- for a loop, the decoded wrap step is no larger than the PCM's own wrap step (same playback
  path) plus max(256, 10 % of the loop's largest interior step): i.e. the codec adds no click.

Passed and now QOA (16): adaptive_track_loop, crowd_ambience_loop, flame_loop, grinder_loop,
hover_fan_loop, leg_servo_loop, roll_omni_loop, roll_wheel_loop, skid_loop, vortex_spin_loop,
footfall_1/2, napalm_launch, reactive_clang_1/2, vortex_throw. (28 older one-shots were already
QOA before this pass.)

Failed and stay PCM (22): the tonal loops, where QOA did add a step at the wrap (endgame drone
26 -> 815 s16 units, motor 530 -> 1364, spin-up 606 -> 1330, drive whine 697 -> 1281, fire patch
220 -> 1383, disc spin 1300 -> 1777), and every transient-dense or broadband file under 30 dB
SNR (arc crackle/discharge, prod zaps, saws, drill, scrape, track clatter, hover skirt, crowd roar
and swells, cook warning, bolt tick). `prod_zap_2` was the worst: +3 dB peak overshoot under QOA.

`audio_test.gd` changes: the "every loop is PCM" check became "PCM or QOA"; a QOA loop's seam is
measured on the decoded stream, delay-aligned against the source (the mixer starts two samples
late), and must also pass the no-added-click rule above; `_levels`/`_window_db` read the source
wav when the import is QOA (identical numbers for every PCM file). Result 117/0, and every
printed level is unchanged except the informational "chassis thud" scale line, -15.1 -> -26.3:
the old number was QOA bytes read as if they were 16-bit samples (chassis_thud has been QOA since
wave F), the new one is the real level. It feeds no check.

Found on the way: in these measurements Godot's WAV playback skipped source sample 0 at the loop wrap (it played
..., n-2, n-1, 1, 2, ...), PCM or QOA. Every loop's audible wrap is therefore a little bigger
than the byte test in audio_test sees. Harmless at these levels; noted for the audio lead.

## Rejected (and why)

| cut | would save | why not |
|---|---|---|
| venue floor normals 1024 -> 512 (the test arena already uses 512) | 6.3 MB | dents and pits visibly softer at 1:1 on the Grinder (`docs/look/size/floor-normal-512-grinder-REJECTED.jpg`) |
| Crush floor albedo 2048 -> 1536 | 1.2 MB | its painted cracks read thinner and lighter (`floor-1536-crush-REJECTED.jpg`) |
| machine texture sets ASTC -> ETC2, or 1024 -> 512 (brushed steel, titanium, HDPE, polycarbonate, decals) | ~5 MB | the owner said the machines looked "not high res enough" / "blurry"; wave V4 made these ASTC with no size limit on purpose and `texel_density_test` pins it. Owner call, not mine |
| paint job textures 1024 -> 512 | ~8 MB | the same machines-look-blurry history; worn at the turntable close-up |
| meshes: turn off generated LODs / shadow meshes | ~1-2 MB | changes rendering and performance, not a size-only change; .scn files are already zstd |
| crowd atlas changes | 1.5-3 MB | out of scope (crowd agent owns it); sized above |
| libgodot with unused engine modules compiled out | 15-25 MB of binary (estimate) | the device slice is the released v4.6.4 binary (`~/Build/SWAP-DEVICE-SLICE.md`); a custom engine build needs the owner's go-ahead and a real-device smoke test. The biggest lever left if ever needed |
| JPEG for the crowd/boards lossless textures inside the pck | small | lossless PNG-in-ctex is already smaller than VRAM here |

## Tests run (HEADLESS=1, worktree)

Size branch: bridge_test 39/0, fx_test 189/0 (2 skipped), audio_test 117/0, commentary_test
82/0, render_test 116/0, texel_density_test 20/0, paint_test 140/0, warmup_test 34/0,
arenas_test 155/0, test_arena_runs_test 24/0, venue_kit_test 214/0, determinism_test 42/0.
hazard_determinism_test 14 checks / 6 failures, the SAME six as the baseline tree at `39e0cd3`
(the pre-change goldens that the integration pass is re-recording).

Determinism proof: venue_kit_test's 21 fight hashes (7 arenas x kit high / none / low) and
hazard_determinism's six per-arena hashes are byte-identical between a clean worktree at
`39e0cd3` and this branch (diffed). determinism_test passes on both.

One flake worth the integrator's eye: determinism_test failed ONCE on this branch when run with
JOBS=6 while another suite was also running on the Mac (load average ~27): "fight 3 against
fight 1 stopped on the same tick (1800 and 1802)", 6 cm drift. It passed alone straight after,
and nothing on this branch touches physics, AI or timing (textures, audio encoding, a test file,
Swift image loading). A determinism test that can fail under CPU load suggests something in the
fixture reads wall-clock time; worth a look separately.

## Not committed / housekeeping

- `Roboteer/Resources/arena.pck` is NOT committed (repo convention: agents do not commit pcks).
  Re-export with `scripts/export-pck.sh` after merging. NOTE from wave B: a headless `--import`
  does not pick up a changed `size_limit` on an already-imported texture; delete
  `Arena/.godot/imported/{yard,grinder,drop_zone,furnace,coliseum}_floor.png-*` before exporting,
  or the pck keeps the 2048 floors.
- `docs/design-system.md` still lists `Art/ui/blueprint_card.png` in the asset table; it is gone.
- Archives used for the numbers: `/Volumes/RoboteerBuild2/size-archives/` (baseline, final).
