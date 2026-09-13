//
//  RoboteerApp.swift
//  Roboteer Stage 1 bridge spike.
//
//  See docs/bridge-spec.md. The Swift shell owns the app; Godot owns only the arena view.
//

import SwiftUI
import OSLog
import Darwin

/// The one logger the spike writes to. `log stream --predicate 'subsystem == "com.radicraft.roboteer"'`
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

    /// One model, one GodotApp, for the life of the process.
    @State private var model = SpikeModel.shared

    init() {
        // Force the launch clock to latch before anything else happens.
        _ = LaunchClock.firstTouch
        let kernelKnown = LaunchClock.processStart != nil
        spikeLog.info("app init at \(LaunchClock.msSinceProcessStart(), privacy: .public) ms since process start (kernel start time available: \(kernelKnown, privacy: .public))")
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onChange(of: scenePhase) { _, phase in
                    model.handleScenePhase(phase)
                }
        }
    }
}
