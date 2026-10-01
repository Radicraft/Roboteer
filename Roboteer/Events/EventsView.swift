//
//  EventsView.swift
//  SIDE EVENTS. The five physics challenges of brief section 10, listed with what they are, what
//  you have done at them and what clearing one hands over.
//
//  The whole screen is behind the wall (`Gates.sideEventsAvailable`), drawn the way every locked
//  thing in the game is drawn: visible, readable, greyed, with the sentence on it. Nothing is
//  hidden and nothing is offered for sale here.
//

import SwiftUI
import SwiftData

// MARK: - The root

struct EventsRootView: View {

    @Bindable var host: ArenaHost

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \BotBuild.createdAt, order: .forward) private var builds: [BotBuild]
    @Query private var states: [CareerState]
    @Query private var records: [EventRecord]

    enum Screen: Equatable {
        case list
        case fight(EventMode)
        case result(EventMode)
    }

    @State private var screen: Screen = .list
    @State private var lastResult: EventResult?
    @State private var outcome: EventStore.Outcome?
    @State private var seed = Int.random(in: 1...9_999_999)

    private var living: [BotBuild] { builds.filter { !$0.isWrittenOff } }
    private var bot: BotBuild? { Garage.selected(from: living) ?? living.first }
    private var tier: CareerTier { states.first?.tier ?? .scrapyard }

    var body: some View {
        Group {
            switch screen {
            case .list:
                EventsView(
                    host: host,
                    bot: bot,
                    records: Dictionary(records.map { ($0.mode, $0) }, uniquingKeysWith: { a, _ in a }),
                    tasterUsed: states.first?.tasterEventsUsed ?? 0,
                    onPlay: { play($0) },
                    onBack: { dismiss() }
                )
            case .fight(let mode):
                EventFightView(
                    host: host,
                    mode: mode,
                    playerConfig: playerConfig,
                    opponentConfig: mode.needsOpponent
                        ? EventFightConfig.fillerOpponent(tier: tier, seed: seed)
                        : nil,
                    clockSeconds: EventCatalogue.shared.entry(mode)?.clockSeconds ?? 90,
                    seed: seed,
                    onResult: { result, json in settle(mode, result: result, json: json) },
                    onAbandon: { screen = .list }
                )
            case .result(let mode):
                EventResultSheet(
                    mode: mode,
                    result: lastResult,
                    outcome: outcome,
                    record: records.first { $0.mode == mode.rawValue },
                    onAgain: { play(mode) },
                    onBack: { screen = .list }
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }

    private var playerConfig: [String: Any] {
        bot?.toBotConfig(id: EventFightConfig.playerID, controller: "player")
            ?? FightConfigFixture.opponent(controller: "player")
    }

    private func play(_ mode: EventMode) {
        let gates = Gates.current
        guard gates.sideEventOpen(tasterUsed: states.first?.tasterEventsUsed ?? 0) else { return }
        // Owner decision 13: the free game's taster play is spent when the event starts.
        if gates.spendsTaster(.sideEvents) {
            let state = CareerStore.state(in: context)
            state.tasterEventsUsed += 1
            try? context.save()
        }
        seed = Int.random(in: 1...9_999_999)
        lastResult = nil
        outcome = nil
        PadFocus.shared.clear()
        screen = .fight(mode)
    }

    /// One run, written into the record, the blueprint handed over if it is a first clear.
    private func settle(_ mode: EventMode, result: EventResult?, json: String) {
        lastResult = result
        if let result {
            outcome = EventStore.apply(
                result,
                mode: mode,
                botName: bot?.name ?? "Unnamed",
                resultJSON: json,
                in: context
            )
        } else {
            outcome = nil
        }
        host.showStage(bot: bot?.toBotConfig(id: EventFightConfig.playerID, controller: "player"))
        screen = .result(mode)
    }
}

// MARK: - The list

struct EventsView: View {

    @Bindable var host: ArenaHost
    let bot: BotBuild?
    let records: [String: EventRecord]
    /// Owner decision 13: side events already played on the free game's taster.
    var tasterUsed: Int = 0
    var onPlay: (EventMode) -> Void
    var onBack: () -> Void

    private var gates: Gates { Gates.current }
    private var tasterLeft: Int { max(0, gates.tasterEvents - tasterUsed) }
    /// Locked unless the full game is open or a taster play is left.
    private var lockedReason: String? {
        gates.sideEventOpen(tasterUsed: tasterUsed) ? nil : gates.lockedReasonIfLocked(.sideEvents)
    }
    private var entries: [EventCatalogue.Entry] { EventCatalogue.shared.known }
    private var canPlay: Bool { lockedReason == nil && (bot?.isValid ?? false) }

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
                    column
                        .frame(width: StageLayout.columnWidth(proxy.size.width), alignment: .topLeading)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 20)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { registerFocus() }
        .onChange(of: canPlay) { _, _ in registerFocus() }
    }

    private func registerFocus() {
        var items = entries.compactMap { entry -> PadItem? in
            guard let mode = entry.mode else { return nil }
            return PadItem(mode.rawValue, enabled: canPlay) { onPlay(mode) }
        }
        items.append(PadItem("back") { onBack() })
        PadFocus.shared.set(items, back: { onBack() })
    }

    private var left: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MODES")
                .font(Stage.label(12, weight: .bold))
                .kerning(2)
                .foregroundStyle(Stage.textFaint)

            Text("SIDE EVENTS")
                .font(Stage.display(40, weight: .black))
                .kerning(1.4)
                .foregroundStyle(Stage.text)
                .shadow(color: .black.opacity(0.6), radius: 10, y: 2)


            Text("Five machines' worth of trouble that is not a fight. Clear one and the part it pays is yours.")
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

    /// The right hand column: which machine goes in, as plain lines (it used to be a boxed panel
    /// in the left column, standing over the machine it described), then the events.
    private var column: some View {
        VStack(alignment: .leading, spacing: 10) {
            machine
            list
        }
    }

    @ViewBuilder
    private var machine: some View {
        if let bot {
            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR MACHINE: \(bot.name.uppercased())")
                    .font(Stage.label(11, weight: .bold))
                    .kerning(Stage.Tracking.label(11))
                    .foregroundStyle(Stage.typeDim)
                Text("\(BuildRules.kilograms(bot.totalWeight)). \(bot.partsLine).")
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                if !bot.isValid {
                    Text(BuildRules.errors(bot.spec).first ?? "")
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text("There is no machine in the garage to enter.")
                .font(Stage.body(13))
                .foregroundStyle(Stage.danger)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !gates.sideEventsAvailable, tasterLeft > 0 {
                Text(gates.tasterLine(.sideEvents, left: tasterLeft))
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.typeDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            lockedList
        }
    }

    private var lockedList: some View {
        LockedPanel(reason: lockedReason) {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(entries) { entry in
                        card(entry)
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func card(_ entry: EventCatalogue.Entry) -> some View {
        let mode = entry.mode
        let record = records[entry.id]
        return GlassPanel(padding: 13) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.name.uppercased())
                            .font(Stage.display(20))
                            .kerning(1)
                            .foregroundStyle(Stage.text)
                        if record?.cleared == true {
                            Text("CLEARED")
                                .font(Stage.label(11, weight: .bold))
                                .kerning(1.2)
                                .foregroundStyle(Stage.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Stage.win, in: CutRect(6))
                        }
                    }
                    Text(entry.pitch)
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.textDim)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 14) {
                        Text("\(entry.clockSeconds) SECONDS")
                            .font(Stage.label(11, weight: .bold))
                            .kerning(0.9)
                            .foregroundStyle(Stage.textFaint)
                        if let mode, let best = record?.bestLine(mode) {
                            Text(best)
                                .font(Stage.label(11, weight: .bold))
                                .kerning(0.9)
                                .foregroundStyle(Stage.text)
                        }
                        if let plays = record?.plays, plays > 0 {
                            Text("\(plays) \(plays == 1 ? "RUN" : "RUNS")")
                                .font(Stage.label(11, weight: .bold))
                                .kerning(0.9)
                                .foregroundStyle(Stage.textFaint)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(record?.cleared == true ? "REWARD TAKEN" : "FIRST CLEAR")
                        .font(Stage.label(11, weight: .bold))
                        .kerning(1)
                        .foregroundStyle(Stage.textFaint)
                    Text(entry.rewardName.uppercased())
                        .font(Stage.label(12, weight: .bold))
                        .kerning(0.6)
                        .foregroundStyle(record?.cleared == true ? Stage.textDim : Stage.gold)
                        .lineLimit(1)
                        .minimumScaleFactor(BroadcastType.floorScale(.label, size: 12, wanted: 0.7))
                    if let mode {
                        StageButton("Play", kind: .primary, enabled: canPlay, focusID: mode.rawValue) {
                            onPlay(mode)
                        }
                        .frame(width: 130)
                    }
                }
                .frame(width: 150, alignment: .trailing)
            }
        }
    }
}

// MARK: - The event itself

/// The same bare Godot view every fight screen uses, with the event's name on a capsule while it
/// starts. The event sends one `fight_config` with `rules.mode` set to the event and waits for
/// `event_result`.
struct EventFightView: View {

    @Bindable var host: ArenaHost

    let mode: EventMode
    let playerConfig: [String: Any]
    let opponentConfig: [String: Any]?
    let clockSeconds: Int
    let seed: Int

    var onResult: (EventResult?, String) -> Void
    var onAbandon: () -> Void

    @State private var didStart = false
    @State private var didFinish = false

    private var name: String {
        (EventCatalogue.shared.entry(mode)?.name ?? mode.rawValue).uppercased()
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // The arena's touches. The one Godot view is a SIBLING BELOW the navigation
                // controller's container view, and that container answers `hitTest` with itself
                // even when it is clear, so on a PUSHED fight screen no touch ever reaches the
                // engine on its own: this hands every touch the chrome above leaves alone to
                // `Input.parseInputEvent` by hand (`FightTouchForwarder`, StageSurface.swift).
                //
                // Owner's bug, 2026-09-16: a quick fight drove and a career fight did not, because
                // `FightView` had this and this screen did not. It is the FIRST child of the stack
                // so the banner and the pause overlay keep their own touches.
                FightTouchForwarder()
                    .ignoresSafeArea()
                banner
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                leaveButton
            }
            .onAppear { start(fallbackInsets: proxy.safeAreaInsets) }
        }
        .statusBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onChange(of: host.lastEventResult) { _, result in
            if result != nil { finish() }
        }
        .onChange(of: host.fightState) { _, state in
            // The arena says a run was abandoned rather than finished. Nothing is recorded.
            if state == .abandoned { leave() }
        }
    }

    private var banner: some View {
        Text(name)
            .font(Stage.display(13))
            .kerning(1.8)
            .foregroundStyle(Stage.textFaint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Stage.glassDeep, in: CutRect(8))
            .padding(.top, 12)
            .opacity(host.fightState == .countdown || host.fightState == .loading ? 1 : 0)
            .animation(.easeOut(duration: 0.35), value: host.fightState)
    }

    /// An event has no judges and no result to wait for if the player has had enough, so there is
    /// always a way out. Leaving records nothing.
    private var leaveButton: some View {
        VStack {
            HStack {
                StageButton("Leave", kind: .glass) { leave() }
                    .frame(width: 108)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private func start(fallbackInsets: EdgeInsets) {
        guard !didStart else { return }
        didStart = true
        PadFocus.shared.clear()
        host.arenaScreenAppeared()
        DispatchQueue.main.async {
            host.startEvent(
                mode: mode,
                build: playerConfig,
                opponent: opponentConfig,
                clockSeconds: clockSeconds,
                seed: seed,
                safeArea: SafeAreaPixels.current(fallback: fallbackInsets)
            )
        }
    }

    private func finish() {
        guard !didFinish, let result = host.lastEventResult else { return }
        didFinish = true
        host.arenaScreenLeft()
        onResult(result, host.eventResultJSON)
    }

    private func leave() {
        guard !didFinish else { return }
        didFinish = true
        host.arenaScreenLeft()
        onAbandon()
    }
}

// MARK: - The result

/// What the run scored, and the blueprint if this was the first clear. No purse, no repair bill
/// and no judges: an event is not a fight.
struct EventResultSheet: View {

    let mode: EventMode
    let result: EventResult?
    let outcome: EventStore.Outcome?
    let record: EventRecord?

    var onAgain: () -> Void
    var onBack: () -> Void

    private var entry: EventCatalogue.Entry? { EventCatalogue.shared.entry(mode) }

    var body: some View {
        ZStack {
            Stage.ground.ignoresSafeArea()
            StageStill(kind: .empty)
                .opacity(0.3)
                .ignoresSafeArea()
            Stage.ink.opacity(0.62).ignoresSafeArea()

            HStack(alignment: .top, spacing: 22) {
                left
                Spacer(minLength: 8)
                buttons
            }
            .padding(.horizontal, 32)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { registerFocus() }
    }

    private func registerFocus() {
        PadFocus.shared.set(
            [PadItem("again") { onAgain() }, PadItem("back") { onBack() }],
            back: { onBack() }
        )
    }

    private var left: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text((entry?.name ?? mode.rawValue).uppercased())
                .font(Stage.label(12, weight: .bold))
                .kerning(2)
                .foregroundStyle(Stage.textFaint)

            Text(headline)
                .font(Stage.display(38, weight: .black))
                .kerning(1.4)
                .foregroundStyle(Stage.text)


            GlassPanel(padding: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    if let result {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(result.score)")
                                .font(Stage.numerals(34))
                                .figureLine(34)
                                .foregroundStyle(outcome?.isNewBest == true ? Stage.gold : Stage.text)
                            Text(mode.scoreWord.uppercased())
                                .font(Stage.label(11, weight: .bold))
                                .kerning(1.2)
                                .foregroundStyle(Stage.textFaint)
                            if outcome?.isNewBest == true {
                                Text("NEW BEST")
                                    .font(Stage.label(11, weight: .bold))
                                    .kerning(1.2)
                                    .foregroundStyle(Stage.ink)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Stage.win, in: CutRect(6))
                            }
                        }
                        StageStat(label: "Time", value: result.timeLine)
                        StageStat(label: "Cleared", value: result.cleared ? "yes" : "no")
                        ForEach(result.details.keys.sorted(), id: \.self) { key in
                            StageStat(label: key.replacingOccurrences(of: "_", with: " ").capitalizedFirst,
                                      value: result.details[key] ?? "")
                        }
                        if let record {
                            HairRule()
                            StageStat(label: "Best", value: record.bestLine(mode) ?? "none yet")
                            StageStat(label: "Runs", value: "\(record.plays)")
                        }
                    } else {
                        Text("The arena finished the event but sent nothing this build could read.")
                            .font(Stage.label(13))
                            .foregroundStyle(Stage.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: 460, alignment: .leading)
            }

            if let part = outcome?.newBlueprint {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Stage.gold)
                    Text("New part: \(CareerEngine.partName(part))")
                        .font(Stage.label(15, weight: .bold))
                        .foregroundStyle(Stage.gold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Stage.panelDeep, in: CutRect(Stage.corner))
                .transition(.opacity)
            } else if outcome?.firstClear == true {
                Text("Cleared. You already own the \(entry?.rewardName ?? "part").")
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.textDim)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private var headline: String {
        guard let result else { return "EVENT OVER" }
        if result.cleared { return outcome?.firstClear == true ? "FIRST CLEAR" : "CLEARED" }
        return "RUN OVER"
    }

    private var buttons: some View {
        VStack(alignment: .trailing, spacing: 10) {
            StageButton("Run it again", kind: .primary, focusID: "again", action: onAgain)
            StageButton("Back to events", focusID: "back", action: onBack)
            Spacer(minLength: 0)
        }
        .frame(width: 250)
    }
}
