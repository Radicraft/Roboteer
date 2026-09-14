//
//  CoachPolicy.swift
//  Which fights open with the how to play callouts on screen.
//
//  The owner played the first build and said it did not feel play tested: no idea what the controls
//  were, no idea how to move the camera. The arena draws the callouts when its `fight_config`
//  carries `"coach": true` (`ArenaHost.coachNextFight`); this file is the shell's decision about
//  when it does. Nothing new crosses the bridge for it.
//

import Foundation

enum CoachPolicy {

    /// Every player is shown the controls for this many fights, whatever they have set, because a
    /// player who has never held the thing cannot know to ask for them.
    static let openingFights = 3

    private static let key = "coach.fightsStarted"

    /// Fights that actually got going on this device. Counted at the countdown, not at the tap, so
    /// a fight the arena never started does not use one up.
    static var fightsStarted: Int {
        get { UserDefaults.standard.integer(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// The test arena is always coached: it exists to be poked at, and nobody arrives there
    /// knowing the controls either.
    static func shouldCoach(mode: ArenaHost.FightMode) -> Bool {
        if mode.isTest { return true }
        if RoboteerSettings.shared.controlTips { return true }
        return fightsStarted < openingFights
    }

    /// Call once per fight, the moment the arena says it has started one.
    static func fightStarted() {
        guard fightsStarted < 1_000_000 else { return }
        fightsStarted += 1
    }

    /// Set the flag the next `fight_config` reads. Always assigns, so a coached fight followed by
    /// an uncoached one does not leak the flag forward.
    static func arm(_ host: ArenaHost, mode: ArenaHost.FightMode) {
        host.coachNextFight = shouldCoach(mode: mode)
    }
}
