//
//  RoboteerApp.swift
//  Roboteer. Landscape only, iPhone only.
//
//  See docs/bridge-spec.md. The Swift shell owns the app; Godot owns only the arena view.
//

import SwiftUI
import SwiftData
import OSLog
import Darwin

/// The one logger the shell writes to. `log stream --predicate 'subsystem == "com.radicraft.roboteer"'`
let spikeLog = Logger(subsystem: "com.radicraft.roboteer", category: "spike")

/// Launch timing reference points.
///
/// `firstTouch` is the moment Swift code first ran in this process (the `@main` type's initialiser
/// touches it). `processStart` is the honest one: the kernel's record of when the process was
/// forked, which includes dyld, the runtime and everything before any of our code ran.
enum LaunchClock {
    /// Captured the first time anything reads this type, which the app initialiser forces early.
    static let firstTouch = Date()

    /// True process start, read from `kinfo_proc.kp_proc.p_starttime` via `sysctl`.
    static let processStart: Date? = kernelProcessStart()

    /// Milliseconds from true process start (or first touch, if the kernel would not say) to now.
    static func msSinceProcessStart(_ now: Date = Date()) -> Double {
        let reference = processStart ?? firstTouch
        return now.timeIntervalSince(reference) * 1000.0
    }

    /// Milliseconds from the first line of our Swift to now.
    static func msSinceFirstTouch(_ now: Date = Date()) -> Double {
        now.timeIntervalSince(firstTouch) * 1000.0
    }

    private static func kernelProcessStart() -> Date? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        let started = info.kp_proc.p_starttime
        let seconds = Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000.0
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

@main
struct RoboteerApp: App {
    @Environment(\.scenePhase) private var scenePhase

    /// One host, one GodotApp, for the life of the process.
    @State private var host = ArenaHost.shared

    /// One SwiftData store, holding the garage.
    private let container: ModelContainer

    init() {
        // Force the launch clock to latch before anything else happens.
        _ = LaunchClock.firstTouch
        let kernelKnown = LaunchClock.processStart != nil
        spikeLog.info("app init at \(LaunchClock.msSinceProcessStart(), privacy: .public) ms since process start (kernel start time available: \(kernelKnown, privacy: .public))")
        // The Broadcast system's type. Registered before any view is built, so the first frame is
        // already in Barlow Condensed rather than swapping face a moment later.
        BroadcastType.register()
        spikeLog.info("type: \(BroadcastType.familyNote, privacy: .public)")
        // `-careerSelfTest` runs the career engine through a scripted season and prints one line
        // per invariant. It is pure and touches no store, so it runs before the container opens.
        CareerSelfTest.runIfRequested()
        container = RoboteerApp.makeContainer()
    }

    /// The garage on disk. If the store will not open, the app runs on an in memory one rather
    /// than refusing to launch: a player with a broken store should still get a game.
    private static func makeContainer() -> ModelContainer {
        do {
            // S6 (stage 6): `EventRecord` is the side events' best scores.
            return try ModelContainer(for: BotBuild.self, CareerState.self, RivalRecord.self, FightLog.self, EventRecord.self)
        } catch {
            spikeLog.error("the garage store did not open: \(String(describing: error), privacy: .public)")
            let memory = ModelConfiguration(isStoredInMemoryOnly: true)
            // A failure here is unrecoverable and would mean the model itself is malformed.
            return try! ModelContainer(for: BotBuild.self, CareerState.self, RivalRecord.self, FightLog.self, EventRecord.self, configurations: memory)
        }
    }

    var body: some Scene {
        WindowGroup {
            // `-openMatchReport`, `-openRewards` and `-openRetryPrompt` (docs/qa-launch-flags.md)
            // raise one post-match screen on fixture data instead of the game, so the three can be
            // read and screenshotted without fighting a match first. Nil in every ordinary launch.
            Group {
                if let qa = PostMatchQA.requested {
                    PostMatchQAView(host: host, screen: qa)
                } else {
                    RootView(host: host)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                host.handleScenePhase(phase)
            }
        }
        .modelContainer(container)
    }
}
