//
//  CareerHomeView.swift
//  CAREER. The circuit ladder of brief section 9: where you are, what you have, and the way into
//  the bracket, the scouting report, the fight and the damage assessment.
//
//  Career navigation lives inside this one view rather than in `MenuView`'s path, so the whole
//  loop is in one place and the menu only has to know the word CAREER.
//

import SwiftUI
import SwiftData

/// Everything one career tie needs to be fought, held while the arena is busy with it.
struct PendingCareerFight {
    let botID: PersistentIdentifier
    let opponent: CareerEntrant
    let round: Int
    let arena: String
    let seed: Int
    let playerConfig: [String: Any]
    let opponentConfig: [String: Any]
}

struct CareerRootView: View {

    @Bindable var host: ArenaHost

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var states: [CareerState]
    @Query(sort: \BotBuild.createdAt, order: .forward) private var builds: [BotBuild]

    enum Screen {
        case home
        case bracket
        case scouting
        case fight
        case damage
        case garage
    }

    @State private var screen: Screen = .home
    @State private var chosenID: PersistentIdentifier?
    @State private var pending: PendingCareerFight?
    @State private var settlement: CareerStore.Settlement?
    @State private var settledBotID: PersistentIdentifier?
    @State private var didPrepare = false
    /// P6 (stage 6): the one moment the game brings the wall up by itself. Set when a tier final
    /// is won and the next circuit is behind it, shown after the damage assessment so the player
    /// gets their win first.
    @State private var wallOfferWaiting = false
    @State private var showingUnlock = false

    private var state: CareerState? { states.first }
    private var living: [BotBuild] { builds.filter { !$0.isWrittenOff } }
    private var chosen: BotBuild? {
        living.first { $0.persistentModelID == chosenID }
            ?? living.first { $0.isSelected }
            ?? living.first
    }

    var body: some View {
        Group {
            if let state {
                content(state)
            } else {
                ZStack {
                    StageBackdrop(host: host, still: .empty, dim: 0.4)
                    GlassPanel {
                        Text("Opening the circuit.")
                            .font(Stage.label(14))
                            .foregroundStyle(Stage.text)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear { prepare() }
        // The only place in the app that raises the unlock screen on its own, and only once ever
        // (`Gates.shouldOfferAfterRegionalFinal`). The Settings row is the other, deliberate, way.
        .unlockScreen(isPresented: $showingUnlock)
    }

    @ViewBuilder
    private func content(_ state: CareerState) -> some View {
        switch screen {
        case .home:
            CareerHomeView(
                host: host,
                state: state,
                bot: chosen,
                onEnter: { enterSeason(state) },
                onBracket: { go(.bracket) },
                onGarage: { go(.garage) },
                onBack: { leave() }
            )
        case .bracket:
            if let bracket = state.bracket {
                BracketView(
                    host: host,
                    bracket: bracket,
                    tier: bracket.tier,
                    onScout: { go(.scouting) },
                    onBack: { go(.home) }
                )
            } else {
                emptyBracket
            }
        case .scouting:
            if let bracket = state.bracket, let opponent = bracket.playerNextOpponent,
               let match = bracket.playerMatch {
                ScoutingView(
                    host: host,
                    opponent: opponent,
                    tier: state.tier,
                    round: match.round,
                    builds: builds,
                    record: CareerStore.record(for: opponent.rivalID, in: context),
                    scrap: state.scrap,
                    chosenID: $chosenID,
                    onFight: { startFight(state, opponent: opponent, round: match.round) },
                    onBack: { go(.bracket) }
                )
            } else {
                emptyBracket
            }
        case .fight:
            if let pending {
                CareerFightView(
                    host: host,
                    playerConfig: pending.playerConfig,
                    opponentConfig: pending.opponentConfig,
                    arena: pending.arena,
                    seed: pending.seed
                ) { result, json in
                    settle(state, result: result, json: json)
                }
            } else {
                emptyBracket
            }
        case .damage:
            if let settlement {
                DamageAssessmentView(
                    host: host,
                    settlement: settlement,
                    botName: settledBot?.name ?? "Your machine",
                    opponentName: pending?.opponent.name ?? "the opposition",
                    scrap: state.scrap,
                    tier: state.tier,
                    onRepair: { repairSettled(state) },
                    onWriteOff: { writeOffSettled(state) },
                    onDone: { finishAssessment(state) }
                )
            } else {
                emptyBracket
            }
        case .garage:
            CareerGarageView(host: host, state: state, builds: builds) { go(.home) }
        }
    }

    private var emptyBracket: some View {
        ZStack {
            StageBackdrop(host: host, still: .empty, dim: 0.42)
            VStack(spacing: 12) {
                Text("There is no season running.")
                    .font(Stage.label(14))
                    .foregroundStyle(Stage.text)
                StageButton("Back", kind: .primary) { go(.home) }
                    .frame(width: 200)
            }
        }
    }

    private var settledBot: BotBuild? {
        builds.first { $0.persistentModelID == settledBotID }
    }

    // MARK: - Navigation

    private func go(_ next: Screen) {
        screen = next
        if next != .fight, next != .scouting {
            restoreStage()
        }
    }

    /// The player's own machine goes back on the stage whenever the career is not looking at
    /// somebody else's, framed at 28 % across so it stands clear of the career's panels rather
    /// than behind them. `showStage` cannot carry the framing, so it brings the surface back with
    /// nothing on it and the machine follows.
    private func restoreStage() {
        guard let bot = chosen else { return }
        host.showStage(bot: nil)
        host.sendWorkshopConfig(
            bot.toBotConfig(id: CareerFightConfig.playerID, controller: "player"),
            frame: StageLayout.botFrame
        )
    }

    private func leave() {
        restoreStage()
        dismiss()
    }

    private func prepare() {
        guard !didPrepare else { return }
        didPrepare = true
        CareerStore.state(in: context)
        CareerStore.prepareRivals(in: context)
        if chosenID == nil { chosenID = chosen?.persistentModelID }
    }

    // MARK: - Actions

    private func enterSeason(_ state: CareerState) {
        guard CareerStore.enterSeason(state, player: chosen, in: context) else { return }
        go(.bracket)
    }

    private func startFight(_ state: CareerState, opponent: CareerEntrant, round: Int) {
        guard let bot = chosen, bot.isValid else { return }
        CareerStore.setPlayerMachine(state, to: bot, in: context)
        let arena = CareerEngine.arena(state.tier, round: round)
        pending = PendingCareerFight(
            botID: bot.persistentModelID,
            opponent: opponent,
            round: round,
            arena: arena,
            seed: state.currentSeasonSeed &+ (round &+ 1) &* 7919,
            playerConfig: bot.toBotConfig(id: CareerFightConfig.playerID, controller: "player"),
            opponentConfig: opponent.spec.toBotConfig(id: CareerFightConfig.opponentID, controller: "ai")
        )
        settlement = nil
        screen = .fight
    }

    private func settle(_ state: CareerState, result: FightResult?, json: String) {
        guard let pending, let bot = builds.first(where: { $0.persistentModelID == pending.botID }) else {
            go(.home)
            return
        }
        settledBotID = bot.persistentModelID
        settlement = CareerStore.settle(
            state: state,
            bot: bot,
            opponent: pending.opponent,
            round: pending.round,
            arena: pending.arena,
            result: result,
            resultJSON: json,
            in: context
        )
        // The final was won and the next circuit is behind the wall. Remember it; the offer comes
        // once the player has read their assessment.
        if settlement?.hitTheWall == true, Gates.shouldOfferAfterRegionalFinal {
            wallOfferWaiting = true
        }
        go(.damage)
    }

    private func repairSettled(_ state: CareerState) {
        if let bot = settledBot, let settlement {
            CareerStore.repair(bot, bill: settlement.bill, state: state, in: context)
        }
        finishAssessment(state)
    }

    private func writeOffSettled(_ state: CareerState) {
        if let bot = settledBot, let settlement {
            CareerStore.writeOff(bot, bill: settlement.bill, state: state, in: context)
            if let next = living.first(where: { $0.persistentModelID != bot.persistentModelID }) {
                Garage.select(next, in: living)
                chosenID = next.persistentModelID
            }
            try? context.save()
        }
        finishAssessment(state)
    }

    private func finishAssessment(_ state: CareerState) {
        CareerStore.defer_(state, in: context)
        settlement = nil
        pending = nil
        go(state.bracket?.playerMatch != nil ? .bracket : .home)
        offerTheUnlockIfOwed()
    }

    /// One shot. The flag is set the moment the screen is raised, not when it closes, so a crash
    /// on the unlock screen cannot turn one offer into two.
    private func offerTheUnlockIfOwed() {
        guard wallOfferWaiting else { return }
        wallOfferWaiting = false
        guard Gates.shouldOfferAfterRegionalFinal else { return }
        Gates.markRegionalOfferShown()
        showingUnlock = true
    }
}

// MARK: - Home

struct CareerHomeView: View {

    @Bindable var host: ArenaHost
    let state: CareerState
    let bot: BotBuild?

    var onEnter: () -> Void
    var onBracket: () -> Void
    var onGarage: () -> Void
    var onBack: () -> Void

    private var tierEntry: CareerCatalogue.TierEntry? { CareerCatalogue.shared.tier(state.tier) }
    private var fee: Int { CareerEngine.entryFee(state.tier) }
    private var seasonRunning: Bool { state.bracket?.playerMatch != nil }
    private var canAfford: Bool { state.scrap >= fee }

    private static let gutter: CGFloat = 28

    var body: some View {
        ZStack {
            StageBackdrop(host: host, still: .withBot, dim: 0.2)
            StageScrim()

            GeometryReader { proxy in
                HStack(alignment: .top, spacing: 18) {
                    ZStack {
                        StageOrbitPad(host: host)
                        left
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    Spacer(minLength: 8)
                    // The season panel used to sit on the left, over the machine. It belongs with
                    // the buttons, in the one column on the right.
                    VStack(alignment: .trailing, spacing: 10) {
                        season
                        buttons
                    }
                    .frame(width: StageLayout.columnWidth(proxy.size.width - 2 * Self.gutter))
                }
                .padding(.horizontal, Self.gutter)
                .padding(.top, 20)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear { registerFocus() }
        .onChange(of: seasonRunning) { _, _ in registerFocus() }
        .onChange(of: state.scrap) { _, _ in registerFocus() }
    }

    /// What the pad can land on here (docs/stage4-swift-notes.md, agent S2's `PadFocus`).
    private func registerFocus() {
        PadFocus.shared.set(
            [
                seasonRunning
                    ? PadItem("continue") { onBracket() }
                    : PadItem("enter", enabled: canAfford && (bot?.isValid ?? false)) { onEnter() },
                PadItem("bracket", enabled: state.bracket != nil) { onBracket() },
                PadItem("garage") { onGarage() }
            ],
            back: { onBack() }
        )
    }

    /// Copy only, all of it in the top quarter, so the machine behind it is never read through
    /// the words.
    private var left: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CAREER")
                .font(Stage.label(12, weight: .bold))
                .kerning(2)
                .foregroundStyle(Stage.textFaint)

            Text(state.tier.title.uppercased())
                .font(Stage.display(40, weight: .black))
                .kerning(1.6)
                .foregroundStyle(Stage.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.6), radius: 10, y: 2)

            Rectangle()
                .fill(Stage.text.opacity(0.85))
                .frame(width: 66, height: 3)

            ScrapBadge(amount: state.scrap, size: 24)

            Spacer(minLength: 0)

            if let bot {
                Text("\(bot.name.uppercased()). \(BuildRules.kilograms(bot.totalWeight)). \(bot.partsLine).")
                    .font(Stage.body(11))
                    .foregroundStyle(Stage.textFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: 300, alignment: .leading)
    }

    /// Where the season stands, on glass at the top of the right hand column. It scrolls rather
    /// than pushing the buttons off a 375 pt screen.
    private var season: some View {
        GlassPanel(padding: 11) {
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    Text(seasonLine)
                        .font(Stage.label(13))
                        .foregroundStyle(Stage.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(arenaLine)
                        .font(Stage.body(11))
                        .foregroundStyle(Stage.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider().overlay(Stage.edge)
                    StageStat(label: "Record", value: "\(state.wins) of \(state.fightsPlayed)")
                    StageStat(label: "Garage", value: "\(state.garageCapacity) \(state.garageCapacity == 1 ? "slot" : "slots")")
                    StageStat(label: "Blueprints", value: "\(state.blueprints.count)")
                    if state.championshipsWon > 0 {
                        StageStat(label: "Championships", value: "\(state.championshipsWon)", tint: Stage.gold)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var seasonLine: String {
        guard let bracket = state.bracket else {
            return "No season entered. The \(state.tier.title) bracket is eight machines, three rounds."
        }
        if let match = bracket.playerMatch, let opponent = bracket.playerNextOpponent {
            return "\(CareerBracket.roundName(match.round, of: CareerBracket.rounds).capitalizedFirst) against \(opponent.name)."
        }
        if bracket.playerWonTier {
            return "You took the last bracket. The \(state.tier.title) is open."
        }
        return "Knocked out of the last bracket. Enter again when you are ready."
    }

    private var arenaLine: String {
        guard let entry = tierEntry else { return "" }
        let names = entry.arenas.map { Catalogue.shared.arena($0)?.name ?? $0 }
        let where_ = names.count > 1 ? names.joined(separator: " and ") : (names.first ?? "The Yard")
        return "Fought in \(where_). Entry \(entry.entryFee) scrap, \(entry.purse) a win and \(entry.purse * entry.finalMultiplier) for the final."
    }

    private var buttons: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if seasonRunning {
                StageButton("Continue", kind: .primary, focusID: "continue", action: onBracket)
            } else {
                StageButton("Enter for \(fee)", kind: .primary, enabled: canAfford && (bot?.isValid ?? false), focusID: "enter", action: onEnter)
            }
            StageButton("Bracket", enabled: state.bracket != nil, focusID: "bracket", action: onBracket)
            StageButton("Garage", focusID: "garage", action: onGarage)
            if !canAfford, !seasonRunning {
                Text("You need \(fee - state.scrap) more scrap for the entry fee. Win a quick fight.")
                    .font(Stage.body(10))
                    .foregroundStyle(Stage.danger)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            StageButton("Back", kind: .glass, action: onBack)
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }
}
