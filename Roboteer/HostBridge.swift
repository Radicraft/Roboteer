//
//  HostBridge.swift
//  Roboteer's own Godot <-> Swift bridge object, registered as the engine singleton "RoboteerHost".
//  Contract: docs/bridge-spec.md. Every message is (type: String, json: String).
//

import Foundation
import OSLog
import SwiftGodot
import SwiftGodotKit

private let bridgeLog = Logger(subsystem: "com.radicraft.roboteer", category: "bridge")

@Godot
final class HostBridge: Object {
    nonisolated(unsafe) static let shared = HostBridge()

    /// Swift -> Godot. GDScript connects to `message_from_host`.
    @Signal var messageFromHost: SignalWithArguments<String, String>

    /// Godot -> Swift: GDScript emits `message_to_host(type, json)` and Swift is connected to it.
    /// Signals are the ONLY working Godot -> Swift path in SwiftGodot 0.75 / libgodot 4.6:
    /// `@Callable` methods on a Swift object are not invokable from GDScript (measured 2026-09-13).
    @Signal var messageToHost: SignalWithArguments<String, String>

    /// Set by the shell. Always invoked on the main thread.
    nonisolated(unsafe) static var onMessage: ((String, String) -> Void)?

    /// The message types that arrive many times a second while a fight or a replay is running.
    /// Logging one line each is console spam in a hot path, so they are not logged (wave P,
    /// agent H). Everything else is one line per event.
    private static let quiet: Set<String> = ["haptic", "replay_state"]

    static func deliver(type: String, json: String, via: String) {
        if !quiet.contains(type) {
            bridgeLog.info("host received \(type, privacy: .public) via \(via, privacy: .public), \(json.count, privacy: .public) bytes")
        }
        let handler = onMessage
        if Thread.isMainThread {
            handler?(type, json)
        } else {
            DispatchQueue.main.async { handler?(type, json) }
        }
    }

    /// Call once, before the GodotApp starts. Registers the class and the singleton at scene level.
    static func install() {
        let previous = initHookCb
        initHookCb = { level in
            previous?(level)
            guard level == .scene else { return }
            register(type: HostBridge.self)
            Engine.registerSingleton(name: "RoboteerHost", instance: HostBridge.shared)
            HostBridge.shared.messageToHost.connect { type, json in
                HostBridge.deliver(type: type, json: json, via: "signal")
            }
            bridgeLog.info("RoboteerHost singleton registered")
        }
    }

    /// Swift -> Godot send. Must run on the Godot (main) thread.
    static func send(type: String, json: String) {
        shared.messageFromHost.emit(type, json)
    }
}
