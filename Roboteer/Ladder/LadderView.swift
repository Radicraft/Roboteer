//
//  LadderView.swift
//  LADDER. Other players' machines, driven by the arena's AI, brief section 10.
//
//  Nothing on this screen is real time and nothing on it waits for the network. The list is
//  whatever the service has: real machines when CloudKit answered, eight generated ghosts when it
//  did not, and the only sign of the difference is a quiet "Offline ladder" label. There is no
//  error state, because an offline ladder is not an error, it is the ladder.
//
//  The fight itself is an ordinary career style tie: the same `CareerFightView`, the same
//  `fight_config`, the ghost as `controller: "ai"` with `debug.opponent_ai: "normal"`, in the
//  arena the player's own tier fights in.
//

import SwiftUI
import SwiftData

struct LadderView: View {

    @Bindable var host: ArenaHost

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var states: [CareerState]
    @Query(sort: \BotBuild.createdAt, order: .forward) private var builds: [BotBuild]

    private enum Screen {
        case list
        case fight
        case result
    }

    /// Everything one ladder fight needs while the arena is busy with it.
    private struct Pending {
        let ghost: LadderService.Ghost
        let botID: PersistentIdentifier
        let botName: String
        let arena: String
        let seed: Int
        let playerConfig: [String: Any]
        let opponentConfig: [String: Any]
    }

    /// What the result panel prints.
    private struct Settled {
        let ghost: LadderService.Ghost
        let won: Bool
        let delta: Int
        let rating: Int
        let outcome: String
    }

    @State private var screen: Screen = .list
    @State private var pending: Pending?
    @State private var settled: Settled?
    @State private var didAppear = false

    private var ladder: LadderService { LadderService.shared }
    private var gameCenter: GameCenterService { GameCenterService.shared }
    private var gates: Gates { Gates.current }
    /// Owner decision 13: a free game may fight `progression.taster.ladder_fights` ladder fights.
    private var tasterUsed: Int { states.first?.tasterLadderUsed ?? 0 }
    private var tasterLeft: Int { max(0, gates.tasterLadderFights - tasterUsed) }
    /// A fight may be fought: the full game, or a taster fight left.
    private var fightOpen: Bool { gates.ladderFightOpen(tasterUsed: tasterUsed) }

    private var state: CareerState? { states.first }
    private var tier: CareerTier { state?.tier ?? .scrapyard }
    private var living: [BotBuild] { builds.filter { !$0.isWrittenOff } }
    private var selected: BotBuild? { Garage.selected(from: living) }

    var body: some View {
        Group {
            switch screen {
            case .list:
                listScreen
            case .fight:
                if let pending {
                    CareerFightView(
                        host: host,
                        playerConfig: pending.playerConfig,
                        opponentConfig: pending.opponentConfig,
                        arena: pending.arena,
                        seed: pending.seed
                    ) { result, json in
                        settle(result: result, json: json)
                    }
                } else {
                    listScreen
                }
            case .result:
                resultScreen
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear { appear() }
    }

    // MARK: - The list

    private var listScreen: some View {
        ZStack {
            StageBackdrop(host: host, still: .empty, dim: 0.42)
            StageScrim()

            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    if !gates.ladderAvailable, tasterLeft > 0 {
                        Text(gates.tasterLine(.ladder, left: tasterLeft))
                            .font(Stage.body(13))
                            .foregroundStyle(Stage.typeDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !fightOpen, let reason = gates.lockedReasonIfLocked(.ladder) {
                        LockedPanel(reason: reason) { opponentList }
                    } else {
                        opponentList
                    }
                }
                Spacer(minLength: 6)
                buttons
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { registerFocus() }
        .onChange(of: ladder.opponents) { _, _ in registerFocus() }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LADDER")
                    .font(Stage.display(34, weight: .black))
                    .kerning(1.6)
                    .foregroundStyle(Stage.text)
                    .shadow(color: .black.opacity(0.6), radius: 10, y: 2)
                Text(subtitle)
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.textFaint)
                    // Bug 12: at the 13 pt floor the line wraps rather than shrinking.
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(ladder.rating)")
                    .font(Stage.numerals(30))
                    .foregroundStyle(Stage.text)
                Text("RATING")
                    .font(Stage.label(11, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(Stage.textFaint)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(ladder.wins) - \(ladder.losses)")
                    .font(Stage.numerals(22))
                    .foregroundStyle(Stage.textDim)
                Text("RECORD")
                    .font(Stage.label(11, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(Stage.textFaint)
            }
        }
    }

    /// One line under the title: who the player is here, and whether the list is real.
    private var subtitle: String {
        var parts: [String] = [gameCenter.displayName]
        parts.append(ladder.isOffline ? "Offline ladder" : ladder.statusLine.replacingOccurrences(of: ".", with: ""))
        if let selected, !ladder.isPublished(selected) {
            parts.append("\(selected.name) is not published yet")
        }
        return parts.joined(separator: ". ") + "."
    }

    private var opponentList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(Array(ladder.opponents.enumerated()), id: \.element.id) { index, ghost in
                    ghostRow(ghost, index: index)
                }
                if ladder.opponents.isEmpty {
                    GlassPanel(padding: 14) {
                        Text(ladder.isBusy ? "Looking for machines near your rating." : "No machines yet. Press Refresh.")
                            .font(Stage.label(13))
                            .foregroundStyle(Stage.textDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func ghostRow(_ ghost: LadderService.Ghost, index: Int) -> some View {
        GlassPanel(padding: 12) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        LiverySwatch(hex: ghost.spec.liveryHex, size: 11)
                        // One line, always: "IRON SPRAT" wrapped at 402 pt (integration,
                        // 2026-09-28). The roboteer's name gives way first.
                        Text(ghost.spec.name.uppercased())
                            .font(Stage.display(16))
                            .kerning(0.8)
                            .foregroundStyle(Stage.text)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                        Text(ghost.displayName)
                            .font(Stage.body(13))
                            .foregroundStyle(Stage.textFaint)
                            .lineLimit(1)
                    }
                    Text("\(ghost.spec.partsLine). \(BuildRules.kilograms(BuildRules.totalWeight(ghost.spec))).")
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.textDim)
                        .lineLimit(1)
                        .minimumScaleFactor(BroadcastType.floorScale(.body, size: 13, wanted: 0.75))

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            if let weapon = Catalogue.shared.weapon(ghost.spec.weapon) {
                                StatPips(label: "Hit", filled: weapon.hitPips, width: 40)
                                StatPips(label: "Reach", filled: weapon.reachPips, width: 40)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            if let drive = Catalogue.shared.drive(ghost.spec.drive) {
                                StatPips(label: "Speed", filled: drive.speedPips, width: 40)
                                StatPips(label: "Push", filled: drive.pushPips, width: 40)
                            }
                        }
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(ghost.rating)")
                        .font(Stage.numerals(19))
                        .foregroundStyle(Stage.text)
                    Text(ghost.recordLine)
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.textFaint)
                        .lineLimit(1)
                    StageButton("Fight", kind: .primary, enabled: canFight, focusID: "fight-\(index)") {
                        startFight(ghost)
                    }
                    .frame(width: 108)
                }
            }
        }
    }

    private var canFight: Bool {
        fightOpen && (selected?.isValid ?? false)
    }

    private var buttons: some View {
        VStack(alignment: .trailing, spacing: 10) {
            StageButton("Publish my build", enabled: gates.ladderAvailable && selected != nil && !ladder.isBusy, focusID: "publish") {
                publish()
            }
            StageButton("Refresh", enabled: fightOpen && !ladder.isBusy, focusID: "refresh") {
                refresh(force: true)
            }
            Spacer(minLength: 0)
            if let selected {
                Text("\(selected.name.uppercased()). \(BuildRules.kilograms(selected.totalWeight)).")
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.textFaint)
                    // Bug 12: at the 13 pt floor the line wraps rather than shrinking.
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !gameCenter.statusLine.isEmpty {
                Text(gameCenter.statusLine)
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.textFaint)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            StageButton("Back", kind: .glass) { leave() }
        }
        .frame(width: 250)
    }

    // MARK: - The result

    private var resultScreen: some View {
        ZStack {
            StageBackdrop(host: host, still: .empty, dim: 0.5)
            VStack(spacing: 0) {
                if let settled {
                    GlassPanel(padding: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(settled.won ? "YOU WON" : "YOU LOST")
                                .font(Stage.display(34, weight: .black))
                                .kerning(1.4)
                                .foregroundStyle(settled.won ? Stage.text : Stage.textDim)
                            Text("\(settled.ghost.spec.name) of \(settled.ghost.displayName). \(settled.outcome).")
                                .font(Stage.label(13))
                                .foregroundStyle(Stage.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                            HairRule()
                            HStack(spacing: 24) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(settled.rating)")
                                        .font(Stage.numerals(30))
                                        .foregroundStyle(Stage.text)
                                    Text("NEW RATING")
                                        .font(Stage.label(11, weight: .bold))
                                        .kerning(1.2)
                                        .foregroundStyle(Stage.textFaint)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(settled.delta >= 0 ? "+\(settled.delta)" : "\(settled.delta)")
                                        .font(Stage.numerals(30))
                                        .foregroundStyle(settled.delta >= 0 ? Stage.text : Stage.danger)
                                    Text("CHANGE")
                                        .font(Stage.label(11, weight: .bold))
                                        .kerning(1.2)
                                        .foregroundStyle(Stage.textFaint)
                                }
                            }
                            if settled.ghost.isGenerated {
                                Text("This machine was generated, so nobody else was told.")
                                    .font(Stage.body(13))
                                    .foregroundStyle(Stage.textFaint)
                            }
                            StageButton("Back to the ladder", kind: .primary, focusID: "done") {
                                screen = .list
                                registerFocus()
                            }
                        }
                        .frame(maxWidth: 420, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            PadFocus.shared.set([PadItem("done") { screen = .list; registerFocus() }], back: { screen = .list; registerFocus() })
        }
    }

    // MARK: - Actions

    private func appear() {
        guard !didAppear else { return }
        didAppear = true
        gameCenter.start()
        guard fightOpen else { return }
        refresh(force: false)
    }

    private func refresh(force: Bool) {
        let wanted = tier
        Task { await ladder.refresh(tier: wanted, force: force) }
    }

    private func publish() {
        guard let build = selected else { return }
        Task { await ladder.publish(build: build) }
    }

    private func startFight(_ ghost: LadderService.Ghost) {
        guard fightOpen, let bot = selected, bot.isValid else { return }
        // Owner decision 13: the taster fight is spent when it starts.
        if gates.spendsTaster(.ladder) {
            let state = CareerStore.state(in: context)
            state.tasterLadderUsed += 1
            try? context.save()
        }
        let arena = CareerEngine.arena(tier, round: 0)
        // Seeded from the two ratings and the machine, so the same pairing is the same fight.
        let seed = abs((ghost.id.hashValue &* 31) &+ ladder.rating &* 7919) % 2_000_000_000
        pending = Pending(
            ghost: ghost,
            botID: bot.persistentModelID,
            botName: bot.name,
            arena: arena,
            seed: seed,
            // Brief v5 section 9.3: the ladder is an exhibition. The machine goes in pristine and
            // comes home exactly as it went, with nothing written into its record.
            playerConfig: bot.toBotConfig(id: CareerFightConfig.playerID, controller: "player", pristine: true),
            opponentConfig: ghost.spec.toBotConfig(id: CareerFightConfig.opponentID, controller: "ai")
        )
        settled = nil
        screen = .fight
    }

    private func settle(result: FightResult?, json: String) {
        guard let pending else {
            screen = .list
            return
        }
        let won = result?.outcome.winner == CareerFightConfig.playerID
        let outcome = result?.outcome.type ?? "judges"
        let delta = ladder.submit(result: LadderService.Outcome(opponent: pending.ghost, won: won))

        writeLog(pending: pending, result: result, json: json, won: won, outcome: outcome)

        // The two leaderboards, after every fight, per docs/stage6-spec.md section 3.
        gameCenter.reportLadder(rating: ladder.rating, careerWins: state?.wins ?? 0)

        settled = Settled(
            ghost: pending.ghost,
            won: won,
            delta: delta,
            rating: ladder.rating,
            outcome: outcomeSentence(result)
        )
        self.pending = nil
        screen = .result
        // The player's own machine goes back on the stage behind the panels.
        if let bot = selected {
            host.showStage(bot: bot.toBotConfig(id: CareerFightConfig.playerID, controller: "player"))
        }
    }

    /// A ladder fight is logged exactly as a career tie is, with `source` set to "ladder" so the
    /// replays screen can tell them apart.
    private func writeLog(pending: Pending, result: FightResult?, json: String, won: Bool, outcome: String) {
        let log = FightLog()
        log.date = Date()
        log.tier = tier
        log.round = 0
        log.source = FightLog.Source.ladder
        log.opponentID = pending.ghost.id
        log.opponentName = "\(pending.ghost.spec.name) of \(pending.ghost.displayName)"
        log.botName = pending.botName
        log.outcome = outcome
        log.didWin = won
        log.scrapEarned = 0
        log.repairCost = 0
        log.arena = pending.arena
        log.resultJSON = json
        // The configuration this fight was actually fought with, rebuilt from the same inputs and
        // the safe area `CareerFightView` sent, so S6's replay screen can watch a ladder fight.
        log.configJSON = CareerFightConfig.json(
            player: pending.playerConfig,
            opponent: pending.opponentConfig,
            arena: pending.arena,
            seed: pending.seed,
            safeArea: host.sentSafeArea,
            opponentAI: "normal"
        )
        context.insert(log)
        try? context.save()

        // Brief v5 section 9.3 (flagged in wave A): the ladder is an exhibition. No damage comes
        // home and nothing is written into the machine's fights, wins or knockouts; the
        // `FightLog` above, with `source = ladder`, is its history.
    }

    private func outcomeSentence(_ result: FightResult?) -> String {
        guard let result else { return "No result came back" }
        switch result.outcome.type {
        case "ko": return "Knockout at \(Int(result.outcome.atSeconds.rounded())) s"
        case "out_of_arena": return "Out of the arena"
        case "component_kill": return "Core destroyed"
        case "judges": return "Judges decision"
        default: return result.outcome.title
        }
    }

    private func leave() {
        if let bot = selected {
            host.showStage(bot: bot.toBotConfig(id: CareerFightConfig.playerID, controller: "player"))
        }
        dismiss()
    }

    // MARK: - The pad

    private func registerFocus() {
        var items: [PadItem] = [
            PadItem("publish", enabled: gates.ladderAvailable && selected != nil) { publish() },
            PadItem("refresh", enabled: fightOpen) { refresh(force: true) }
        ]
        for (index, ghost) in ladder.opponents.enumerated() {
            items.append(PadItem("fight-\(index)", enabled: canFight) { startFight(ghost) })
        }
        PadFocus.shared.set(items, back: { leave() })
    }
}
