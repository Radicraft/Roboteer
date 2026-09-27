# Third-party fonts

The game's type is the "01 Blueprint" system from docs/look/fonts-options.html (owner decision
2026-09-27). Every face is SIL Open Font License 1.1, taken from the official Google Fonts
repository (github.com/google/fonts, `ofl/` folders), unmodified. The same TTFs ship twice: in the
app (`Roboteer/Fonts/`) and in the Godot pack (`Arena/assets/fonts/`), each folder with the
family's licence as `OFL-<family>.txt`.

| Role | Face | File | Source | Licence |
|---|---|---|---|---|
| Display | Saira Stencil One 400 | `SairaStencilOne-Regular.ttf` | `ofl/sairastencilone` | OFL 1.1, Copyright 2019 The Saira Stencil Project Authors, reserved font name "Saira" |
| UI body | Saira Semi Condensed 500 | `SairaSemiCondensed-Medium.ttf` | `ofl/sairasemicondensed` | OFL 1.1, Copyright 2016 The Saira Project Authors, reserved font name "Saira" |
| UI labels, buttons | Saira Semi Condensed 700 | `SairaSemiCondensed-Bold.ttf` | `ofl/sairasemicondensed` | as above |
| Numbers | B612 Mono 700 | `B612Mono-Bold.ttf` | `ofl/b612mono` | OFL 1.1, Copyright 2012 The B612 Project Authors |

"Saira" is a Reserved Font Name: the files must never be edited (metrics, subsetting) and shipped
under that name.

Barlow Condensed (the previous family) was removed from both folders on 2026-09-27. The baked arena
kit and decal textures made before that date still carry Barlow lettering as pixels; that is
covered by the same OFL 1.1 (Copyright 2017 The Barlow Project Authors).
