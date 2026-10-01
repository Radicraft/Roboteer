//
//  ReplaysView.swift
//  REPLAYS. Every fight the arena recorded, listed newest first, and the way into the player.
//
//  A replay is not a video. The arena kept the player's inputs and the seed, so watching one
//  re-simulates the fight in a fresh world at whatever speed you ask for, with a free camera.
//  That is why a clip is worth sharing: it is the fight, shot again.
//
//  Behind the wall (`Gates.replaysAvailable`), and sharing a clip is behind it too
//  (`Gates.sharingAvailable`).
//

import SwiftUI
import SwiftData

// MARK: - Reading the recording out of a fight

/// The `replay` block of a result, and the configuration that reproduces it.
enum ReplayPayload {

    /// The `replay` value of a `fight_result` or `event_result`, as text, or "" when there was
    /// none. `CareerStore` writes this into `FightLog.replayJSON` for every career fight.
    static func block(from resultJSON: String) -> String {
        guard let data = resultJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let replay = root["replay"],
              let out = try? JSONSerialization.data(withJSONObject: replay, options: []),
              let text = String(data: out, encoding: .utf8) else { return "" }
        return text
    }

    /// The replay block as the arena wants it back: always an object with `inputs`. A recorder
    /// that sent a bare array of inputs is wrapped, so both shapes replay.
    static func inputsObject(from replayJSON: String) -> [String: Any]? {
        guard !replayJSON.isEmpty, let data = replayJSON.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let object = any as? [String: Any] {
            guard object["inputs"] != nil else { return nil }
            return object
        }
        if let array = any as? [Any], !array.isEmpty {
            return ["inputs": array]
        }
        return nil
    }

    /// How many ticks the recording holds, when it says so. Presentation only: the arena is the
    /// authority and sends `replay_state` with its own total.
    static func tickCount(from replayJSON: String) -> Int? {
        guard let object = inputsObject(from: replayJSON),
              let inputs = object["inputs"] as? [Any] else { return nil }
        return inputs.count
    }

    /// The original `fight_config` with the recording attached and this run's safe area on it.
    /// Returns nil when the log has no configuration (every fight logged before Stage 6) or no
    /// inputs, which is exactly when the row's Watch button is disabled.
    static func config(from log: FightLog, safeArea: SafeAreaPixels) -> String? {
        guard let data = log.configJSON.data(using: .utf8),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let replay = inputsObject(from: log.replayJSON) else { return nil }

        root["replay"] = replay
        var presentation = root["presentation"] as? [String: Any] ?? [:]
        presentation["safe_area_px"] = [
            "left": safeArea.left,
            "top": safeArea.top,
            "right": safeArea.right,
            "bottom": safeArea.bottom
        ]
        // The replay bar is the shell's, so the arena is asked for the bare view and the camera
        // it uses for a replay rather than the fight HUD.
        presentation["hud"] = false
        presentation["camera"] = "replay"
        root["presentation"] = presentation
        return JSONText.string(from: root)
    }

    /// Whether this log can be watched at all.
    static func isWatchable(_ log: FightLog) -> Bool {
        !log.configJSON.isEmpty && inputsObject(from: log.replayJSON) != nil
    }
}

// MARK: - The root

struct ReplaysRootView: View {

    @Bindable var host: ArenaHost

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \FightLog.date, order: .reverse) private var logs: [FightLog]
    @Query(sort: \BotBuild.createdAt, order: .forward) private var builds: [BotBuild]

    @State private var watching: PersistentIdentifier?

    private var watchable: [FightLog] { logs.filter { !$0.replayJSON.isEmpty } }
    private var current: FightLog? {
        guard let watching else { return nil }
        return logs.first { $0.persistentModelID == watching }
    }

    var body: some View {
        Group {
            if let current {
                ReplayPlayerView(host: host, log: current) {
                    watching = nil
                    host.stopReplay()
                    host.showStage(bot: Garage.selected(from: builds)?
                        .toBotConfig(id: FightConfigFixture.playerID, controller: "player"))
                }
            } else {
                ReplaysView(
                    host: host,
                    logs: watchable,
                    onWatch: { watching = $0.persistentModelID },
                    onBack: { dismiss() }
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - The list

struct ReplaysView: View {

    @Bindable var host: ArenaHost
    let logs: [FightLog]
    var onWatch: (FightLog) -> Void
    var onBack: () -> Void

    private var gates: Gates { Gates.current }
    private var lockedReason: String? { gates.lockedReasonIfLocked(.replays) }

    var body: some View {
        ZStack {
            StageBackdrop(host: host, still: .withBot, dim: 0.26)
            StageScrim()

            // Bug 13: the machine stands in the left 45 %, so the list keeps to the stage column
            // (`StageLayout.columnWidth`) and nothing boxed crosses the machine.
            GeometryReader { proxy in
                HStack(alignment: .top, spacing: 22) {
                    left
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    list
                        .frame(width: StageLayout.columnWidth(proxy.size.width), alignment: .topLeading)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 20)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { registerFocus() }
    }

    private func registerFocus() {
        var items: [PadItem] = logs.prefix(8).map { log in
            PadItem("replay-\(log.persistentModelID.hashValue)", enabled: lockedReason == nil && ReplayPayload.isWatchable(log)) {
                onWatch(log)
            }
        }
        items.append(PadItem("back") { onBack() })
        PadFocus.shared.set(items, back: { onBack() })
    }

    private var left: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ARCHIVE")
                .font(Stage.label(12, weight: .bold))
                .kerning(2)
                .foregroundStyle(Stage.textFaint)

            Text("REPLAYS")
                .font(Stage.display(40, weight: .black))
                .kerning(1.4)
                .foregroundStyle(Stage.text)
                .shadow(color: .black.opacity(0.6), radius: 10, y: 2)


            // On a plate: loose over the stage this ran across the machine (integration,
            // 2026-09-28).
            Text("Every fight is kept as the inputs that made it, so a replay is the fight run again. Slow it down, move the camera, keep the clip.")
                .font(Stage.body(13))
                .foregroundStyle(Stage.type)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .blueprintPlate()

            Spacer(minLength: 0)

            StageButton("Back", kind: .glass, action: onBack)
                .frame(width: 160)
            PadHintBar(showsBack: true)
        }
        .frame(maxWidth: 300, alignment: .leading)
    }

    private var list: some View {
        LockedPanel(reason: lockedReason) {
            Group {
                if logs.isEmpty {
                    GlassPanel(padding: 14) {
                        Text("Nothing recorded yet. Fight a career match and it will be here afterwards.")
                            .font(Stage.body(13))
                            .foregroundStyle(Stage.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(logs) { log in
                                row(log)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
    }

    private func row(_ log: FightLog) -> some View {
        let watchable = ReplayPayload.isWatchable(log)
        return GlassPanel(padding: 12) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(log.botName.uppercased())
                            .font(Stage.display(17))
                            .kerning(0.8)
                            .foregroundStyle(Stage.text)
                        Text("AGAINST \(log.opponentName.uppercased())")
                            .font(Stage.label(11, weight: .bold))
                            .kerning(0.9)
                            .foregroundStyle(Stage.textFaint)
                        if log.didWin {
                            Text("WON")
                                .font(Stage.label(11, weight: .bold))
                                .kerning(1.2)
                                .foregroundStyle(Stage.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Stage.win, in: PlateRect())
                        }
                    }
                    Text(summary(log))
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.textDim)
                        .lineLimit(1)
                        .minimumScaleFactor(BroadcastType.floorScale(.body, size: 13, wanted: 0.8))
                    if !watchable {
                        Text("Recorded before replays were kept, so there is nothing to watch.")
                            .font(Stage.body(13))
                            .foregroundStyle(Stage.textFaint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                StageButton("Watch", kind: .primary, enabled: lockedReason == nil && watchable) {
                    onWatch(log)
                }
                .frame(width: 130)
            }
        }
    }

    /// "13 Sep, The Grinder. Won by knockout." One line, plain.
    private func summary(_ log: FightLog) -> String {
        let arena = Catalogue.shared.arena(log.arena)?.name
            ?? EventCatalogue.shared.entry(log.arena)?.name
            ?? log.arena.capitalizedFirst
        let when = log.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        let what: String
        if log.round < 0 {
            what = log.didWin ? "Cleared." : "Not cleared."
        } else {
            what = log.line
        }
        return "\(when), \(arena). \(what)"
    }
}
