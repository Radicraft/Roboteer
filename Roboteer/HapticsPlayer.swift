//
//  HapticsPlayer.swift
//  Turns the arena's `haptic` messages into taps on the phone's haptic engine.
//  Contract: docs/stage3-spec.md section 3. One way, presentation only, never simulation.
//

import Foundation
import OSLog
import UIKit

let hapticsLog = Logger(subsystem: "com.radicraft.roboteer", category: "haptics")

final class HapticsPlayer {

    static let shared = HapticsPlayer()

    /// The arena coalesces to 30 a second already. This is the shell side belt and braces, so a
    /// misbehaving arena cannot flood the engine.
    private let minimumTickInterval: CFTimeInterval = 1.0 / 30.0
    private var lastTickAt: CFTimeInterval = 0
    private var impactGenerators: [Int: UIImpactFeedbackGenerator] = [:]
    private var notificationGenerator: UINotificationFeedbackGenerator?
    private var droppedTicks = 0

    private init() {}

    /// Call when a fight starts. Warms every generator so the first tap is not late.
    func prepare() {
        #if targetEnvironment(simulator)
        hapticsLog.info("haptics are a no operation on the simulator")
        #else
        for style in Self.usedStyles {
            generator(for: style).prepare()
        }
        notification().prepare()
        #endif
        lastTickAt = 0
        droppedTicks = 0
    }

    /// Release the generators when the fight ends so nothing is held warm on the menu.
    func relax() {
        impactGenerators.removeAll()
        notificationGenerator = nil
        if droppedTicks > 0 {
            hapticsLog.info("dropped \(self.droppedTicks, privacy: .public) ticks to the 30 a second throttle")
        }
        droppedTicks = 0
    }

    /// `kind` is one of tick, impact_light, impact_heavy, flip, ko_tick, bell.
    /// Anything else is logged and ignored. Must be called on the main thread.
    func play(kind: String) {
        switch kind {
        case "tick":
            let now = CACurrentMediaTime()
            guard now - lastTickAt >= minimumTickInterval else {
                droppedTicks += 1
                return
            }
            lastTickAt = now
            impact(.light)
        case "impact_light":
            impact(.medium)
        case "impact_heavy":
            impact(.heavy)
        case "flip":
            impact(.rigid)
        case "ko_tick":
            impact(.soft)
        case "bell":
            notify(.success)
        default:
            hapticsLog.warning("unknown haptic kind \(kind, privacy: .public)")
        }
    }

    // MARK: - Generators

    private static let usedStyles: [UIImpactFeedbackGenerator.FeedbackStyle] = [.light, .medium, .heavy, .rigid, .soft]

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if targetEnvironment(simulator)
        _ = style
        #else
        let engine = generator(for: style)
        engine.impactOccurred()
        engine.prepare()
        #endif
    }

    private func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        #if targetEnvironment(simulator)
        _ = type
        #else
        let engine = notification()
        engine.notificationOccurred(type)
        engine.prepare()
        #endif
    }

    private func generator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        if let existing = impactGenerators[style.rawValue] { return existing }
        let made = UIImpactFeedbackGenerator(style: style)
        impactGenerators[style.rawValue] = made
        return made
    }

    private func notification() -> UINotificationFeedbackGenerator {
        if let existing = notificationGenerator { return existing }
        let made = UINotificationFeedbackGenerator()
        notificationGenerator = made
        return made
    }
}
