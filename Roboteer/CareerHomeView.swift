//
//  CareerHomeView.swift
//  CAREER, as a season you can see (brief v4 section 6).
//
//  The home screen IS the season screen: the tier strip across the top with the unlock wall marked
//  where the gates put it, the bracket of eight in the middle with your slot lit, and the next
//  fight card at the bottom with the opponent, the house bot on duty, the arena, the fee, the purse
//  and the scouting and grudge lines. One primary button, FIGHT. Two secondaries, Garage and
//  Repairs. Every number the player can be charged is on this screen before FIGHT is pressed.
//
//  Career navigation lives inside this one view rather than in `MenuView`'s path, so the whole
//  loop is in one place and the menu only has to know the word CAREER.
//
//  Layout rule (docs/stage4-swift-notes.md, docs/stage5-swift-notes.md): the left of the screen
//  belongs to the live machine, framed at `StageLayout.botFrame`, and every panel goes in the one
//  column on the right.
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
    /// The card the player read before pressing FIGHT. The fight config is built from it, so what
    /// was promised on the card and what the arena is told cannot drift apart.
    let next: NextFight
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
    /// The bracket as it stood when the settlement screen was raised, so the result can slide into
    /// it there rather than appearing already filed.
    @State private var settledBracket: CareerBracket?
    @State private var settledRound = 0
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
                next: nextFight(state),
                gates: Gates.snapshot,
                stable: living,
                onEnter: { enterSeason(state) },
                onFight: { fightNextTie(state) },
                onBracket: { go(.bracket) },
                onScout: { go(.scouting) },
                onGarage: { go(.garage) },
                onRepair: { build in repairFromHome(build, state: state) },
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
                    next: nextFight(state),
                    chosenID: $chosenID,
                    onFight: { fightNextTie(state) },
                    onBack: { go(.home) }
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
                    seed: pending.seed,
                    next: pending.next
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
                    bracket: settledBracket,
                    settledRound: settledRound,
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

    /// The next tie as one value: who, where, who is guarding the corner, what it pays and what the
    /// chosen machine still owes. Everything the card prints and everything the fight config sends.
    private func nextFight(_ state: CareerState) -> NextFight? {
        let rivalID = state.bracket?.playerNextOpponent?.rivalID ?? ""
        let due = chosen.map { CareerEngine.repairBill(for: $0.spec, damage: $0.currentDamage).total } ?? 0
        return NextFight.make(
            tier: state.tier,
            bracket: state.bracket,
            seasonSeed: state.currentSeasonSeed,
            record: CareerStore.record(for: rivalID, in: context),
            playerBotName: chosen?.name ?? "your machine",
            repairsDue: due
        )
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
        // V3 (wave V): open straight onto one of the career's own screens, so its layout can be
        // photographed on a headless simulator. Presentation only.
        if ArenaHost.hasLaunchFlag("-autoUnlock") {
            showingUnlock = true
        }
        if ArenaHost.hasLaunchFlag("-autoCareerFight"), let state {
            // One runloop later, so the career store has settled before the tie is started.
            DispatchQueue.main.async { fightNextTie(state) }
        } else if ArenaHost.hasLaunchFlag("-autoBracket") {
            screen = .bracket
        } else if ArenaHost.hasLaunchFlag("-autoScouting") {
            screen = .scouting
        } else if ArenaHost.hasLaunchFlag("-autoCareerGarage") {
            screen = .garage
        }
    }

    // MARK: - Actions

    /// Pay the fee, draw the bracket, and stay here: the season screen is where the new bracket
    /// and the first next-fight card appear.
    private func enterSeason(_ state: CareerState) {
        guard CareerStore.enterSeason(state, player: chosen, in: context) else { return }
        go(.home)
    }

    /// FIGHT. The card has already said who, where, for how much and against which house bot.
    private func fightNextTie(_ state: CareerState) {
        guard let bracket = state.bracket, let match = bracket.playerMatch,
              let opponent = bracket.playerNextOpponent,
              let next = nextFight(state) else { return }
        startFight(state, opponent: opponent, round: match.round, next: next)
    }

    private func startFight(_ state: CareerState, opponent: CareerEntrant, round: Int, next: NextFight) {
        guard let bot = chosen, bot.isValid else { return }
        CareerStore.setPlayerMachine(state, to: bot, in: context)
        pending = PendingCareerFight(
            botID: bot.persistentModelID,
            opponent: opponent,
            round: round,
            arena: next.arena,
            seed: state.currentSeasonSeed &+ (round &+ 1) &* 7919,
            next: next,
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
        settledRound = pending.round
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
        settledBracket = state.bracket
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

    /// Back to the season screen, always: the next-fight card is what has to update after a tie,
    /// and after the final it is the season summary that has to appear (brief v4 section 6).
    private func finishAssessment(_ state: CareerState) {
        CareerStore.defer_(state, in: context)
        settlement = nil
        pending = nil
        settledBracket = nil
        go(.home)
        offerTheUnlockIfOwed()
    }

    /// The Repairs button on the season screen. Same call the garage makes, so there is one place
    /// a bill is paid.
    private func repairFromHome(_ build: BotBuild, state: CareerState) {
        let bill = CareerEngine.repairBill(for: build.spec, damage: build.currentDamage)
        CareerStore.repair(build, bill: bill, state: state, in: context)
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

// MARK: - The season screen

struct CareerHomeView: View {

    @Bindable var host: ArenaHost
    let state: CareerState
    let bot: BotBuild?
    /// Nil when no season is running, or when the player is out of the one that is.
    let next: NextFight?
    let gates: Gates
    /// Every machine that is not written off, for the Repairs sheet.
    let stable: [BotBuild]

    var onEnter: () -> Void
    var onFight: () -> Void
    var onBracket: () -> Void
    var onScout: () -> Void
    var onGarage: () -> Void
    var onRepair: (BotBuild) -> Void
    var onBack: () -> Void

    @State private var showingRepairs = false

    private var fee: Int { CareerEngine.entryFee(state.tier) }
    private var canAfford: Bool { state.scrap >= fee }
    private var canFight: Bool { next != nil && (bot?.isValid ?? false) && bot?.fitnessFault == nil }
    private var seasonOver: Bool { state.bracket != nil && next == nil }
    private var tookTheTier: Bool { state.bracket?.playerWonTier ?? false }

    /// Everything still owed on machines that are not written off. This is a charge the player can
    /// face, so it is on the screen before FIGHT.
    private var repairsOutstanding: Int {
        stable.reduce(0) { total, build in
            total + CareerEngine.repairBill(for: build.spec, damage: build.currentDamage).total
        }
    }

    private static let gutter: CGFloat = 28

    var body: some View {
        ZStack {
            StageBackdrop(host: host, still: .withBot, dim: 0.2)
            StageScrim()

            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 8) {
                    TierStrip(current: state.tier, gates: gates)

                    HStack(alignment: .top, spacing: 18) {
                        ZStack {
                            StageOrbitPad(host: host)
                            left
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        Spacer(minLength: 8)
                        rightColumn
                            .frame(width: StageLayout.columnWidth(proxy.size.width - 2 * Self.gutter))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .padding(.horizontal, Self.gutter)
                .padding(.top, 14)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if showingRepairs {
                CareerRepairsSheet(
                    stable: stable,
                    scrap: state.scrap,
                    onRepair: onRepair,
                    onClose: { showingRepairs = false; registerFocus() }
                )
            }
        }
        .onAppear { registerFocus() }
        .onChange(of: next?.opponent.id) { _, _ in registerFocus() }
        .onChange(of: state.scrap) { _, _ in registerFocus() }
        .onChange(of: state.bracketJSON) { _, _ in registerFocus() }
    }

    /// What the pad can land on here (docs/stage4-swift-notes.md, agent S2's `PadFocus`).
    private func registerFocus() {
        guard !showingRepairs else { return }
        PadFocus.shared.set(
            [
                next != nil
                    ? PadItem("fight", enabled: canFight) { onFight() }
                    : PadItem("enter", enabled: canAfford && (bot?.isValid ?? false)) { onEnter() },
                PadItem("garage") { onGarage() },
                PadItem("repairs", enabled: repairsOutstanding > 0) {
                    showingRepairs = true
                    PadFocus.shared.pushContext()
                }
            ],
            back: { onBack() }
        )
    }

    // MARK: - The clear left

    /// Copy only, all of it down the left edge, so the machine behind it is never read through
    /// the words.
    private var left: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                StageButton("Back", kind: .quiet, action: onBack)
                    .frame(width: 88)
                Spacer(minLength: 0)
            }

            Text(state.tier.title.uppercased())
                .font(Stage.display(34, weight: .black))
                .kerning(1.4)
                .foregroundStyle(Stage.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.6), radius: 10, y: 2)

            Rectangle()
                .fill(Stage.text.opacity(0.85))
                .frame(width: 60, height: 3)

            ScrapBadge(amount: state.scrap, size: 22)

            LowerThird(bar: Stage.lineDim, entersFrom: .leading) {
                Text("Record \(state.wins) of \(state.fightsPlayed). \(state.blueprints.count) blueprints. \(state.garageCapacity) garage \(state.garageCapacity == 1 ? "slot" : "slots").")
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.typeDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let bot {
                LowerThird(bar: Stage.lineDim, entersFrom: .leading) {
                    Text("\(bot.name.uppercased()). \(BuildRules.kilograms(bot.totalWeight)). \(bot.partsLine).")
                        .font(Stage.label(11))
                        .kerning(Stage.Tracking.label(11))
                        .foregroundStyle(Stage.typeDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 300, alignment: .leading)
    }

    // MARK: - The season, in the one column on the right

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // The card first, the board under it. Brief v4 section 6 draws the bracket in
                    // the middle and the card at the bottom, but the bracket of eight is 150 pt of
                    // a 402 pt screen and the card is what the player has to read before pressing
                    // FIGHT, so the one that has to be on screen without a scroll is the card.
                    // The whole board is still a flick down, and FULL BOARD opens it outright.
                    middlePanel
                    if let bracket = state.bracket {
                        GlassPanel(padding: 9) {
                            CompactBracket(bracket: bracket, onOpen: onBracket)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            buttons
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var middlePanel: some View {
        if let next {
            NextFightCard(next: next, onScout: onScout)
        } else if tookTheTier {
            SeasonSummaryPanel(tally: state.seasonTally, tier: state.tier, nextFee: fee)
        } else if seasonOver {
            GlassPanel(padding: 11) {
                VStack(alignment: .leading, spacing: 6) {
                    StageHeading("Season over")
                    Text("You are out of the \(state.tier.title). The board played itself out without you.")
                        .font(Stage.body(12))
                        .foregroundStyle(Stage.text)
                        .fixedSize(horizontal: false, vertical: true)
                    StageStat(label: "Re-enter", value: "\(fee)", tint: canAfford ? Stage.text : Stage.danger)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            GlassPanel(padding: 11) {
                VStack(alignment: .leading, spacing: 6) {
                    StageHeading("No season entered")
                    Text("The \(state.tier.title) is eight machines and three rounds. \(arenaLine)")
                        .font(Stage.body(12))
                        .foregroundStyle(Stage.text)
                        .fixedSize(horizontal: false, vertical: true)
                    HairRule()
                    StageStat(label: "Entry", value: "\(fee)", tint: canAfford ? Stage.text : Stage.danger)
                    StageStat(label: "A win pays", value: "\(CareerEngine.purse(state.tier, round: 0))", tint: Stage.gold)
                    StageStat(label: "The final pays", value: "\(CareerEngine.purse(state.tier, round: CareerBracket.rounds - 1))", tint: Stage.gold)
                    if repairsOutstanding > 0 {
                        StageStat(label: "Repairs owing", value: "\(repairsOutstanding)", tint: Stage.danger)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var arenaLine: String {
        guard let entry = CareerCatalogue.shared.tier(state.tier) else { return "" }
        let names = entry.arenas.map { Catalogue.shared.arena($0)?.name ?? $0 }
        let where_ = names.count > 1 ? names.joined(separator: " and ") : (names.first ?? "The Yard")
        return "Fought in \(where_)."
    }

    // MARK: - One primary, two secondaries

    private var buttons: some View {
        VStack(spacing: 7) {
            if next != nil {
                StageButton("Fight", kind: .primary, enabled: canFight, focusID: "fight", action: onFight)
                if let fault = bot?.fitnessFault {
                    Text("\(fault). Repair it for \(next?.repairsDue ?? 0) before the tie, or send another machine.")
                        .font(Stage.body(10))
                        .foregroundStyle(Stage.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if !(bot?.isValid ?? false) {
                    Text("Your machine is not legal. Fix it in the garage before the tie.")
                        .font(Stage.body(10))
                        .foregroundStyle(Stage.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                StageButton(
                    seasonOver ? "Re-enter for \(fee)" : "Enter for \(fee)",
                    kind: .primary,
                    enabled: canAfford && (bot?.isValid ?? false),
                    focusID: "enter",
                    action: onEnter
                )
                if !canAfford {
                    Text("You need \(fee - state.scrap) more scrap for the entry fee. Win a quick fight.")
                        .font(Stage.body(10))
                        .foregroundStyle(Stage.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: 7) {
                StageButton("Garage", kind: .quiet, focusID: "garage", action: onGarage)
                StageButton(
                    repairsOutstanding > 0 ? "Repairs \(repairsOutstanding)" : "Repairs",
                    kind: .quiet,
                    enabled: repairsOutstanding > 0,
                    focusID: "repairs"
                ) {
                    showingRepairs = true
                    PadFocus.shared.pushContext()
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - The tier strip

/// Scrapyard to Masters across the top, the player's circuit lit, and the wall marked where the
/// gates put it (brief v4 section 6). Locked circuits are dim with a lock; the wall itself is a
/// hairline rule with two words on it, so a locked player can see exactly where the free game ends.
struct TierStrip: View {

    let current: CareerTier
    let gates: Gates

    var body: some View {
        // Five score bugs joined by one rule (design system section 5). The rule runs behind the
        // bugs rather than between them, so the strip reads as one graphic instead of five chips.
        HStack(spacing: 0) {
            ForEach(Array(CareerTier.allCases.enumerated()), id: \.element) { index, tier in
                if index > 0 { joint(before: tier) }
                bug(tier)
            }
        }
        .background(alignment: .center) {
            HairRule()
                .padding(.horizontal, 10)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Circuit \(current.title)")
    }

    private func bug(_ tier: CareerTier) -> some View {
        let isCurrent = tier == current
        let open = gates.tierAvailable(tier)
        return VStack(spacing: 1) {
            Text(isCurrent ? "Circuit" : (open ? "Open" : "Locked"))
                .font(Stage.label(11))
                .kerning(Stage.Tracking.label(11))
                .foregroundStyle(isCurrent ? Stage.line : Stage.textFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 3) {
                if !open {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Stage.textFaint)
                }
                Text(tier.title.uppercased())
                    .font(Stage.display(15))
                    .kerning(Stage.Tracking.display(15))
                    .foregroundStyle(isCurrent ? Stage.type : (open ? Stage.typeDim : Stage.textFaint))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background {
            ZStack {
                CutRect(8).fill(isCurrent ? Stage.line.opacity(0.18) : Stage.glass)
                CutRect(8).strokeBorder(isCurrent ? Stage.line : Stage.lineDim, lineWidth: 1)
            }
        }
    }

    /// The wall: drawn between the last free circuit and the first locked one, and nowhere else.
    @ViewBuilder
    private func joint(before tier: CareerTier) -> some View {
        if gates.firstLockedTier == tier {
            Text("FULL GAME")
                .font(Stage.label(11))
                .kerning(Stage.Tracking.label(11))
                .foregroundStyle(Stage.line)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Stage.ink.opacity(0.9))
                .overlay(alignment: .leading) {
                    Rectangle().fill(Stage.line).frame(width: 2)
                }
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Stage.line).frame(width: 2)
                }
                .padding(.horizontal, 5)
        } else {
            Color.clear.frame(width: 8, height: 1)
        }
    }
}

// MARK: - The next fight card

/// The bottom of the season screen: who is in the other corner, who is guarding the house bot's
/// corner, where it is fought, what it cost to enter, what a win pays, and what is known about
/// them. Tapping it opens the full scouting report.
struct NextFightCard: View {

    let next: NextFight
    var onScout: () -> Void

    var body: some View {
        GlassPanel(padding: 11) {
            VStack(alignment: .leading, spacing: 6) {
                // The card's lower-third header (design system section 5).
                LowerThird(bar: Stage.line, entersFrom: .trailing) {
                    HStack(spacing: 8) {
                        Text("NEXT FIGHT")
                            .font(Stage.display(16))
                            .kerning(Stage.Tracking.display(16))
                            .foregroundStyle(Stage.type)
                        Text(next.roundTitle.uppercased())
                            .font(Stage.label(11))
                            .kerning(Stage.Tracking.label(11))
                            .foregroundStyle(Stage.line)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 4)
                        Text("SCOUTING REPORT")
                            .font(Stage.label(11))
                            .kerning(Stage.Tracking.label(11))
                            .foregroundStyle(Stage.textFaint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)

                HStack(alignment: .center, spacing: 8) {
                    LiverySwatch(hex: next.opponent.liveryHex, size: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(next.opponent.name.uppercased())
                            .font(Stage.display(19))
                            .kerning(0.9)
                            .foregroundStyle(Stage.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Text(next.opponent.roboteer)
                            .font(Stage.label(10))
                            .foregroundStyle(Stage.textDim)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(BuildRules.kilograms(BuildRules.totalWeight(next.opponent.spec)))
                        .font(Stage.numerals(13))
                        .foregroundStyle(Stage.textDim)
                }

                Text(next.partsLine)
                    .font(Stage.label(11))
                    .kerning(Stage.Tracking.label(11))
                    .foregroundStyle(Stage.type)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // Every number the player can be charged, as a row of score bugs, ABOVE the arena
                // and the scouting prose. Brief v4 section 6 asks for the money to be on the screen
                // before FIGHT is pressed, and on a 402 pt phone that means above the fold rather
                // than merely somewhere on the card.
                HStack(spacing: 6) {
                    ScoreBug(label: "Entry paid", value: "\(next.entryFee)", size: 18)
                    ScoreBug(
                        label: next.isFinal ? "Final pays" : "A win pays",
                        value: "\(next.purse)",
                        tint: Stage.scrap,
                        size: 18
                    )
                    if next.repairsDue > 0 {
                        ScoreBug(label: "Repairs owing", value: "\(next.repairsDue)", tint: Stage.danger, size: 18)
                    }
                    Spacer(minLength: 0)
                }

                HairRule()

                // The arena and the house bot on duty, which is new in brief v4 and is the thing a
                // player most needs to know before pressing FIGHT.
                StageStat(label: "Arena", value: next.arenaName)
                StageStat(label: "House bot", value: next.houseBotName)
                Text(next.houseBotLine)
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.textFaint)
                    .fixedSize(horizontal: false, vertical: true)

                HairRule()

                Text(next.scoutingLine)
                    .font(Stage.body(11))
                    .foregroundStyle(Stage.textDim)
                    .fixedSize(horizontal: false, vertical: true)

                if !next.grudgeLine.isEmpty {
                    Text(next.grudgeLine)
                        .font(Stage.body(11))
                        .italic()
                        .foregroundStyle(Stage.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture { onScout() }
    }
}

// MARK: - The season summary

/// What winning the final was worth: the record, the scrap and the blueprints (brief v4 section 6).
/// It stays on the season screen until the next season is entered, and the tier strip above it has
/// already moved on.
struct SeasonSummaryPanel: View {

    let tally: SeasonTally
    /// The circuit the player is on NOW, which is the one after the season the summary is about.
    let tier: CareerTier
    let nextFee: Int

    var body: some View {
        GlassPanel(padding: 11) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    StageHeading("Season summary")
                    Spacer(minLength: 4)
                    Text("\(tally.tier.title.uppercased()) TAKEN")
                        .font(Stage.label(9, weight: .bold))
                        .kerning(1.2)
                        .foregroundStyle(Stage.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Stage.win, in: CutRect(6))
                }

                ForEach(tally.summaryLines, id: \.self) { line in
                    Text(line)
                        .font(Stage.body(12))
                        .foregroundStyle(Stage.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HairRule()

                if tally.tier != tier {
                    Text("You are in the \(tier.title) now.")
                        .font(Stage.label(12))
                        .foregroundStyle(Stage.text)
                }
                StageStat(label: "Next entry", value: "\(nextFee)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Repairs

/// The second secondary button. One row per machine with what it still owes, so a bill can be
/// cleared without walking into the garage and back.
struct CareerRepairsSheet: View {

    let stable: [BotBuild]
    let scrap: Int
    var onRepair: (BotBuild) -> Void
    var onClose: () -> Void

    var body: some View {
        ZStack {
            Stage.ink.opacity(0.70)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }

            GlassPanel(padding: 14, deep: true) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        StageHeading("Repairs")
                        Spacer(minLength: 6)
                        ScrapBadge(amount: scrap, size: 16)
                    }

                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(stable) { build in
                                row(build)
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: 190)

                    StageButton("Close", kind: .quiet, focusID: "close") { close() }
                }
                .frame(width: 330)
            }
        }
        .onAppear {
            PadFocus.shared.set([PadItem("close") { close() }], back: { close() })
        }
    }

    private func close() {
        PadFocus.shared.popContext()
        onClose()
    }

    private func row(_ build: BotBuild) -> some View {
        let bill = CareerEngine.repairBill(for: build.spec, damage: build.currentDamage)
        return HStack(spacing: 8) {
            LiverySwatch(hex: build.liveryHex, size: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(build.name.uppercased())
                    .font(Stage.display(13))
                    .kerning(0.5)
                    .foregroundStyle(Stage.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(bill.isPristine
                     ? "No damage."
                     : "\(Int((bill.fractionOfValue * 100).rounded()))% of its value.")
                    .font(Stage.body(10))
                    .foregroundStyle(bill.isWriteOff ? Stage.danger : Stage.textFaint)
            }
            Spacer(minLength: 4)
            if !bill.isPristine {
                Button {
                    onRepair(build)
                } label: {
                    Text("PAY \(bill.total)")
                        .font(Stage.label(11, weight: .bold))
                        .kerning(0.8)
                        .foregroundStyle(scrap >= bill.total ? Stage.type : Stage.textFaint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background {
                            ZStack {
                                CutRect(6).fill(scrap >= bill.total ? Stage.line.opacity(0.18) : Stage.type.opacity(0.05))
                                CutRect(6).strokeBorder(scrap >= bill.total ? Stage.line : Color.clear, lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(scrap < bill.total)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            CutRect(8)
                .fill(Stage.type.opacity(0.04))
        }
    }
}
