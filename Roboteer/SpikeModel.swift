//
//  SpikeModel.swift
//  Owns the single GodotApp, the bridge handle, and every Stage 1 measurement.
//
//  Message contract: docs/bridge-spec.md. Two keys only, "type" and "json".
//

import Foundation
import SwiftUI
import OSLog
import SwiftGodot
import SwiftGodotKit

@Observable
final class SpikeModel {

    /// One GodotApp per process. Never recreated. Backgrounding pauses it, it is not torn down.
    static let shared = SpikeModel()

    @ObservationIgnored let app: GodotApp
    @ObservationIgnored private var handle: GodotAppViewHandle?
    @ObservationIgnored private var eventHandlerToken: UUID?
    @ObservationIgnored private var configSentAt: Date?
    @ObservationIgnored private var didScheduleFiveSecondSample = false

    // Timings, all milliseconds from true process start.
    var readyMs: Double?
    var arenaReadyMs: Double?
    var roundTripMs: Double?

    // phys_footprint samples, megabytes.
    var memoryAtReadyMB: Double?
    var memoryPlusFiveMB: Double?
    var memoryLatestMB: Double?

    var lastMessageType: String = "none yet"
    var godotVersion: String = "unknown"
    var arenaReady: Bool = false
    var resultJSON: String = ""
    var errorText: String?
    var eventLog: [String] = []

    private init() {
        // QA hooks: `-godotDriver metal|opengl3`, `-godotMethod mobile|gl_compatibility`, `-godotVerbose`.
        let args = ProcessInfo.processInfo.arguments
        func arg(_ name: String) -> String? {
            guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let driver = arg("-godotDriver") ?? "metal"
        let method = arg("-godotMethod") ?? "mobile"
        var extra: [String] = []
        if args.contains("-godotVerbose") { extra.append("--verbose") }
        let display = arg("-godotDisplay") ?? "embedded"
        HostBridge.install()
        app = GodotApp(packFile: "arena.pck", renderingDriver: driver, renderingMethod: method, displayDriver: display, extraArgs: extra)
        HostBridge.onMessage = { [weak self] type, json in self?.receiveRaw(type: type, json: json) }
        spikeLog.info("Godot driver \(driver, privacy: .public) method \(method, privacy: .public) extra \(extra.joined(separator: " "), privacy: .public)")
        eventHandlerToken = app.registerEventHandler { [weak self] event in
            self?.handleGodotEvent(event)
        }
        spikeLog.info("GodotApp created at \(LaunchClock.msSinceProcessStart(), privacy: .public) ms")
    }

    // MARK: - Bridge wiring

    /// Called by `GodotAppView` once the Godot scene tree root exists.
    func onReady(_ handle: GodotAppViewHandle) {
        self.handle = handle
        let ms = LaunchClock.msSinceProcessStart()
        if readyMs == nil {
            readyMs = ms
            spikeLog.info("onReady at \(ms, privacy: .public) ms since process start")
        }
        sampleMemory(into: \.memoryLatestMB)
    }

    /// Called by `GodotAppView` on the main thread for every message Godot sends.
    func receive(_ dict: VariantDictionary) {
        let type = String(dict["type"]) ?? ""
        let json = String(dict["json"]) ?? "{}"
        spikeLog.info("received via SwiftGodotKit view callback")
        receiveRaw(type: type, json: json)
    }

    func receiveRaw(type: String, json: String) {
        lastMessageType = type.isEmpty ? "empty type" : type
        spikeLog.info("received \(type, privacy: .public), \(json.count, privacy: .public) bytes of json")

        switch type {
        case "arena_ready":
            handleArenaReady(json)
        case "fight_result":
            handleFightResult(json)
        case "arena_log":
            handleArenaLog(json)
        default:
            spikeLog.warning("unknown message type \(type, privacy: .public)")
        }
    }

    private func handleArenaReady(_ json: String) {
        let ms = LaunchClock.msSinceProcessStart()
        arenaReadyMs = ms
        arenaReady = true
        if let object = jsonObject(json) {
            godotVersion = object["godot_version"] as? String ?? "unknown"
            if let schema = object["schema"] as? Int, schema != 1 {
                errorText = "Arena reports schema \(schema). This build speaks schema 1."
            }
        }
        spikeLog.info("arena_ready at \(ms, privacy: .public) ms, godot \(self.godotVersion, privacy: .public)")

        sampleMemory(into: \.memoryAtReadyMB)
        sampleMemory(into: \.memoryLatestMB)
        scheduleFiveSecondSample()
        // QA hook: `-autoSendFight` sends the fixture one second after the arena is ready.
        if ProcessInfo.processInfo.arguments.contains("-autoSendFight") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.sendFightConfig() }
        }
    }

    private func handleFightResult(_ json: String) {
        if let sentAt = configSentAt {
            let ms = Date().timeIntervalSince(sentAt) * 1000.0
            roundTripMs = ms
            spikeLog.info("fight_config to fight_result round trip \(ms, privacy: .public) ms")
        }
        resultJSON = prettyPrinted(json)
        sampleMemory(into: \.memoryLatestMB)

        // Prove the payload survived the crossing, per the spec's diagnostics.echo.
        if let object = jsonObject(json),
           let diagnostics = object["diagnostics"] as? [String: Any],
           let echo = diagnostics["echo"] as? [String: Any] {
            let arena = echo["arena"] as? String ?? "missing"
            let bots = echo["bot_count"] as? Int ?? -1
            let seed = echo["seed"] as? Int ?? -1
            spikeLog.info("echo arena \(arena, privacy: .public), bots \(bots, privacy: .public), seed \(seed, privacy: .public)")
            if arena != "yard" || bots != 2 || seed != 123456789 {
                errorText = "The returned echo does not match the config that was sent."
            }
        } else {
            errorText = "The result carried no diagnostics.echo block."
        }
    }

    private func handleArenaLog(_ json: String) {
        guard let object = jsonObject(json) else { return }
        let level = object["level"] as? String ?? "info"
        let text = object["text"] as? String ?? ""
        spikeLog.info("arena_log \(level, privacy: .public): \(text, privacy: .public)")
        if level == "error" { errorText = text }
    }

    // MARK: - Sending

    /// The one message this spike sends. Two keys, exactly as the spec says.
    func send(type: String, json: String) {
        guard handle != nil, arenaReady else {
            errorText = "The arena is not ready yet, so nothing was sent."
            spikeLog.error("send(\(type, privacy: .public)) before arena_ready")
            return
        }
        HostBridge.send(type: type, json: json)
        spikeLog.info("sent \(type, privacy: .public), \(json.count, privacy: .public) bytes of json")
    }

    func sendFightConfig() {
        errorText = nil
        resultJSON = ""
        roundTripMs = nil
        configSentAt = Date()
        send(type: "fight_config", json: FightConfigFixture.json)
    }

    // MARK: - Memory

    func sampleMemoryNow() {
        sampleMemory(into: \.memoryLatestMB)
    }

    private func sampleMemory(into keyPath: ReferenceWritableKeyPath<SpikeModel, Double?>) {
        guard let bytes = Self.physFootprintBytes() else { return }
        let megabytes = Double(bytes) / (1024.0 * 1024.0)
        self[keyPath: keyPath] = megabytes
        spikeLog.info("phys_footprint \(megabytes, privacy: .public) MB")
    }

    private func scheduleFiveSecondSample() {
        guard !didScheduleFiveSecondSample else { return }
        didScheduleFiveSecondSample = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            self.sampleMemory(into: \.memoryPlusFiveMB)
            self.sampleMemory(into: \.memoryLatestMB)
        }
    }

    /// Physical memory footprint, the number Jetsam judges the app by.
    static func physFootprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.phys_footprint)
    }

    // MARK: - Lifecycle

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            spikeLog.info("scene phase background, pausing Godot")
            app.pause()
            app.stopDrawing()
        case .active:
            spikeLog.info("scene phase active, resuming Godot")
            app.resume()
            app.startDrawing()
        case .inactive:
            spikeLog.info("scene phase inactive")
        @unknown default:
            break
        }
    }

    // MARK: - Godot runtime events

    private func handleGodotEvent(_ event: GodotAppEvent) {
        let line: String
        switch event {
        case .startupFailure(let failure):
            line = "startupFailure \(failure.reason.rawValue) at \(failure.sourcePath), scene \(failure.scene ?? "default")"
            spikeLog.error("\(line, privacy: .public)")
            errorText = "Godot did not start. \(failure.reason.rawValue)."
        case .warning(let warning):
            line = "warning \(warning.code.rawValue): \(warning.detail)"
            spikeLog.warning("\(line, privacy: .public)")
        case .bridge(let bridge):
            line = "bridge \(bridge.state.rawValue)"
            spikeLog.info("\(line, privacy: .public)")
        case .windowBinding(let binding):
            line = "windowBinding \(binding.state.rawValue), node \(binding.nodeName ?? "none"), owns \(binding.ownsWindow), platform \(binding.platform)"
            spikeLog.info("\(line, privacy: .public)")
        case .lifecycle(let lifecycle):
            line = "lifecycle \(lifecycle.label) (\(lifecycle.notification))"
            spikeLog.info("\(line, privacy: .public)")
        }
        eventLog.append(line)
        if eventLog.count > 40 { eventLog.removeFirst(eventLog.count - 40) }
    }

    // MARK: - JSON helpers

    private func jsonObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    private func prettyPrinted(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8) else { return text }
        return string
    }
}
