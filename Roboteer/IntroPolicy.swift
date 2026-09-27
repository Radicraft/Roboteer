//
//  IntroPolicy.swift
//  Which fights open with the arena intro, and how much of it.
//
//  Before the countdown the arena can fly the camera past each of its hazards, naming them, then
//  drop onto the player's machine (docs/wave-b-intro-notes.md). The arena plays what the
//  `fight_config` asks for in `"intro"`: "full" (about 6 s), "short" (about 2 s) or "none"; no key
//  is none. This file is the shell's decision:
//
//    - full the first time the player fights in an arena on this device,
//    - short in an arena already seen,
//    - none for the test arena, side events and replays (they never arm it), and for a quick
//      restart: the same arena again within a few minutes of the last fight starting there.
//
//  The seen arenas live in UserDefaults, like the coach counter; they are a presentation memory,
//  not career state, so a new career does not replay every intro.
//

import Foundation

enum IntroPolicy {

    private static let seenKey = "intro.seenArenas"

    /// A fight in the same arena this soon after the last one started is a restart: straight in.
    static let quickRestartSeconds: TimeInterval = 180

    /// In memory only: a relaunch is never a quick restart.
    private static var lastArena: String?
    private static var lastStartedAt: Date?

    static var seenArenas: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: seenKey) }
    }

    /// "full", "short" or "none" for a fight about to start in `arena`.
    static func mode(arena: String, isTest: Bool, now: Date = Date()) -> String {
        if isTest { return "none" }
        if let lastArena, let lastStartedAt, lastArena == arena,
           now.timeIntervalSince(lastStartedAt) < quickRestartSeconds {
            return "none"
        }
        return seenArenas.contains(arena) ? "short" : "full"
    }

    /// Set the key the next `fight_config` carries. Always assigns, so it never leaks forward.
    static func arm(_ host: ArenaHost, arena: String, isTest: Bool) {
        host.introNextFight = mode(arena: arena, isTest: isTest)
    }

    /// Call once per fight, the moment the arena says it has started one (the countdown), so a
    /// fight that never got going does not use up the arena's full intro.
    static func fightStarted(arena: String, now: Date = Date()) {
        var seen = seenArenas
        if !seen.contains(arena) {
            seen.insert(arena)
            seenArenas = seen
        }
        lastArena = arena
        lastStartedAt = now
    }
}
