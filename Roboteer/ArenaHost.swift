//
//  ArenaHost.swift
//  Owns the single GodotApp for the life of the process, the bridge wiring, the Stage 1
//  measurements and the Stage 3 fight state.
//
//  Message contract: docs/bridge-spec.md. Two keys only, "type" and "json".
//  Stage 3 additions: docs/stage3-spec.md sections 2, 3 and 12.
//  Stage 4 additions: the lit stage (`workshop_config` / `workshop_ready`) and the test arena
//  (`rules.mode = "test"` / `test_reset`), docs/stage4-spec.md sections 5, 6 and 7.
//

import Foundation
import SwiftUI
import OSLog
import SwiftGodot
import SwiftGodotKit

@Observable
final class ArenaHost {

    /// One GodotApp per process. Never recreated. Leaving the fight pauses it, it is not torn down.
    static let shared = ArenaHost()

    /// The fight states the arena reports, plus the state before a configuration has landed.
    ///
    /// Stage 6 (agent S6) adds `abandoned`: the arena gave up on a fight or an event without a
    /// result, which is a screen to leave rather than a result to record.
    enum FightState: String {
        case loading
        case countdown
        case fighting
        case result
        case abandoned
    }

    /// Stage 6 (agent S6): where a replay has got to. The arena sends `replay_state` every ten
    /// ticks while a recording plays back.
    struct ReplayState: Equatable {
        var tick: Int = 0
        var total: Int = 0
        var finished: Bool = false
    }

    /// What the one Godot view is showing. The arena switches on the message it was last sent.
    enum Surface {
        /// The lit stage with the player's own bot on it, behind the menus.
        case stage
        /// A fight or the test arena, full screen.
        case fight
    }

    /// A fight or the test arena. The test arena has no timer and a reset button.
    enum FightMode {
        case fight
        case test

        var isTest: Bool { self == .test }
    }

    /// What `workshop_ready` reports after the arena assembles the bot on the stage. Every field
    /// is optional because the arena is the authority on which it can measure.
    struct WorkshopSummary: Equatable {
        var totalKg: Double?
        var clearanceM: Double?
        var comHeightM: Double?
        /// Weights per category, in the order the arena listed them.
        var categories: [String] = []
        var categoryWeights: [String: Double] = [:]

        var isEmpty: Bool {
            totalKg == nil && clearanceM == nil && comHeightM == nil && categories.isEmpty
        }
    }

    @ObservationIgnored let app: GodotApp
    @ObservationIgnored private var handle: GodotAppViewHandle?
    @ObservationIgnored private var eventHandlerToken: UUID?
    @ObservationIgnored private var configSentAt: Date?
    @ObservationIgnored private var didScheduleFiveSecondSample = false
    @ObservationIgnored private var pendingConfigJSON: String?
    @ObservationIgnored private var rearmRetry: DispatchWorkItem?
    @ObservationIgnored private var didRetryThisFight = false
    @ObservationIgnored private var expectSpikeEcho = false
    @ObservationIgnored private(set) var fightIsOnScreen = false
    @ObservationIgnored private var pendingWorkshopJSON: String?
    @ObservationIgnored private var workshopDebounce: DispatchWorkItem?
    @ObservationIgnored private var lastWorkshopJSON: String?
    // The turntable gesture, summed between sends.
    @ObservationIgnored private var stageCameraOrbit: CGSize = .zero
    @ObservationIgnored private var stageCameraPinch: Double = 1
    @ObservationIgnored private var stageCameraFlush: DispatchWorkItem?
    @ObservationIgnored private var pendingSettingsJSON: String?
    /// False only when this run was asked for a headless or dummy renderer.
    @ObservationIgnored private(set) var rendersLive = true

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

    // MARK: - The warm up behind the loading screen (2026-09-21)
    //
    // The one Godot view is behind every menu, so the first frame a player ever sees is a full
    // 3D frame and every material in it has its pipeline compiled and its textures uploaded
    // right then, on the main thread. Until that finishes SwiftUI cannot redraw either: the
    // turntable looks empty and the menu reads as inactive (docs/stage-bug-2026-09-21.md).
    // The arena now walks the whole catalogue once, before the menu is shown, and reports its
    // progress here so the loading screen can stand in front of it.

    /// 0 to 1. What the arena has got through.
    var preloadFraction: Double = 0
    /// The one plain sentence on the loading screen. Written by the arena.
    var preloadLine: String = ""
    /// True once the arena has finished, or once the shell has given up waiting for it.
    var preloadDone: Bool = false
    /// How long the walk took, milliseconds, as the arena measured it.
    var preloadMs: Double?
    /// True when the loading screen was never shown at all: a QA launch with `-skipLoading`,
    /// or a run with no live renderer, where there is nothing to warm.
    @ObservationIgnored private(set) var preloadSkipped = false
    @ObservationIgnored private var preloadGiveUp: DispatchWorkItem?
    var resultJSON: String = ""
    var errorText: String?
    var eventLog: [String] = []

    // Stage 4 stage state.
    /// What the one Godot view is showing right now.
    var surface: Surface = .stage
    /// True while the stage is orbiting somebody else's machine for the scouting report, so the
    /// menus do not put the player's own bot back over it.
    var scoutingOpponent: Bool = false
    /// The numbers the arena measured for the bot standing on the stage.
    var workshopSummary: WorkshopSummary?
    /// Which mode the current fight configuration asked for.
    var fightMode: FightMode = .fight

    // Stage 3 fight state.
    var fightState: FightState = .loading
    /// Which half of the round the arena says it is in: "open" until 2:00, then "endgame"
    /// (brief v4 section 2, `docs/wave-g-contracts.md`). Every `fight_state` carries it, and the
    /// arena sends one extra on the endgame tick. It is a plain string rather than an enum
    /// because the shell only ever compares it, and an unknown phase must never drop a message.
    var fightPhase: String = "open"
    var lastResult: FightResult?
    /// Names for the bot ids, read out of the configuration that was actually sent.
    var botNames: [String: String] = [:]
    /// The bot ids in the order the configuration listed them.
    var botOrder: [String] = []
    /// The safe area, in Godot pixels, that went out with the current fight configuration.
    var sentSafeArea: SafeAreaPixels = .zero
    /// Bumped every time the arena sends `pause_requested` (the pad's START button). The fight
    /// screen watches it and puts its pause overlay up; a counter rather than a flag because two
    /// presses in a row must both be seen.
    var pauseRequests = 0

    // MARK: Stage 6 state (agent S6: side events and replays)

    /// The last `event_result` the arena sent, and the raw text it arrived as.
    var lastEventResult: EventResult?
    var eventResultJSON: String = ""
    /// Where the replay currently playing has got to, or nil when nothing is being replayed.
    var replayState: ReplayState?
    /// What the replay bar last asked for. The arena is the authority, but the bar has to draw
    /// something the moment it is pressed.
    var replayIsPlaying: Bool = true
    var replaySpeed: Double = 1.0
    /// The last `fight_config` this process sent, kept so a fight can be written into its log with
    /// the configuration that produced it and replayed from it later.
    private(set) var lastFightConfigJSON: String = ""

    // MARK: - Launch arguments

    static func launchArgument(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static func hasLaunchFlag(_ name: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(name)
    }

    /// `-opponentAI idle|charge|normal`, passed through to `debug.opponent_ai`.
    static var opponentAI: String {
        let value = launchArgument("-opponentAI") ?? "normal"
        return ["idle", "charge", "normal"].contains(value) ? value : "normal"
    }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private init() {
        // The simulator slice of libgodot has no Metal driver, so the simulator renders through
        // OpenGL ES 3 instead (docs/simulator-rendering.md): a patched libgodot gives the embedded
        // display server its own CAEAGLLayer inside the layer SwiftGodotKit hands over. The device
        // is unchanged and still uses Metal. Explicit launch arguments override both sets of
        // defaults, so `-godotDriver dummy -godotMethod dummy -godotDisplay headless` still gets
        // the headless arena on the simulator.
        #if targetEnvironment(simulator)
        let defaultDriver = "opengl3"
        let defaultMethod = "gl_compatibility"
        let defaultDisplay = "embedded"
        #else
        let defaultDriver = "metal"
        let defaultMethod = "mobile"
        let defaultDisplay = "embedded"
        #endif

        let driver = Self.launchArgument("-godotDriver") ?? defaultDriver
        let method = Self.launchArgument("-godotMethod") ?? defaultMethod
        let display = Self.launchArgument("-godotDisplay") ?? defaultDisplay
        var extra: [String] = []
        if Self.hasLaunchFlag("-godotVerbose") { extra.append("--verbose") }

        // Whether this run can draw anything at all. A headless or dummy run still has live
        // physics, rules and bridge, but the stage behind the menus has to be the rendered still.
        rendersLive = display != "headless" && driver != "dummy" && method != "dummy"

        HostBridge.install()
        app = GodotApp(packFile: "arena.pck", renderingDriver: driver, renderingMethod: method, displayDriver: display, extraArgs: extra)
        HostBridge.onMessage = { [weak self] type, json in self?.receiveRaw(type: type, json: json) }
        spikeLog.info("Godot driver \(driver, privacy: .public) method \(method, privacy: .public) display \(display, privacy: .public) extra \(extra.joined(separator: " "), privacy: .public)")
        eventHandlerToken = app.registerEventHandler { [weak self] event in
            self?.handleGodotEvent(event)
        }
        spikeLog.info("GodotApp created at \(LaunchClock.msSinceProcessStart(), privacy: .public) ms")

        // The loading screen only makes sense in front of a renderer. A headless or dummy run
        // has nothing to warm, and `-skipLoading` is the QA flag for a screenshot that must not
        // have to wait for one (docs/qa-launch-flags.md).
        if !rendersLive {
            skipPreload("this run has no live renderer")
        } else if let flag = Self.loadingSkipFlags.first(where: { Self.hasLaunchFlag($0) }) {
            skipPreload(flag)
        } else {
            // Armed now, not when the arena answers: an arena that never comes up at all (a
            // missing pck, an engine that failed to start) must not leave the loading screen
            // standing over a game nobody can reach.
            armPreloadGiveUp()
        }
    }

    /// QA launch flags that skip the loading screen (docs/qa-launch-flags.md). The ones that
    /// drop straight into a FIGHT skip it, because the fight would otherwise start and run its
    /// countdown behind the scrim; everything else (`-autoBuilder`, `-autoWorkshop`, the career
    /// flags) waits behind the loading screen like a player does, so its first frame is the
    /// warmed one. `-skipLoading` skips it for anything.
    static let loadingSkipFlags = ["-skipLoading", "-autoFight", "-autoTest", "-autoCareerFight", "-autoSendFight"]

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
        deliverPendingConfig()
        deliverPendingWorkshop()
        deliverPendingSettings()
    }

    /// Called by `GodotAppView` on the main thread for every message Godot sends.
    func receive(_ dict: VariantDictionary) {
        let type = String(dict["type"]) ?? ""
        let json = String(dict["json"]) ?? "{}"
        spikeLog.info("received via SwiftGodotKit view callback")
        receiveRaw(type: type, json: json)
    }

    /// The single dispatch point for every message type in the contract.
    func receiveRaw(type: String, json: String) {
        lastMessageType = type.isEmpty ? "empty type" : type
        // `haptic` and `replay_state` arrive many times a second; one log line each is spam in a
        // hot path (wave P, agent H). Every other type is one line per event.
        if type != "haptic" && type != "replay_state" {
            spikeLog.info("received \(type, privacy: .public), \(json.count, privacy: .public) bytes of json")
        }

        switch type {
        case "arena_ready":
            handleArenaReady(json)
        case "fight_state":
            handleFightState(json)
        case "fight_result":
            handleFightResult(json)
        // Stage 6 (agent S6): a side event reports a score, not a fight result, and a replay
        // reports where it has got to.
        case "event_result":
            handleEventResult(json)
        case "replay_state":
            handleReplayState(json)
        case "workshop_ready":
            handleWorkshopReady(json)
        // The catalogue warm up behind the loading screen.
        case "preload_progress":
            handlePreloadProgress(json)
        case "preload_done":
            handlePreloadDone(json)
        // The pad's START button. The arena does not pause itself: it asks, the shell decides,
        // and the shell answers with `fight_control` pause.
        case "pause_requested":
            handlePauseRequested()
        case "haptic":
            handleHaptic(json)
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
                errorText = "The arena reports schema \(schema). This build speaks schema 1."
            }
        }
        spikeLog.info("arena_ready at \(ms, privacy: .public) ms, godot \(self.godotVersion, privacy: .public)")

        sampleMemory(into: \.memoryAtReadyMB)
        sampleMemory(into: \.memoryLatestMB)
        scheduleFiveSecondSample()

        // A fight or a stage may be waiting on the arena. Send it the moment the arena is there.
        deliverPendingConfig()
        deliverPendingWorkshop()
        deliverPendingSettings()

        // Everything the stage and the fight will need, read and drawn once, while the loading
        // screen is still up. Sent after the workshop config above, so the player's own machine
        // is bound first and is already standing on the turntable when the menu appears.
        beginPreload()

        // QA hook: `-autoSendFight` sends the spike fixture one second after the arena is ready.
        if Self.hasLaunchFlag("-autoSendFight") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.sendSpikeConfig() }
        }
    }

    // MARK: - The warm up

    /// How long the shell will wait for the arena before it shows the menu anyway. The loading
    /// screen must never be able to trap the game: a build with no arena, a pck that predates
    /// the warm up, or a renderer that was never started all end here instead of on a dead
    /// screen. Generous, because the phone's first ever launch is the slowest one it will have.
    static let preloadGiveUpSeconds: Double = 40

    /// Ask the arena to read and draw everything once. Answered by `preload_progress` and then
    /// `preload_done`. Idempotent: the arena ignores a second request while one is running.
    func beginPreload() {
        guard !preloadDone, !preloadSkipped else { return }
        guard arenaReady, handle != nil else { return }
        // `models: false` reads everything but skips the off screen draw. Nothing passes it
        // today; it is the switch to reach for if the draw ever misbehaves on a device.
        send(type: "preload_begin", json: "{}")
        // A fresh allowance from here: the time the engine took to come up is not the walk's.
        armPreloadGiveUp()
    }

    /// Show the menu anyway after `preloadGiveUpSeconds`, whatever the arena has or has not said.
    private func armPreloadGiveUp() {
        preloadGiveUp?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.preloadDone else { return }
            spikeLog.warning("the warm up did not finish in \(Self.preloadGiveUpSeconds, privacy: .public) s; showing the menu anyway")
            self.preloadLine = ""
            self.preloadFraction = 1
            self.preloadDone = true
        }
        preloadGiveUp = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.preloadGiveUpSeconds, execute: work)
    }

    /// There is nothing to warm and nothing to wait for: no live renderer, or a QA launch that
    /// asked to go straight in. The loading screen is never shown.
    func skipPreload(_ why: String) {
        guard !preloadSkipped else { return }
        preloadSkipped = true
        preloadFraction = 1
        preloadLine = ""
        preloadDone = true
        preloadGiveUp?.cancel()
        preloadGiveUp = nil
        spikeLog.info("loading screen skipped: \(why, privacy: .public)")
    }

    private func handlePreloadProgress(_ json: String) {
        guard !preloadDone, let object = jsonObject(json) else { return }
        if let fraction = object["fraction"] as? Double {
            // Only ever forwards: a late message from an earlier walk cannot pull the lights
            // back down once they have come up.
            preloadFraction = max(preloadFraction, min(1, max(0, fraction)))
        }
        if let line = object["line"] as? String, !line.isEmpty {
            preloadLine = line
        }
    }

    private func handlePreloadDone(_ json: String) {
        preloadGiveUp?.cancel()
        preloadGiveUp = nil
        if let object = jsonObject(json) {
            preloadMs = (object["ms"] as? NSNumber)?.doubleValue
            let number = { (key: String) -> Double in (object[key] as? NSNumber)?.doubleValue ?? -1 }
            spikeLog.info("warm up done in \(self.preloadMs ?? -1, privacy: .public) ms (read \(number("read_ms"), privacy: .public) ms, draw \(number("draw_ms"), privacy: .public) ms): \(Int(number("scenes")), privacy: .public) scenes, \(Int(number("models")), privacy: .public) models, \(Int(number("materials")), privacy: .public) materials, \(Int(number("sounds")), privacy: .public) sounds, \(Int(number("warmed")), privacy: .public) drawn")
        }
        spikeLog.info("first playable frame at \(LaunchClock.msSinceProcessStart(), privacy: .public) ms since process start")
        preloadFraction = 1
        preloadDone = true
    }

    private func handleFightState(_ json: String) {
        let object = jsonObject(json)
        // The phase is read BEFORE the state is checked: `paused` and `resumed` are not members
        // of FightState and fall out of the guard below, and the half of the round they were
        // sent in is still true.
        if let phase = object?["phase"] as? String, !phase.isEmpty {
            fightPhase = phase
        }
        guard let object,
              let name = object["state"] as? String,
              let state = FightState(rawValue: name) else {
            spikeLog.warning("fight_state with no state this build understands: \(json, privacy: .public)")
            return
        }
        fightState = state
        spikeLog.info("fight_state \(name, privacy: .public)")
        // The arena is clearly alive, so the defensive resend is no longer wanted.
        rearmRetry?.cancel()
        rearmRetry = nil
        if state == .countdown {
            HapticsPlayer.shared.prepare()
        }
    }

    private func handleFightResult(_ json: String) {
        if let sentAt = configSentAt {
            let ms = Date().timeIntervalSince(sentAt) * 1000.0
            roundTripMs = ms
            spikeLog.info("fight_config to fight_result round trip \(ms, privacy: .public) ms")
        }
        rearmRetry?.cancel()
        rearmRetry = nil
        resultJSON = prettyPrinted(json)
        sampleMemory(into: \.memoryLatestMB)

        if let parsed = FightResult(json: json) {
            lastResult = parsed
            // The arena also sends fight_state result, but the sheet must appear even if it does not.
            fightState = .result
            spikeLog.info("result \(parsed.outcome.type, privacy: .public), winner \(parsed.outcome.winner, privacy: .public), \(parsed.durationSeconds, privacy: .public) s")
        } else {
            errorText = "The result did not parse as JSON."
            spikeLog.error("fight_result did not parse")
        }

        // Prove the payload survived the crossing, per the spec's diagnostics.echo. Only the spike
        // fixture is checked against the Stage 1 numbers.
        guard expectSpikeEcho else { return }
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

    // MARK: Stage 6 message handlers (agent S6)

    /// `event_result` {mode, score, cleared, time_s, details}. A side event never sends judges,
    /// scrap or a winner, so it is not a `FightResult` and is not put in `lastResult`.
    private func handleEventResult(_ json: String) {
        rearmRetry?.cancel()
        rearmRetry = nil
        eventResultJSON = prettyPrinted(json)
        sampleMemory(into: \.memoryLatestMB)
        guard let parsed = EventResult(json: json) else {
            errorText = "The event result did not parse as JSON."
            spikeLog.error("event_result did not parse")
            return
        }
        lastEventResult = parsed
        fightState = .result
        spikeLog.info("event_result \(parsed.mode, privacy: .public), score \(parsed.score, privacy: .public), cleared \(parsed.cleared, privacy: .public), \(parsed.timeSeconds, privacy: .public) s")
    }

    /// `replay_state` {tick, total, finished}, every ten ticks while a recording plays.
    private func handleReplayState(_ json: String) {
        guard let root = JSONValue.parse(json) else { return }
        var state = ReplayState()
        state.tick = root["tick"]?.intValue ?? 0
        state.total = root["total"]?.intValue ?? replayState?.total ?? 0
        state.finished = root["finished"]?.boolValue ?? false
        replayState = state
        if state.finished { replayIsPlaying = false }
    }

    /// `workshop_ready` carries the arena's own `build_summary()`. Key names are read loosely so a
    /// GDScript rename does not blank the panel: total weight, front lip clearance and the height
    /// of the centre of mass, plus whatever per category weights the arena chose to send.
    private func handleWorkshopReady(_ json: String) {
        guard let root = JSONValue.parse(json) else { return }
        var summary = WorkshopSummary()

        func number(_ keys: [String], in value: JSONValue?) -> Double? {
            for key in keys {
                if let found = value?[key]?.doubleValue { return found }
            }
            return nil
        }

        summary.totalKg = number(["total_kg", "total", "total_weight", "weight_total", "mass_kg"], in: root)
        summary.clearanceM = number(["clearance", "clearance_m", "front_clearance", "clearance_front"], in: root)
        summary.comHeightM = number(["com_height", "com_height_m", "centre_of_mass_height", "center_of_mass_height"], in: root)

        // Per category weights: either a nested object, or loose keys alongside the totals.
        let nested = root["weights"] ?? root["categories"] ?? root["per_category"]
        if let nested {
            for member in nested.members {
                guard let value = member.value.doubleValue else { continue }
                summary.categories.append(member.key)
                summary.categoryWeights[member.key] = value
            }
        }

        workshopSummary = summary
        spikeLog.info("workshop_ready total \(summary.totalKg ?? -1, privacy: .public) kg, clearance \(summary.clearanceM ?? -1, privacy: .public) m")
    }

    /// `pause_requested` {} : the pad asked for the pause menu. Nothing but a nudge to the shell,
    /// which puts its own overlay up and sends `fight_control` pause back.
    private func handlePauseRequested() {
        guard fightIsOnScreen else { return }
        pauseRequests &+= 1
    }

    private func handleHaptic(_ json: String) {
        guard let object = jsonObject(json), let kind = object["kind"] as? String else { return }
        HapticsPlayer.shared.play(kind: kind)
    }

    private func handleArenaLog(_ json: String) {
        ArenaFileLog.append(json)
        guard let object = jsonObject(json) else { return }
        let level = object["level"] as? String ?? "info"
        let text = object["text"] as? String ?? ""
        spikeLog.info("arena_log \(level, privacy: .public): \(text, privacy: .public)")
        if level == "error" { errorText = text }
    }

    // MARK: - Sending

    /// The one shape this shell sends. Two keys, exactly as the spec says.
    func send(type: String, json: String) {
        guard handle != nil, arenaReady else {
            errorText = "The arena is not ready yet, so nothing was sent."
            spikeLog.error("send(\(type, privacy: .public)) before arena_ready")
            return
        }
        HostBridge.send(type: type, json: json)
        spikeLog.info("sent \(type, privacy: .public), \(json.count, privacy: .public) bytes of json")
    }

    /// Hand a complete FightConfig to the arena.
    func sendFightConfig(_ json: String) {
        configSentAt = Date()
        readBotIdentities(from: json)
        // Stage 6 (agent S6): the log keeps the configuration a fight was fought with, because a
        // replay is that configuration with the recorded inputs attached.
        lastFightConfigJSON = json
        var out = coachNextFight ? Self.injectingCoach(into: json) : json
        if let intro = introNextFight { out = Self.injectingIntro(intro, into: out) }
        send(type: "fight_config", json: out)
    }

    /// The arena intro for the next `fight_config`: "full", "short" or "none" (`IntroPolicy`), or nil
    /// to send no key, which the arena reads as none. Set by `IntroPolicy.arm` for a fight and a career
    /// match; cleared by a replay and an event. Like the coach flag it never reaches
    /// `lastFightConfigJSON`, so a replay of the fight carries no intro (the arena also refuses one).
    var introNextFight: String?

    static func injectingIntro(_ intro: String, into json: String) -> String {
        guard let data = json.data(using: .utf8),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return json }
        object["intro"] = intro
        return JSONText.string(from: object)
    }

    /// When true the next `fight_config` carries `"coach": true`, which asks the arena's HUD to show
    /// the how-to-play callouts (drive, weapon, camera) over the countdown and the opening seconds.
    /// The shell sets it for a player's first few fights and for the test arena; the stored
    /// `lastFightConfigJSON` never carries it, so replays are unaffected.
    var coachNextFight = false

    static func injectingCoach(into json: String) -> String {
        guard let data = json.data(using: .utf8),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return json }
        object["coach"] = true
        return JSONText.string(from: object)
    }

    /// The Stage 1 spike configuration, sent by the bridge spike screen.
    func sendSpikeConfig() {
        errorText = nil
        resultJSON = ""
        roundTripMs = nil
        expectSpikeEcho = true
        sendFightConfig(FightConfigFixture.json)
    }

    /// Start a fight or the test arena with the player's own build. Safe to call before the arena
    /// is ready: the configuration waits for `arena_ready` and goes out the moment it lands.
    func startFight(
        player: [String: Any],
        mode: FightMode,
        safeArea: SafeAreaPixels,
        arena: String = "yard",
        opponents: [[String: Any]]? = nil,
        rumble: Bool = false,
        houseBot: (id: String, speed: Double)? = nil,
        seed: Int = 123456789
    ) {
        let opponentAI = Self.opponentAI
        let json = FightConfigFixture.fightJson(
            player: player,
            safeArea: safeArea,
            opponentAI: opponentAI,
            mode: mode,
            arena: arena,
            opponents: opponents,
            rumble: rumble,
            houseBot: houseBot,
            seed: seed
        )
        surface = .fight
        fightMode = mode
        // A fight configuration replaces whatever was on the stage, so a stale workshop send must
        // not arrive after it and pull the arena back to the turntable.
        workshopDebounce?.cancel()
        workshopDebounce = nil
        pendingWorkshopJSON = nil
        sentSafeArea = safeArea
        lastResult = nil
        resultJSON = ""
        roundTripMs = nil
        errorText = nil
        expectSpikeEcho = false
        didRetryThisFight = false
        fightState = .loading
        // Every round starts in the open phase, whatever the last one ended in.
        fightPhase = "open"
        pendingConfigJSON = json
        HapticsPlayer.shared.prepare()
        spikeLog.info("starting a \(mode == .test ? "test" : "fight", privacy: .public), opponent ai \(opponentAI, privacy: .public), safe area \(safeArea.left, privacy: .public)/\(safeArea.top, privacy: .public)/\(safeArea.right, privacy: .public)/\(safeArea.bottom, privacy: .public) px")
        deliverPendingConfig()
    }

    private func deliverPendingConfig() {
        guard let json = pendingConfigJSON, arenaReady, handle != nil else { return }
        pendingConfigJSON = nil
        sendFightConfig(json)
        scheduleRearmRetry(json)
    }

    // MARK: - The stage and the test arena

    /// Put the player's own bot on the lit stage behind the menus. The arena switches back to the
    /// turntable when it receives `workshop_config` (docs/stage4-spec.md section 5).
    ///
    /// Stage 5 adds `mode`: the scouting report sends `"scout"`, which asks the arena to orbit the
    /// machine in the payload instead of standing the player's own on the turntable
    /// (docs/stage5-spec.md section 2). No mode at all is the Stage 4 behaviour.
    /// `frame` is where the stage centre should land across the screen, 0 (left edge) to 1 (right
    /// edge); nil means the arena's default of 0.5. Screens that put their panels on the right pass
    /// about 0.3 so the machine stands in the clear left of the picture instead of behind the glass.
    func sendWorkshopConfig(_ botConfig: [String: Any], mode: String? = nil, frame: Double? = nil) {
        var payload: [String: Any] = ["bot": botConfig]
        if let mode { payload["mode"] = mode }
        if let frame { payload["frame"] = min(1, max(0, frame)) }
        let json = JSONText.string(from: payload)
        scoutingOpponent = (mode == "scout")
        guard json != lastWorkshopJSON else { return }
        lastWorkshopJSON = json
        surface = .stage
        guard arenaReady, handle != nil else {
            pendingWorkshopJSON = json
            return
        }
        send(type: "workshop_config", json: json)
    }

    /// Start a career tie: the chosen machine against a real opponent, in the tier's arena. The
    /// configuration is built by the career (`CareerFightConfig`) because only the career knows
    /// which arena and which opponent; everything else is exactly `startFight`.
    func startCareerFight(configJSON: String) {
        surface = .fight
        fightMode = .fight
        scoutingOpponent = false
        workshopDebounce?.cancel()
        workshopDebounce = nil
        pendingWorkshopJSON = nil
        lastWorkshopJSON = nil
        lastResult = nil
        resultJSON = ""
        roundTripMs = nil
        errorText = nil
        expectSpikeEcho = false
        didRetryThisFight = false
        fightState = .loading
        // Every round starts in the open phase, whatever the last one ended in.
        fightPhase = "open"
        pendingConfigJSON = configJSON
        HapticsPlayer.shared.prepare()
        spikeLog.info("starting a career fight, \(configJSON.count, privacy: .public) bytes of config")
        deliverPendingConfig()
    }

    // MARK: - Stage 6: side events and replays (agent S6)

    /// Start one of the five side events. Exactly the same shape as a fight: one `fight_config`,
    /// no chatter after it, and one `event_result` back. The only differences are `rules.mode`,
    /// the arena id (which equals the mode id) and that a second bot is only sent for the two
    /// modes that have an opponent.
    func startEvent(
        mode: EventMode,
        build: [String: Any],
        opponent: [String: Any]? = nil,
        clockSeconds: Int = 90,
        seed: Int = Int.random(in: 1...9_999_999),
        safeArea: SafeAreaPixels = .zero
    ) {
        let json = EventFightConfig.json(
            mode: mode,
            player: build,
            opponent: opponent,
            clockSeconds: clockSeconds,
            seed: seed,
            safeArea: safeArea
        )
        introNextFight = nil
        beginArenaRun(json)
        sentSafeArea = safeArea
        lastEventResult = nil
        eventResultJSON = ""
        replayState = nil
        spikeLog.info("starting event \(mode.rawValue, privacy: .public), \(clockSeconds, privacy: .public) s, seed \(seed, privacy: .public)")
        deliverPendingConfig()
    }

    /// Play a recording back. The configuration is the original fight with a `replay` block on it,
    /// so the arena rebuilds the same world from the same seed and drives the player's machine
    /// from the log instead of from the sticks.
    func startReplay(configJSON: String) {
        introNextFight = nil
        beginArenaRun(configJSON)
        replayState = ReplayState()
        replayIsPlaying = true
        replaySpeed = 1.0
        lastEventResult = nil
        spikeLog.info("starting a replay, \(configJSON.count, privacy: .public) bytes of config")
        deliverPendingConfig()
    }

    /// Leaving the replay screen. The arena is told to stop so a paused replay is not left
    /// running behind the menus.
    func stopReplay() {
        guard replayState != nil else { return }
        replayState = nil
        replayIsPlaying = false
        sendReplayControl(action: "pause")
    }

    func setReplayPlaying(_ playing: Bool) {
        replayIsPlaying = playing
        sendReplayControl(action: playing ? "play" : "pause")
    }

    func setReplaySpeed(_ speed: Double) {
        replaySpeed = speed
        sendReplayControl(action: "speed", value: speed)
    }

    func restartReplay() {
        replayIsPlaying = true
        replayState = ReplayState(tick: 0, total: replayState?.total ?? 0, finished: false)
        sendReplayControl(action: "restart")
    }

    /// Scrubbing. Sent once, on release, because seeking backwards makes the arena re-simulate
    /// from the start and that is not something to do sixty times a second.
    func seekReplay(to tick: Int) {
        replayState = ReplayState(tick: tick, total: replayState?.total ?? 0, finished: false)
        sendReplayControl(action: "seek", value: Double(tick))
    }

    /// `replay_control` {action, value}. The one message the replay bar sends.
    func sendReplayControl(action: String, value: Double? = nil) {
        var payload: [String: Any] = ["action": action]
        if let value { payload["value"] = value }
        send(type: "replay_control", json: JSONText.string(from: payload))
    }

    /// Everything `startFight`, `startCareerFight`, `startEvent` and `startReplay` have in common:
    /// the arena takes the screen, the stage sends are dropped and the fight state is reset.
    private func beginArenaRun(_ json: String) {
        surface = .fight
        fightMode = .fight
        scoutingOpponent = false
        workshopDebounce?.cancel()
        workshopDebounce = nil
        pendingWorkshopJSON = nil
        lastWorkshopJSON = nil
        lastResult = nil
        resultJSON = ""
        roundTripMs = nil
        errorText = nil
        expectSpikeEcho = false
        didRetryThisFight = false
        fightState = .loading
        // Every round starts in the open phase, whatever the last one ended in.
        fightPhase = "open"
        pendingConfigJSON = json
        HapticsPlayer.shared.prepare()
    }

    /// The builder calls this on every edit. One send per 150 ms of quiet, so dragging a stepper
    /// does not flood the bridge (docs/stage4-spec.md section 7).
    func sendWorkshopConfigDebounced(_ botConfig: [String: Any], after seconds: TimeInterval = 0.15) {
        workshopDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.sendWorkshopConfig(botConfig)
        }
        workshopDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// `fight_control` {action}: "pause" freezes the fixed tick, "resume" starts it again, "quit"
    /// gives the fight up and takes the arena's existing abandoned path, which comes back as
    /// `fight_state` abandoned. The shell is the authority on all three; the arena only ever asks.
    func sendFightControl(_ action: String) {
        send(type: "fight_control", json: JSONText.string(from: ["action": action]))
    }

    /// The turntable, as the player's fingers move it (brief section 11: "full turntable orbit,
    /// free zoom and tilt"). `StageOrbitPad` in the clear left of every stage screen sends the
    /// gesture here in screen points: `orbit` is +x right and +y down, `pinch` is the incremental
    /// factor since the last call, above 1 for zooming in. The arena reads `stage_camera` and moves
    /// its workshop and menu rig; nothing else in the shell knows where the camera is.
    ///
    /// Deltas are summed and sent at most once every 16 ms, because a drag produces a touch event
    /// per frame per finger and the bridge does not need three of them.
    func sendStageCamera(orbit: CGSize? = nil, pinch: Double? = nil) {
        guard surface == .stage else { return }
        if let orbit {
            stageCameraOrbit.width += orbit.width
            stageCameraOrbit.height += orbit.height
        }
        if let pinch, pinch > 0 {
            stageCameraPinch *= pinch
        }
        guard stageCameraFlush == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.stageCameraFlush = nil
            let dx = Double(self.stageCameraOrbit.width)
            let dy = Double(self.stageCameraOrbit.height)
            let factor = self.stageCameraPinch
            self.stageCameraOrbit = .zero
            self.stageCameraPinch = 1
            guard self.surface == .stage, self.arenaReady, self.handle != nil else { return }
            var payload: [String: Any] = [:]
            if dx != 0 || dy != 0 { payload["orbit"] = [dx, dy] }
            if abs(factor - 1) > 0.0001 { payload["pinch"] = factor }
            guard !payload.isEmpty else { return }
            self.send(type: "stage_camera", json: JSONText.string(from: payload))
        }
        stageCameraFlush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: work)
    }

    /// Re place and repair both bots in the test arena. The arena owns what that means.
    func sendTestReset() {
        send(type: "test_reset", json: "{}")
    }

    /// The whole settings dictionary, every time: after `arena_ready` and on every change. The
    /// arena never has to merge a partial update. A change made before the arena is up waits.
    func sendSettings(_ settings: [String: Any]) {
        let json = JSONText.string(from: settings)
        guard arenaReady, handle != nil else {
            pendingSettingsJSON = json
            return
        }
        pendingSettingsJSON = nil
        send(type: "settings", json: json)
    }

    private func deliverPendingSettings() {
        guard let json = pendingSettingsJSON, arenaReady, handle != nil else { return }
        pendingSettingsJSON = nil
        send(type: "settings", json: json)
    }

    private func deliverPendingWorkshop() {
        guard let json = pendingWorkshopJSON, arenaReady, handle != nil else { return }
        pendingWorkshopJSON = nil
        send(type: "workshop_config", json: json)
    }

    /// Leaving a fight for the menus: the stage comes back and the bot on it is re sent, because
    /// the arena has been showing the fight since the last `fight_config`.
    func showStage(bot: [String: Any]?) {
        surface = .stage
        scoutingOpponent = false
        lastWorkshopJSON = nil
        workshopSummary = nil
        // Stage 6 (agent S6): a replay or an event is over the moment the stage comes back.
        replayState = nil
        lastEventResult = nil
        rearmRetry?.cancel()
        rearmRetry = nil
        pendingConfigJSON = nil
        HapticsPlayer.shared.relax()
        app.resume()
        app.startDrawing()
        if let bot {
            sendWorkshopConfig(bot)
        }
    }

    /// The arena is meant to accept a new `fight_config` after a result and re arm itself. If the
    /// second fight never leaves LOADING, send the configuration once more before giving up, and
    /// say so in the log so the failure is visible rather than silent.
    private func scheduleRearmRetry(_ json: String) {
        rearmRetry?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.fightState == .loading, self.lastResult == nil else { return }
            guard !self.didRetryThisFight else {
                self.errorText = "The arena did not start the fight. Go back and try again."
                spikeLog.error("the arena never left LOADING after two fight_config sends")
                return
            }
            self.didRetryThisFight = true
            spikeLog.warning("no fight_state within 3 s, sending fight_config once more")
            self.sendFightConfig(json)
            self.scheduleRearmRetry(json)
        }
        rearmRetry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    /// Names and order for the result sheet, read from the configuration that was sent rather
    /// than hardcoded, so the sheet stays right when the fixture changes.
    private func readBotIdentities(from json: String) {
        guard let object = jsonObject(json), let bots = object["bots"] as? [[String: Any]] else { return }
        var names: [String: String] = [:]
        var order: [String] = []
        for bot in bots {
            guard let id = bot["id"] as? String else { continue }
            order.append(id)
            names[id] = bot["name"] as? String ?? id
        }
        botNames = names
        botOrder = order
    }

    /// The name to print for a bot id, falling back to the id itself.
    func name(for id: String) -> String {
        if id.isEmpty { return "Nobody" }
        return botNames[id] ?? id
    }

    // MARK: - Arena screen lifecycle

    /// The fight screen appeared. The GodotApp is never recreated, only woken.
    func arenaScreenAppeared() {
        fightIsOnScreen = true
        surface = .fight
        app.resume()
        app.startDrawing()
    }

    /// Back to the garage. Since Stage 4 the menus sit in front of the same live view, so the
    /// engine keeps drawing the stage rather than sleeping. It only sleeps on backgrounding.
    func arenaScreenLeft() {
        fightIsOnScreen = false
        rearmRetry?.cancel()
        rearmRetry = nil
        pendingConfigJSON = nil
        HapticsPlayer.shared.relax()
    }

    /// True only while there is nothing live to show: before `arena_ready`, on every platform, or
    /// in a run that was explicitly launched with a headless or dummy renderer. There is no
    /// simulator special case any more: the simulator renders through OpenGL ES 3
    /// (docs/simulator-rendering.md), so once the arena says it is ready the live surface shows.
    var showsStill: Bool {
        surface == .stage && (!arenaReady || !rendersLive)
    }

    // MARK: - Memory

    func sampleMemoryNow() {
        sampleMemory(into: \.memoryLatestMB)
    }

    private func sampleMemory(into keyPath: ReferenceWritableKeyPath<ArenaHost, Double?>) {
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
            spikeLog.info("scene phase active")
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


/// Diagnostic file log of every `arena_log` line, readable off a device with
/// `devicectl device copy from --domain-type appDataContainer` (Documents/arena-log.txt).
/// Capped so it can never grow past about a megabyte.
enum ArenaFileLog {
    private static let url: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("arena-log.txt")
    }()
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let queue = DispatchQueue(label: "roboteer.arena-file-log")

    static func append(_ line: String) {
        let stamped = "\(formatter.string(from: Date())) \(line)\n"
        queue.async {
            guard let data = stamped.data(using: .utf8) else { return }
            let fm = FileManager.default
            if let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue, size > 1_000_000 {
                try? fm.removeItem(at: url)
            }
            if !fm.fileExists(atPath: url.path) {
                fm.createFile(atPath: url.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        }
    }
}
