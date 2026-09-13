# Roboteer

Physics robot combat for iPhone. SwiftUI shell, Godot 4.6 arena embedded via SwiftGodotKit (libgodot).

- `docs/brief-v3.md` is the design brief. It is the authority. Read it before touching anything.
- `docs/bridge-spec.md` is the Swift <-> Godot contract (Stage 1).
- `Roboteer/` Swift app sources, `Roboteer.xcodeproj` the Xcode project.
- `Arena/` the Godot project (opened with Godot 4.6.x, `~/Applications/Godot.app`).
- `scripts/export-pck.sh` exports `Arena/` to `Roboteer/Resources/arena.pck`.

iPhone only. Build with Xcode 27.
