//
//  CareerHomeView.swift
//  CAREER, as a season you can see (brief v4 section 6).
//
//  The home screen IS the season screen, drawn as option A of docs/look/menus-options.html: the
//  back chevron and the tier line top left, the circuit in display type with one dim line of
//  housekeeping under it, ONE panel on the right holding the next tie with FIGHT inside it, and
//  the season as a four slot strip under the panel. Garage and the repair bill are text links.
//  Every number the player can be charged is still on this screen before FIGHT is pressed, as one
//  money sentence (design system section 8).
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

// MARK: - The season screen (option A, docs/look/menus-options.html)

/// One screen, one hero. The left is copy only: the back chevron, the tier line, the circuit in
/// display type and ONE dim line of housekeeping. The right is ONE panel, the next tie, with FIGHT
/// inside it and everything else demoted to a text link. Under the panel the season is a four slot
/// strip, and the full board is one tap away (design system section 8).
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

    private static let gutter: CGFloat = 26

    var body: some View {
        ZStack {
            StageBackdrop(host: host, still: .withBot, dim: 0.2)
            StageScrim()

            GeometryReader { proxy in
                VStack(spacing: 0) {
                    // The chevron and the tier line run across the top of the screen, clear of
                    // both columns: five words need the room and neither column has it.
                    HStack(alignment: .center, spacing: 2) {
                        BackChevron(action: onBack)
                        TierLine(items: tierItems)
                        Spacer(minLength: 0)
                    }

                    HStack(alignment: .top, spacing: 16) {
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

                    // The strip is the width of the SCREEN, not of the safe area, so it reads as a
                    // broadcast band rather than a floating box. The words keep the gutter.
                    Ticker(lines: tickerLines, textInset: Self.gutter)
                        .padding(.horizontal, -Self.gutter)
                        .ignoresSafeArea(edges: .horizontal)
                }
                .padding(.horizontal, Self.gutter)
                .padding(.top, 12)
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

    /// What the pad can land on here (docs/stage4-swift-notes.md, agent S2's `PadFocus`). Every
    /// action on the screen is in this list, links included, because a link is a button now.
    private func registerFocus() {
        guard !showingRepairs else { return }
        var items: [PadItem] = []
        if next != nil {
            items.append(PadItem("fight", enabled: canFight) { onFight() })
            items.append(PadItem("scout") { onScout() })
        } else {
            items.append(PadItem("enter", enabled: canAfford && (bot?.isValid ?? false)) { onEnter() })
        }
        items.append(PadItem("garage") { onGarage() })
        if repairsOutstanding > 0 {
            items.append(PadItem("repairs") {
                showingRepairs = true
                PadFocus.shared.pushContext()
            })
        }
        if state.bracket != nil {
            items.append(PadItem("board") { onBracket() })
        }
        PadFocus.shared.set(items, back: { onBack() })
    }

    // MARK: - The clear left

    /// Copy only, all of it down the left edge, so the machine behind it is never read through the
    /// words: the chevron and the tier line on one row, the circuit, and one dim line.
    private var left: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.tier.title.uppercased())
                .font(Stage.display(30))
                .kerning(Stage.Tracking.display(30))
                .foregroundStyle(Stage.type)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(color: Stage.ink.opacity(0.6), radius: 10, y: 2)

            housekeeping
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 340, alignment: .leading)
    }

    /// The five circuits as one line of words, the wall where the gates put it.
    private var tierItems: [TierLine.Item] {
        CareerTier.allCases.map { tier in
            TierLine.Item(
                id: tier.rawValue,
                title: tier.title,
                current: tier == state.tier,
                locked: !gates.tierAvailable(tier),
                wallBefore: gates.firstLockedTier == tier
            )
        }
    }

    /// "Record 5 of 6 · 900 scrap · Tinribs, 89.5 kg", and the scrap in the scrap colour.
    private var housekeeping: Text {
        var line = dim("Record \(state.wins) of \(state.fightsPlayed)")
        line = line + dim(" · ")
        line = line + Text("\(state.scrap) scrap")
            .font(Stage.body(13))
            .foregroundStyle(Stage.scrap)
        if let bot {
            line = line + dim(" · \(bot.name), \(BuildRules.kilograms(bot.totalWeight))")
        }
        return line
    }

    private func dim(_ text: String) -> Text {
        Text(text)
            .font(Stage.body(13))
            .foregroundStyle(Stage.typeDim)
    }

    // MARK: - The season, in the one column on the right

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let next {
                NextFightCard(
                    next: next,
                    canFight: canFight,
                    gatingLine: gatingLine,
                    repairsOutstanding: repairsOutstanding,
                    onScout: onScout,
                    onFight: onFight,
                    onGarage: onGarage,
                    onRepair: { showingRepairs = true; PadFocus.shared.pushContext() }
                )
            } else {
                seasonPanel
            }

            if let bracket = state.bracket {
                BracketStrip(bracket: bracket, tier: state.tier, onOpen: onBracket)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The one line under FIGHT when the tie cannot be taken. Plain words, danger colour.
    private var gatingLine: String? {
        if let fault = bot?.fitnessFault {
            return "\(fault). Repair it for \(next?.repairsDue ?? repairsOutstanding) before the tie, or send another machine."
        }
        if !(bot?.isValid ?? false) {
            return "Your machine is not legal. Fix it in the garage before the tie."
        }
        return nil
    }

    // MARK: - No tie to fight: the same panel, the same one primary

    /// Season over, season taken and season not entered all read the same way: one panel, one
    /// primary, the reasons as plain lines (design system section 8).
    private var seasonPanel: some View {
        GlassPanel(padding: 12) {
            VStack(alignment: .leading, spacing: 7) {
                PanelLabel("Career ·", accent: state.tier.title)

                Text(seasonHeadline.uppercased())
                    .font(Stage.display(24))
                    .kerning(Stage.Tracking.display(24))
                    .foregroundStyle(Stage.type)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                ForEach(seasonLines, id: \.self) { line in
                    Text(line)
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.typeDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                MoneySentence(seasonMoney)

                StageButton(
                    seasonOver && !tookTheTier ? "Re-enter for \(fee)" : "Enter for \(fee)",
                    kind: .primary,
                    enabled: canAfford && (bot?.isValid ?? false),
                    focusID: "enter",
                    action: onEnter
                )
                .padding(.top, 4)

                if !canAfford {
                    Text("You need \(fee - state.scrap) more scrap for the entry fee. Win a quick fight.")
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !(bot?.isValid ?? false) {
                    Text("Your machine is not legal. Fix it in the garage before you enter.")
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                CardLinks(
                    repairsOutstanding: repairsOutstanding,
                    onGarage: onGarage,
                    onRepair: { showingRepairs = true; PadFocus.shared.pushContext() }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var seasonHeadline: String {
        if tookTheTier { return "\(state.seasonTally.tier.title) taken" }
        if seasonOver { return "Season over" }
        return "Enter the \(state.tier.title)"
    }

    private var seasonLines: [String] {
        if tookTheTier {
            var lines = state.seasonTally.summaryLines
            if state.seasonTally.tier != state.tier {
                lines.append("You are in the \(state.tier.title) now.")
            }
            return lines
        }
        if seasonOver {
            return ["You are out of the \(state.tier.title). The board played itself out without you."]
        }
        return ["The \(state.tier.title) is eight machines and three rounds. \(arenaLine)"]
    }

    private var seasonMoney: [MoneyClause] {
        var clauses = [MoneyClause(tookTheTier || seasonOver ? "Next entry" : "Entry", fee, tint: canAfford ? Stage.type : Stage.danger)]
        if !tookTheTier {
            clauses.append(MoneyClause("The final pays", CareerEngine.purse(state.tier, round: CareerBracket.rounds - 1), tint: Stage.scrap))
        }
        if repairsOutstanding > 0 {
            clauses.append(MoneyClause("Repairs owing", repairsOutstanding, tint: Stage.danger))
        }
        return clauses
    }

    private var arenaLine: String {
        guard let entry = CareerCatalogue.shared.tier(state.tier) else { return "" }
        let names = entry.arenas.map { Catalogue.shared.arena($0)?.name ?? $0 }
        let where_ = names.count > 1 ? names.joined(separator: " and ") : (names.first ?? "The Yard")
        return "Fought in \(where_)."
    }

    // MARK: - The ticker

    /// The season news, one idea a line, in the same band the menu uses.
    private var tickerLines: [String] {
        var lines: [String] = []
        if let next {
            lines.append("NEXT UP, \(next.roundTitle.uppercased()): \(next.opponent.name.uppercased()), RUN BY \(next.opponent.roboteer.uppercased()).")
            lines.append("\(next.arenaName.uppercased()). HOUSE BOT ON DUTY: \(next.houseBotName.uppercased()).")
        } else if tookTheTier {
            lines.append("YOU TOOK THE \(state.seasonTally.tier.title.uppercased()).")
        } else if seasonOver {
            lines.append("THE BOARD PLAYED ITSELF OUT. ENTER THE NEXT SEASON WHEN YOU ARE READY.")
        } else {
            lines.append("NO SEASON ENTERED. EIGHT MACHINES, THREE ROUNDS, ONE PURSE.")
        }
        lines.append("RECORD \(state.wins) OF \(state.fightsPlayed). \(state.scrap) SCRAP IN HAND.")
        return lines
    }
}

// MARK: - The next fight card

/// The one boxed panel on the season screen: who is in the other corner, where it is fought, who
/// guards the house bot's corner, the money as one sentence, and FIGHT inside the card. Garage and
/// the repair bill are text links under it, because that is what they are.
struct NextFightCard: View {

    let next: NextFight
    var canFight: Bool = true
    /// The one line under FIGHT when the tie cannot be taken.
    var gatingLine: String? = nil
    var repairsOutstanding: Int = 0

    var onScout: () -> Void
    var onFight: () -> Void = {}
    var onGarage: () -> Void = {}
    var onRepair: () -> Void = {}

    var body: some View {
        GlassPanel(padding: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    PanelLabel("Next fight ·", accent: next.roundTitle)
                    Spacer(minLength: 4)
                    TextLink("Scouting ›", tint: Stage.line, focusID: "scout", action: onScout)
                }

                HStack(alignment: .center, spacing: 9) {
                    LiverySwatch(hex: next.opponent.liveryHex, size: 18)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(next.opponent.name.uppercased())
                            .font(Stage.display(26))
                            .kerning(Stage.Tracking.display(26))
                            .foregroundStyle(Stage.type)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(opponentLine)
                            .font(Stage.body(13))
                            .foregroundStyle(Stage.typeDim)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    Spacer(minLength: 0)
                }

                Text("\(next.arenaName). House bot on duty: \(next.houseBotName.asName).")
                    .font(Stage.body(13))
                    .foregroundStyle(Stage.type)
                    .fixedSize(horizontal: false, vertical: true)

                MoneySentence(money)

                StageButton("Fight", kind: .primary, enabled: canFight, focusID: "fight", action: onFight)
                    .padding(.top, 4)

                if let gatingLine {
                    Text(gatingLine)
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                CardLinks(repairsOutstanding: repairsOutstanding, onGarage: onGarage, onRepair: onRepair)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Dot Ferris · Box, 4WD, Axe · 90.4 kg", as one dim line.
    private var opponentLine: String {
        "\(next.opponent.roboteer) · \(next.partsLine) · \(BuildRules.kilograms(BuildRules.totalWeight(next.opponent.spec)))"
    }

    private var money: [MoneyClause] {
        var clauses = [
            MoneyClause("Entry paid", next.entryFee, tint: Stage.type),
            MoneyClause(next.isFinal ? "The final pays" : "A win pays", next.purse, tint: Stage.scrap)
        ]
        if next.repairsDue > 0 {
            clauses.append(MoneyClause("Repairs owing", next.repairsDue, tint: Stage.danger))
        }
        return clauses
    }
}

/// The two text links under the one primary: the garage, and the bill when there is one.
struct CardLinks: View {

    let repairsOutstanding: Int
    var onGarage: () -> Void
    var onRepair: () -> Void

    var body: some View {
        HStack(spacing: 22) {
            Spacer(minLength: 0)
            TextLink("Garage", focusID: "garage", action: onGarage)
            if repairsOutstanding > 0 {
                TextLink("Repair for \(repairsOutstanding)", tint: Stage.danger, focusID: "repairs", action: onRepair)
            }
            Spacer(minLength: 0)
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
