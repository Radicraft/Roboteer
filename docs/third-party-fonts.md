# Third-party fonts

The game's type is the "01 Blueprint" system from docs/look/fonts-options.html (owner decision
2026-09-27), with figures in the UI face since wave D (decision 7 of 2026-09-30,
docs/wave-d-figures-notes.md). Every face is SIL Open Font License 1.1 and unmodified. The same TTFs ship twice: in the
app (`Roboteer/Fonts/`) and in the Godot pack (`Arena/assets/fonts/`), each folder with the
family's licence as `OFL-<family>.txt`.

| Role | Face | File | Source | Licence |
|---|---|---|---|---|
| Display | Saira Stencil One 400 | `SairaStencilOne-Regular.ttf` | `ofl/sairastencilone` | OFL 1.1, Copyright 2019 The Saira Stencil Project Authors, reserved font name "Saira" |
| UI body | Saira Semi Condensed 500 | `SairaSemiCondensed-Medium.ttf` | github.com/Omnibus-Type/Saira `Saira/fonts/ttf/` at c9d45ed (v1.101) | OFL 1.1, Copyright 2020 The Saira Project Authors |
| UI labels, buttons, numbers | Saira Semi Condensed 700 (numbers with OpenType `tnum`) | `SairaSemiCondensed-Bold.ttf` | as above | as above |

The Saira Semi Condensed files are the family's own upstream release, v1.101, the one Google Fonts
builds its variable Saira (`ofl/saira`) from. Google's static `ofl/sairasemicondensed` folder is
still v0.072 (2016, reserved font name "Saira"), which has no tabular figures; v1.101 has `tnum`
and carries no reserved font name. Never edit the files (metrics, subsetting); the figures come
from switching the font's own `tnum` feature on, not from a modified copy.

B612 Mono 700 (OFL 1.1, Copyright 2012 The B612 Project Authors) carried the numbers from
2026-09-27 to 2026-09-30 and was removed from both folders in wave D.

Barlow Condensed (the previous family) was removed from both folders on 2026-09-27. The baked arena
kit and decal textures made before that date still carry Barlow lettering as pixels; that is
covered by the same OFL 1.1 (Copyright 2017 The Barlow Project Authors).
