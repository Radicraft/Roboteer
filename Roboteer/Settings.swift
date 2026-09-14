//
//  Settings.swift
//  What the player chose, kept in UserDefaults and sent to the arena as one `settings` message.
//
//  The whole dictionary goes out every time, after `arena_ready` and on every change, so the arena
//  never has to merge partial updates and a late listener can be brought up to date by asking for
//  one more send.
//

import Foundation
import SwiftUI

@Observable
final class RoboteerSettings {

    static let shared = RoboteerSettings()

    /// How the sticks and the thumbs drive the bot.
    enum Scheme: String, CaseIterable, Identifiable {
        case arcade
        case tank

        var id: String { rawValue }

        var title: String {
            switch self {
            case .arcade: return "Arcade"
            case .tank: return "Tank"
            }
        }

        var blurb: String {
            switch self {
            case .arcade: return "One stick steers the machine the way you point it."
            case .tank: return "One side each, like the real thing. Harder, more precise."
            }
        }
    }

    private let defaults = UserDefaults.standard

    private enum Key {
        static let scheme = "settings.scheme"
        static let directorCut = "settings.directorCut"
        static let haptics = "settings.haptics"
        static let controlTips = "settings.controlTips"
        static let volume = "settings.volume"
    }

    var scheme: Scheme {
        didSet { defaults.set(scheme.rawValue, forKey: Key.scheme); changed() }
    }

    /// The knockout camera: the director's cut, or stay on the player's own machine.
    var directorCut: Bool {
        didSet { defaults.set(directorCut, forKey: Key.directorCut); changed() }
    }

    var haptics: Bool {
        didSet { defaults.set(haptics, forKey: Key.haptics); changed() }
    }

    /// The how to play callouts the arena draws over the countdown and the opening seconds: which
    /// stick drives, which button fires the weapon, how the camera is moved. On by default,
    /// because a player who already knows can turn them off and a player who does not cannot ask.
    /// Nothing new goes to the arena for this: the shell decides per fight and the arena only ever
    /// reads `coach` on the `fight_config` it is given (`CoachPolicy`).
    var controlTips: Bool {
        didSet { defaults.set(controlTips, forKey: Key.controlTips); changed() }
    }

    /// 0 to 1.
    var volume: Double {
        didSet {
            volume = min(1, max(0, volume))
            defaults.set(volume, forKey: Key.volume)
            changed()
        }
    }

    /// Called whenever anything changes, so the shell can push the whole thing to the arena.
    @ObservationIgnored var onChange: ((RoboteerSettings) -> Void)?

    private init() {
        let storedScheme = defaults.string(forKey: Key.scheme) ?? Scheme.arcade.rawValue
        scheme = Scheme(rawValue: storedScheme) ?? .arcade
        directorCut = defaults.object(forKey: Key.directorCut) as? Bool ?? true
        haptics = defaults.object(forKey: Key.haptics) as? Bool ?? true
        controlTips = defaults.object(forKey: Key.controlTips) as? Bool ?? true
        volume = defaults.object(forKey: Key.volume) as? Double ?? 0.8
    }

    private func changed() {
        onChange?(self)
    }

    /// The `settings` message payload. Everything the arena might want in one object.
    var dictionary: [String: Any] {
        [
            "scheme": scheme.rawValue,
            "director_cut": directorCut,
            "haptics": haptics,
            "volume": volume,
            // Presentation only, so the arena HUD can show the right button glyphs.
            "controller_connected": ControllerObserver.shared.showsHints,
            "controller_kind": ControllerObserver.shared.kind
        ]
    }

    /// Marketing version and build, for the About row.
    var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(version), build \(build)"
    }
}
