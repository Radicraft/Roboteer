//
//  FightConfigFixture.swift
//  The hardcoded fight configurations the shell sends. Contract: docs/bridge-spec.md.
//

import Foundation
import SwiftUI
import UIKit

/// Safe area insets in Godot window pixels (points times the screen scale), the shape
/// `presentation.safe_area_px` in docs/stage3-spec.md section 2.
struct SafeAreaPixels: Equatable {
    var left: Int
    var top: Int
    var right: Int
    var bottom: Int

    static let zero = SafeAreaPixels(left: 0, top: 0, right: 0, bottom: 0)

    /// Physical insets from the key window, which are left/right in device terms rather than
    /// leading/trailing, so they survive a right to left language. Falls back to the layout
    /// insets a `GeometryReader` reports if no window is on screen yet.
    static func current(fallback: EdgeInsets? = nil) -> SafeAreaPixels {
        if let window = keyWindow {
            let insets = window.safeAreaInsets
            let scale = window.windowScene?.screen.scale ?? UIScreen.main.scale
            if insets.left > 0 || insets.right > 0 || insets.top > 0 || insets.bottom > 0 {
                return SafeAreaPixels(
                    left: Int((insets.left * scale).rounded()),
                    top: Int((insets.top * scale).rounded()),
                    right: Int((insets.right * scale).rounded()),
                    bottom: Int((insets.bottom * scale).rounded())
                )
            }
        }
        guard let fallback else { return .zero }
        let scale = keyWindow?.windowScene?.screen.scale ?? UIScreen.main.scale
        return SafeAreaPixels(
            left: Int((fallback.leading * scale).rounded()),
            top: Int((fallback.top * scale).rounded()),
            right: Int((fallback.trailing * scale).rounded()),
            bottom: Int((fallback.bottom * scale).rounded())
        )
    }

    private static var keyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return active?.windows.first { $0.isKeyWindow } ?? active?.windows.first
    }
}

/// Fight configurations, copied from `docs/bridge-spec.md` (FightConfig v1) and extended for
/// Stage 3 by `docs/stage3-spec.md` section 2. If the spec changes, change it there first.
enum FightConfigFixture {

    /// The Stage 1 spike configuration, kept verbatim so the bridge spike screen still measures
    /// the same round trip it always did.
    static let json = #"""
{
  "schema": 1,
  "seed": 123456789,
  "arena": "yard",
  "rules": { "duration_s": 90, "ko_count_s": 10 },
  "bots": [
    {
      "id": "player-1", "name": "Tinribs", "controller": "player",
      "chassis": "wedge", "drive": "4wd", "weapon": "flipper",
      "utility": ["srimech", "spare_battery"],
      "armour": {
        "front": { "material": "steel", "thickness": 3 },
        "sides": { "material": "hdpe",  "thickness": 2 },
        "rear":  { "material": "polycarbonate", "thickness": 1 },
        "top":   { "material": "titanium", "thickness": 2 }
      },
      "damage": { "wheels": [1.0, 1.0, 1.0, 1.0], "weapon": 1.0, "armour": {"front":1.0,"sides":1.0,"rear":1.0,"top":1.0}, "drive": 1.0, "core": 1.0 }
    },
    { "id": "ai-1", "name": "Scrapheap", "controller": "ai", "chassis": "box", "drive": "2wd", "weapon": "saw",
      "utility": ["srimech"], "armour": { "front": {"material":"steel","thickness":2}, "sides": {"material":"steel","thickness":2}, "rear": {"material":"steel","thickness":2}, "top": {"material":"steel","thickness":2} },
      "damage": { "wheels": [1.0, 1.0], "weapon": 1.0, "armour": {"front":1.0,"sides":1.0,"rear":1.0,"top":1.0}, "drive": 1.0, "core": 1.0 } }
  ]
}
"""#

    /// Names for the ids in the fixture, used by the result sheet when the arena reports only ids.
    /// `ArenaHost` reads the names out of the configuration it actually sent.
    static let stage3BotOrder = ["player-1", "ai-1"]

    static let playerID = "player-1"
    static let opponentID = "ai-1"

    /// The Stage 4 fight: the player's own build against the Stage 3 fixture opponent, in The Yard.
    /// The opponent stays what it was until Stage 5 brings rivals, so a change in how a build
    /// fights is a change in the build and nothing else.
    ///
    /// Built as a dictionary and written by `JSONText`, which keeps every condition a float. The
    /// Stage 3 text template did the same job; `JSONSerialization` would turn 1.0 into `1` and the
    /// arena would read the conditions as ints (docs/stage3-swift-notes.md).
    static func fightJson(
        player: [String: Any],
        safeArea: SafeAreaPixels,
        opponentAI: String,
        mode: ArenaHost.FightMode
    ) -> String {
        // The test arena has no timer, no judges and a dummy opponent that is assembled but never
        // driven unless `debug.opponent_ai` says otherwise (docs/stage4-spec.md section 6).
        let rules: [String: Any] = mode.isTest
            ? ["mode": "test", "ko_count_s": 10]
            : ["mode": "fight", "duration_s": 90, "ko_count_s": 10]

        let root: [String: Any] = [
            "schema": 1,
            "seed": 123456789,
            "arena": "yard",
            "rules": rules,
            "presentation": [
                "safe_area_px": [
                    "left": safeArea.left,
                    "top": safeArea.top,
                    "right": safeArea.right,
                    "bottom": safeArea.bottom
                ],
                "haptics": RoboteerSettings.shared.haptics
            ],
            "debug": ["opponent_ai": opponentAI],
            "bots": [player, opponent(controller: mode.isTest ? "dummy" : "ai")]
        ]
        return JSONText.string(from: root)
    }

    /// The Stage 3 opponent: a wedge with a flipper in all steel, called Scrapheap.
    static func opponent(controller: String) -> [String: Any] {
        [
            "id": opponentID,
            "name": "Scrapheap",
            "controller": controller,
            "chassis": "wedge",
            "drive": "4wd",
            "weapon": "flipper",
            "utility": ["srimech"],
            "armour": [
                "front": ["material": "steel", "thickness": 2],
                "sides": ["material": "steel", "thickness": 2],
                "rear": ["material": "steel", "thickness": 2],
                "top": ["material": "steel", "thickness": 2]
            ],
            "livery": "#8a2f24",
            "damage": [
                "wheels": [1.0, 1.0, 1.0, 1.0],
                "weapon": 1.0,
                "armour": ["front": 1.0, "sides": 1.0, "rear": 1.0, "top": 1.0],
                "drive": 1.0,
                "core": 1.0
            ]
        ]
    }
}
