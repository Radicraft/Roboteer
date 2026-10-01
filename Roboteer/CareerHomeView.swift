//
//  CareerHomeView.swift
//  CAREER, as five Series you can see (brief v5 sections 2, 4 and 9.4).
//
//  The home screen IS the Series screen, drawn as option S1 of docs/look/series-options.html: the
//  back chevron and the five Series as one line of words across the top, the scrap top right, the
//  Level bar as a full width rule under them, the Series in display type on the left with one dim
//  line of housekeeping, ONE panel on the right holding the next match with FIGHT inside it, and
//  the four matches as a strip under the panel with the campaign board one tap away. Garage,
//  Repair and Shop are text links, because that is what they are (design system section 8).
//
//  `CareerRootView` owns the whole loop: fight -> `CareerStore.settleMatch` -> the match report ->
//  the rewards on a win or the retry prompt on a loss or a draw -> back here. There is no entry
//  fee, no purse and no bracket: money comes from brief v5 section 3 and parts come from the shop.
//
//  Layout rule (docs/stage4-swift-notes.md, docs/stage5-swift-notes.md): the left of the screen
//  belongs to the live machine, framed at `StageLayout.botFrame`, and every panel goes in the one
//  column on the right.
//

import SwiftUI
import SwiftData

/// Everything one career match needs to be fought, held while the arena is busy with it.
struct PendingCareerMatch {
    let botID: PersistentIdentifier
    /// The card the player read before pressing FIGHT. The fight config is built from it, so what
    /// was promised on the card and what the arena is told cannot drift apart.
    let next: NextMatch
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
    @Query(sort: \FightLog.date, order: .reverse) private var logs: [FightLog]

    enum Screen {
        case home
        case board
        case scouting
        case fight
        case report
        case rewards
        case retry
        case garage
        case shop
        /// Owner decision 8: the daily seeded exhibition, once the campaign is won.
        case daily
    }

    @State private var screen: Screen = .home
    @State private var chosenID: PersistentIdentifier?
    @State private var pending: PendingCareerMatch?
    /// What the match just fought did. The report is shown first, always; the rewards only on a win.
    @State private var report: MatchReport?
    @State private var rewards: Rewards?
    @State private var settledBotID: PersistentIdentifier?
    @State private var didPrepare = false
    /// P6 (stage 6): the one moment the game brings the wall up by itself. Set when a Series final
    /// is won and the next Series is behind it, shown after the player has had their rewards.
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
                        Text("Opening the campaign.")
                            .font(Stage.label(14))
                            .foregroundStyle(Stage.text)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            prepare()
            announceStage(screen)
        }
        .onChange(of: screen) { _, now in announceStage(now) }
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
                next: nextMatch(state),
                gates: Gates.snapshot,
                stable: living,
                // The strip follows the match on duty, not the campaign's own place. Replaying
                // Series 1 match 2 used to print the CURRENT Series' four matches under a card
                // about somewhere else (wave P, agent B2's note).
                slots: ProgressionEngine.seriesSlots(
                    state: state,
                    seriesIndex: ProgressionEngine.pending(state).seriesIndex,
                    logs: logs),
                onFight: { startFight(state) },
                onBoard: { go(.board) },
                onScout: { go(.scouting) },
                onGarage: { go(.garage) },
                onShop: { go(.shop) },
                onDaily: PostCampaign.dailyAvailable(state: state) ? { go(.daily) } : nil,
                onRepair: { build in repairFromHome(build, state: state) },
                canPatch: canPatch(chosen, state: state),
                onPatch: { build in patch(build, state: state) },
                onReplay: { index in
                    replay(state,
                           seriesIndex: ProgressionEngine.pending(state).seriesIndex,
                           matchIndex: index)
                },
                onCancelReplay: { CareerStore.cancelReplay(state: state, in: context) },
                onUnlock: { showingUnlock = true },
                onBack: { leave() }
            )
        case .board:
            CampaignBoardView(
                host: host,
                state: state,
                logs: logs,
                next: nextMatch(state),
                bot: chosen,
                canFight: canTakeMatch(state),
                onFight: { startFight(state) },
                onReplay: { series, match in replay(state, seriesIndex: series, matchIndex: match) },
                onUnlock: { showingUnlock = true },
                onBack: { go(.home) }
            )
        case .scouting:
            if let next = nextMatch(state) {
                ScoutingView(
                    host: host,
                    opponent: next.opponent,
                    builds: builds,
                    record: CareerStore.record(for: next.opponent.rivalID, in: context),
                    scrap: state.scrap,
                    next: next,
                    chosenID: $chosenID,
                    owned: state.blueprints,
                    onFight: { startFight(state) },
                    onBack: { go(.home) }
                )
            } else {
                nothingToFight
            }
        case .fight:
            if let pending {
                CareerFightView(
                    host: host,
                    playerConfig: pending.playerConfig,
                    opponentConfig: pending.opponentConfig,
                    arena: pending.next.arena,
                    seed: pending.seed,
                    next: pending.next
                ) { result, json in
                    settle(state, result: result, json: json)
                }
            } else {
                nothingToFight
            }
        case .report:
            if let report {
                MatchReportView(host: host, report: report, matchTitle: settledTitle) {
                    readTheReport(state)
                }
            } else {
                nothingToFight
            }
        case .rewards:
            if let rewards {
                RewardsView(host: host, rewards: rewards, matchTitle: settledTitle) {
                    finishMatch(state)
                }
            } else {
                nothingToFight
            }
        case .retry:
            if let report {
                RetryPromptView(
                    host: host,
                    report: report,
                    repairBill: settledBill,
                    scrap: state.scrap,
                    matchTitle: settledTitle,
                    attempts: state.attempts,
                    retryBlock: retryBlock(state),
                    repairClearsBlock: retryOwnershipAndLegal(state),
                    onPatchAndRetry: canPatch(settledBot ?? chosen, state: state)
                        ? { patchAndRetry(state) } : nil,
                    onRetry: { retry(state, repairing: false) },
                    onRepairAndRetry: { retry(state, repairing: true) },
                    onGarage: {
                        finishMatch(state)
                        go(.garage)
                    }
                )
            } else {
                nothingToFight
            }
        case .garage:
            CareerGarageView(host: host, state: state, builds: builds) { go(.home) }
        case .shop:
            ShopView(host: host, state: state) { go(.home) }
        case .daily:
            DailyExhibitionView(host: host, state: state, bot: chosen) { go(.home) }
        }
    }

    /// Nothing to fight and nothing to show: one sentence and the way back, never a dead screen.
    private var nothingToFight: some View {
        ZStack {
            StageBackdrop(host: host, still: .empty, dim: 0.42)
            VStack(spacing: 12) {
                Text("There is no match waiting.")
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

    /// "Series 2, match 3": the match just fought, for the three post-match screens (B1's
    /// amendment in docs/wave-p-contracts.md).
    private var settledTitle: String { pending?.next.title ?? "" }

    /// Why RETRY cannot send the machine straight back (bug 4), or nil. The same three checks
    /// `startFight` makes, so an enabled RETRY always starts a fight.
    private func retryBlock(_ state: CareerState) -> String? {
        guard let bot = settledBot ?? chosen else { return "There is no machine to send. Build one in the garage." }
        return ProgressionEngine.retryBlock(
            fault: bot.fitnessFault,
            legal: bot.isValid,
            ownership: ProgressionEngine.ownershipFault(in: bot.spec, owned: state.blueprints),
            repairBill: settledBill.total,
            scrap: state.scrap,
            canPatch: canPatch(bot, state: state)
        )
    }

    /// Is some OTHER living machine fit to fight, legal and fully owned.
    private func otherFitMachine(than bot: BotBuild, state: CareerState) -> Bool {
        living.contains { other in
            other.persistentModelID != bot.persistentModelID && other.isValid && other.fitnessFault == nil
                && ProgressionEngine.ownershipFault(in: other.spec, owned: state.blueprints) == nil
        }
    }

    /// Owner decision 1: the free emergency patch-up is offered when the player is stranded.
    private func canPatch(_ bot: BotBuild?, state: CareerState) -> Bool {
        guard let bot else { return false }
        return ProgressionEngine.emergencyPatchAllowed(
            fault: bot.fitnessFault,
            repairBill: CareerEngine.repairBill(for: bot.spec, damage: bot.currentDamage).total,
            scrap: state.scrap,
            otherFitMachine: otherFitMachine(than: bot, state: state))
    }

    private func patch(_ bot: BotBuild, state: CareerState) {
        CareerStore.emergencyPatch(bot, state: state, otherFitMachine: otherFitMachine(than: bot, state: state),
                                   in: context)
    }

    private func patchAndRetry(_ state: CareerState) {
        guard let bot = settledBot ?? chosen else { return }
        patch(bot, state: state)
        report = nil
        rewards = nil
        pending = nil
        startFight(state)
    }

    /// True when the only thing wrong is damage, so paying the bill makes the retry possible.
    private func retryOwnershipAndLegal(_ state: CareerState) -> Bool {
        guard let bot = settledBot ?? chosen else { return false }
        return bot.isValid && ProgressionEngine.ownershipFault(in: bot.spec, owned: state.blueprints) == nil
    }

    /// What the machine that just fought still owes, for the retry prompt.
    private var settledBill: RepairBill {
        guard let bot = settledBot ?? chosen else { return RepairBill() }
        return CareerEngine.repairBill(for: bot.spec, damage: bot.currentDamage)
    }

    /// The next match as one value: who, where, which house bot, what a win pays and what the
    /// chosen machine still owes. Everything the card prints and everything the config sends.
    private func nextMatch(_ state: CareerState) -> NextMatch? {
        let rivalID = ProgressionEngine.opponentRivalID(state: state)
        return ProgressionEngine.nextMatch(
            state: state,
            playerBot: chosen,
            record: CareerStore.record(for: rivalID, in: context)
        )
    }

    /// The same checks `startFight` makes, so an enabled FIGHT on the board always starts one.
    private func canTakeMatch(_ state: CareerState) -> Bool {
        guard let bot = chosen, bot.isValid, bot.fitnessFault == nil,
              ProgressionEngine.ownershipFault(in: bot.spec, owned: state.blueprints) == nil else { return false }
        return nextMatch(state) != nil
    }

    // MARK: - The stage's screen (wave C, docs/wave-c-menus-notes.md)

    /// The `screen` the stage is told for each career screen. The fight, the scouting report and
    /// the daily exhibition put their own machines on the view.
    private func stageName(_ screen: Screen) -> String? {
        switch screen {
        case .home: return "career"
        case .board: return "board"
        case .garage: return "garage"
        case .shop: return "shop"
        case .report: return "result"
        case .rewards: return "rewards"
        case .retry: return "retry"
        case .scouting, .fight, .daily: return nil
        }
    }

    /// The opponent across the floor on the board, built as the fight will build it.
    private func boardOpponent() -> [String: Any]? {
        guard let state, let next = nextMatch(state) else { return nil }
        return next.opponent.spec.toBotConfig(id: CareerFightConfig.opponentID, controller: "ai")
    }

    /// Tell the stage which career screen is in front of it, with the board's opponent and the
    /// result's win cue. Deduped by the host, so saying it on appear and on every change is free.
    private func announceStage(_ screen: Screen) {
        guard let name = stageName(screen) else { return }
        host.enterStageScreen(name, focus: name == "shop" ? ShopView.stageFocus : nil,
                              opponent: screen == .board ? boardOpponent() : nil,
                              cue: screen == .report && report?.isWin == true ? "win" : nil)
    }

    // MARK: - Navigation

    private func go(_ next: Screen) {
        // Bug 6: the screen being left must not keep its pad items. Every career screen registers
        // its own on appear; the fight registers none, because the pad belongs to the arena.
        if next != screen { PadFocus.shared.clear() }
        screen = next
        if next != .fight, next != .scouting, next != .daily {
            restoreStage(for: next)
        }
    }

    /// The player's own machine goes back on the stage whenever the career is not looking at
    /// somebody else's, framed at 28 % across so it stands clear of the career's panels rather
    /// than behind them. `showStage` cannot carry the framing, so it brings the surface back with
    /// nothing on it and the machine follows.
    private func restoreStage(for next: Screen? = nil) {
        guard let bot = chosen else { return }
        host.showStage(bot: nil)
        if let next, let name = stageName(next) {
            host.sendWorkshopConfig(
                bot.toBotConfig(id: CareerFightConfig.playerID, controller: "player"),
                frame: StageLayout.botFrame,
                screen: name,
                focus: name == "shop" ? ShopView.stageFocus : nil,
                opponent: next == .board ? boardOpponent() : nil,
                cue: next == .report && report?.isWin == true ? "win" : nil
            )
        } else {
            host.sendWorkshopConfig(
                bot.toBotConfig(id: CareerFightConfig.playerID, controller: "player"),
                frame: StageLayout.botFrame
            )
        }
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
            // One runloop later, so the career store has settled before the match is started.
            DispatchQueue.main.async { startFight(state) }
        } else if ArenaHost.hasLaunchFlag("-autoBoard") || ArenaHost.hasLaunchFlag("-autoBracket") {
            screen = .board
        } else if ArenaHost.hasLaunchFlag("-autoScouting") {
            screen = .scouting
        } else if ArenaHost.hasLaunchFlag("-autoCareerGarage") {
            screen = .garage
        } else if ArenaHost.hasLaunchFlag("-autoShop") {
            screen = .shop
        }
    }

    // MARK: - The match

    /// FIGHT. The card has already said who, where, what a win pays and which house bot is on duty.
    private func startFight(_ state: CareerState) {
        // Bug 3: a career match is fought only with parts the career owns, checked here as well
        // as on the card, because a machine can carry a part from before the builder locked it.
        guard let bot = chosen, bot.isValid, bot.fitnessFault == nil,
              ProgressionEngine.ownershipFault(in: bot.spec, owned: state.blueprints) == nil,
              let next = nextMatch(state) else { return }
        pending = PendingCareerMatch(
            botID: bot.persistentModelID,
            next: next,
            seed: next.seed(careerSeed: state.currentSeasonSeed),
            playerConfig: bot.toBotConfig(id: CareerFightConfig.playerID, controller: "player"),
            opponentConfig: next.opponent.spec.toBotConfig(id: CareerFightConfig.opponentID, controller: "ai")
        )
        report = nil
        rewards = nil
        go(.fight)
    }

    /// The arena has answered. Everything one settled match does to the career happens in
    /// `CareerStore.settleMatch`; this only decides which screen reads it out.
    private func settle(_ state: CareerState, result: FightResult?, json: String) {
        guard let pending, let bot = builds.first(where: { $0.persistentModelID == pending.botID }) else {
            go(.home)
            return
        }
        settledBotID = bot.persistentModelID
        let settled = CareerStore.settleMatch(
            state: state,
            bot: bot,
            next: pending.next,
            result: result,
            resultJSON: json,
            in: context
        )
        report = settled.report
        rewards = settled.rewards
        // The final was won and the next Series is behind the wall. Remember it; the offer comes
        // once the player has read their rewards.
        if settled.rewards?.hitTheWall == true, Gates.shouldOfferAfterRegionalFinal {
            wallOfferWaiting = true
        }
        go(.report)
    }

    /// The match report has been read. A win goes on to the rewards; a loss or a draw goes to the
    /// retry prompt (brief v5 sections 2 and 9.4).
    private func readTheReport(_ state: CareerState) {
        go(rewards == nil ? .retry : .rewards)
    }

    /// Back to the Series screen, always: the next-match card and the strip are what have to
    /// update after a match.
    private func finishMatch(_ state: CareerState) {
        report = nil
        rewards = nil
        pending = nil
        go(.home)
        offerTheUnlockIfOwed()
    }

    /// The retry prompt, which replays the SAME match on a new seed (brief v5 section 9.1). The
    /// attempt count has already been bumped by `settleMatch`, and the seed follows from it.
    private func retry(_ state: CareerState, repairing: Bool) {
        if repairing, let bot = settledBot ?? chosen {
            CareerStore.repair(bot, bill: CareerEngine.repairBill(for: bot.spec, damage: bot.currentDamage),
                               state: state, in: context)
        }
        report = nil
        rewards = nil
        pending = nil
        startFight(state)
    }

    /// Replay a match already won, once the campaign is finished or the next Series is behind the
    /// wall. The Series screen picks the replay up as the match on duty.
    private func replay(_ state: CareerState, seriesIndex: Int, matchIndex: Int) {
        guard CareerStore.startReplay(state: state, seriesIndex: seriesIndex,
                                      matchIndex: matchIndex, in: context) else { return }
        go(.home)
    }

    /// The Repair link on the Series screen. Same call the garage makes, so there is one place a
    /// bill is paid.
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

// MARK: - The Series screen (option S1, docs/look/series-options.html)

/// One screen, one hero. Across the top: the chevron, the five Series as one line of words, and
/// the scrap. Under them the Level bar, full width, as a rule. The left is copy only. The right is
/// ONE panel, the next match, with FIGHT inside it and everything else demoted to a text link.
/// Under the panel the Series is a strip of four matches plus the one after it, and the campaign
/// board is one tap away (design system section 8).
struct CareerHomeView: View {

    @Bindable var host: ArenaHost
    let state: CareerState
    let bot: BotBuild?
    /// Nil when the Series is finished: the campaign is over, or the next Series is behind the wall.
    let next: NextMatch?
    let gates: Gates
    /// Every machine that is not written off, for the Repairs sheet.
    let stable: [BotBuild]
    /// The four matches of the Series being shown, from the engine.
    let slots: [SeriesMatchSlot]

    var onFight: () -> Void
    var onBoard: () -> Void
    var onScout: () -> Void
    var onGarage: () -> Void
    var onShop: () -> Void
    /// Owner decision 8: the daily exhibition, offered as a text link once the campaign is won.
    var onDaily: (() -> Void)? = nil
    var onRepair: (BotBuild) -> Void
    /// Owner decision 1: the chosen machine is stranded (unfit, bill over the bank, nothing else
    /// fit), so the crew offers a free patch-up to 25 %.
    var canPatch: Bool = false
    var onPatch: (BotBuild) -> Void = { _ in }
    var onReplay: (Int) -> Void
    var onCancelReplay: () -> Void
    var onUnlock: () -> Void
    var onBack: () -> Void

    @State private var showingRepairs = false

    private var canFight: Bool {
        next != nil && (bot?.isValid ?? false) && bot?.fitnessFault == nil && ownershipFault == nil
    }

    /// Bug 3: a part on the machine the career does not own (an armour material fitted before the
    /// builder locked them). Nil when everything on it is the player's.
    private var ownershipFault: String? {
        guard let bot else { return nil }
        return ProgressionEngine.ownershipFault(in: bot.spec, owned: state.blueprints)
    }
    private var seriesComplete: Bool { next == nil }
    private var canReplay: Bool { ProgressionEngine.replaysAvailable(state: state, gates: gates) }

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
            StageBackdrop(host: host, still: .withBot, dim: 0, shade: .right)

            GeometryReader { proxy in
                VStack(spacing: 0) {
                    // The chevron, the five Series and the scrap run across the top of the screen,
                    // clear of both columns: five words need the room and neither column has it.
                    HStack(alignment: .center, spacing: 2) {
                        BackChevron(action: onBack)
                        SeriesLine(items: seriesItems)
                        Spacer(minLength: 8)
                        scrapCorner
                    }

                    // Both progression tracks, read in one glance: the Series as words above, the
                    // Level as a rule (brief v5 section 2).
                    LevelBar(level: state.levelState)
                        .padding(.top, 7)
                        .padding(.bottom, 3)

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
        .onChange(of: canFight) { _, _ in registerFocus() }
        .onChange(of: state.matchIndex) { _, _ in registerFocus() }
        .onChange(of: state.replayMatchIndex) { _, _ in registerFocus() }
    }

    /// What the pad can land on here (docs/stage4-swift-notes.md, agent S2's `PadFocus`). Every
    /// action on the screen is in this list, links included, because a link is a button now.
    private func registerFocus() {
        guard !showingRepairs else { return }
        var items: [PadItem] = []
        if next != nil {
            items.append(PadItem("fight", enabled: canFight) { onFight() })
            if canPatch, let bot {
                items.append(PadItem("patch") { onPatch(bot) })
            }
            items.append(PadItem("scout") { onScout() })
        } else if seriesComplete, lockedNext != nil {
            // Whatever the panel is saying, if it is offering the unlock as its one primary then
            // a pad has to be able to land on it. A finished campaign behind the wall offers it
            // too, for the replays (wave P, agent H).
            items.append(PadItem("unlock") { onUnlock() })
        }
        items.append(PadItem("garage") { onGarage() })
        items.append(PadItem("shop") { onShop() })
        if let onDaily { items.append(PadItem("daily") { onDaily() }) }
        if repairsOutstanding > 0, !canPatch {
            items.append(PadItem("repairs") {
                showingRepairs = true
                PadFocus.shared.pushContext()
            })
        }
        items.append(PadItem("board") { onBoard() })
        PadFocus.shared.set(items, back: { onBack() })
    }

    // MARK: - The clear left

    /// Copy only, all of it down the left edge, so the machine behind it is never read through the
    /// words: the Series in display type, and one dim line.
    private var left: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ProgressionEngine.seriesLine(state.seriesIndex).uppercased())
                .font(Stage.display(30))
                .kerning(Stage.Tracking.display(30))
                .foregroundStyle(Stage.type)
                .lineLimit(1)
                .minimumScaleFactor(BroadcastType.floorScale(.display, size: 30, wanted: 0.6))
                .shadow(color: Stage.ink.opacity(0.6), radius: 10, y: 2)

            housekeeping
                .lineLimit(1)
                .minimumScaleFactor(BroadcastType.floorScale(.body, size: 13, wanted: 0.7))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: 340, alignment: .leading)
    }

    /// The scrap, top right, as a plain label and number (design system section 5).
    private var scrapCorner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("SCRAP")
                .font(Stage.label(11))
                .kerning(Stage.Tracking.label(11))
                .foregroundStyle(Stage.typeDim)
            Text("\(state.scrap)")
                .font(Stage.numerals(20))
                .figureLine(20)
                .foregroundStyle(Stage.scrap)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.scrap) scrap")
    }

    /// The five Series as one line of words, the wall where the gates put it.
    private var seriesItems: [TierLine.Item] {
        CareerTier.allCases.map { tier in
            TierLine.Item(
                id: tier.rawValue,
                title: tier.title,
                current: tier.index == state.seriesIndex,
                locked: !gates.tierAvailable(tier),
                wallBefore: gates.firstLockedTier == tier
            )
        }
    }

    /// "Record 6 of 8 · 640 scrap · Tinribs, 89.5 kg", and the scrap in the scrap colour.
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

    // MARK: - The Series, in the one column on the right

    private var rightColumn: some View {
        // The card and the strip as they are when they fit. When a long gating line makes the
        // card taller than a 402 pt phone can hold, the card scrolls inside its own room instead,
        // so it can never push the Series strip or the ticker off the foot of the screen (QA
        // 2026-09-25: the ticker was cut by the bottom edge).
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 8) {
                matchCard
                seriesStrip
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.vertical, showsIndicators: false) {
                    matchCard
                }
                .scrollBounceBehavior(.basedOnSize)
                seriesStrip
            }
        }
        .padding(.top, 2)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var seriesStrip: some View {
        SeriesStrip(
            slots: slots,
            seriesIndex: shownSeriesIndex,
            nextSeriesLocked: shownNextLocked,
            onOpen: onBoard,
            onReplay: canReplay ? onReplay : nil
        )
    }

    @ViewBuilder
    private var matchCard: some View {
        Group {
            if let next {
                NextMatchCard(
                    next: next,
                    canFight: canFight,
                    gatingLine: gatingLine,
                    onPatch: canPatch ? { if let bot { onPatch(bot) } } : nil,
                    repairsOutstanding: repairsOutstanding,
                    onScout: onScout,
                    onFight: onFight,
                    onGarage: onGarage,
                    onShop: onShop,
                    onDaily: onDaily,
                    onRepair: { showingRepairs = true; PadFocus.shared.pushContext() },
                    onCancelReplay: onCancelReplay
                )
            } else {
                completePanel
            }
        }
    }

    /// The one line under FIGHT when the match cannot be taken. Plain words, danger colour.
    private var gatingLine: String? {
        if let fault = bot?.fitnessFault {
            let bill = next?.repairsDue ?? repairsOutstanding
            if canPatch {
                return "\(fault). Repairs cost \(bill) and there is \(state.scrap) in the bank. The crew will patch it up to \(ProgressionEngine.emergencyPatchPercent)% for free."
            }
            return "\(fault). Repair it for \(bill) before the match, or send another machine."
        }
        if !(bot?.isValid ?? false) {
            return "Your machine is not legal. Fix it in the garage before the match."
        }
        return ownershipFault
    }

    /// The Series the strip under the card is about: the one being replayed while a replay is
    /// running, and the campaign's own otherwise.
    private var shownSeriesIndex: Int { ProgressionEngine.pending(state).seriesIndex }

    /// Is the Series AFTER the one on the strip behind the wall.
    private var shownNextLocked: Bool {
        let all = CareerTier.allCases
        guard shownSeriesIndex + 1 < all.count else { return false }
        return !gates.tierAvailable(all[shownSeriesIndex + 1])
    }

    /// True when the save is standing in a Series this entitlement does not open. The engine
    /// refuses the match (`ProgressionEngine.isBehindWall`); this is only how the screen says so.
    private var behindWall: Bool { ProgressionEngine.isBehindWall(state: state, gates: gates) }

    /// The Series that is behind the full game wall, else nil: the one the save is standing in
    /// when the entitlement has gone, otherwise the one after the one just finished.
    private var lockedNext: CareerTier? {
        if behindWall { return state.tier }
        guard let following = state.tier.next, !gates.tierAvailable(following) else { return nil }
        return following
    }

    // MARK: - No match to fight: the same panel, the same one primary

    /// The Series is finished. Either the campaign is done and everything can be replayed, or the
    /// next Series is behind the wall. One panel, one primary, the reasons as plain lines.
    private var completePanel: some View {
        GlassPanel(padding: 12) {
            VStack(alignment: .leading, spacing: 7) {
                PanelLabel("Career ·", accent: ProgressionEngine.seriesName(state.seriesIndex))

                Text(completeHeadline.uppercased())
                    .font(Stage.display(24))
                    .kerning(Stage.Tracking.display(24))
                    .foregroundStyle(Stage.type)
                    .lineLimit(1)
                    .minimumScaleFactor(BroadcastType.floorScale(.display, size: 24, wanted: 0.6))

                ForEach(completeLines, id: \.self) { line in
                    Text(line)
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.typeDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let locked = lockedNext {
                    StageButton("Unlock the full game", kind: .primary, focusID: "unlock", action: onUnlock)
                        .padding(.top, 4)
                    Text(state.campaignComplete
                         ? gates.lockedReason(.replays)
                         : gates.lockedReason(.tier(locked)))
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.typeDim)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    StageButton("Campaign board", kind: .primary, focusID: "board", action: onBoard)
                        .padding(.top, 4)
                }

                CardLinks(
                    repairsOutstanding: repairsOutstanding,
                    onGarage: onGarage,
                    onShop: onShop,
                    onRepair: { showingRepairs = true; PadFocus.shared.pushContext() },
                    onDaily: onDaily
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var completeHeadline: String {
        // A finished campaign is a finished campaign, whatever the entitlement says now. What a
        // player without one loses is the REPLAYS, not the twenty matches they won.
        if state.campaignComplete { return "The campaign is yours" }
        if behindWall { return "Series \(state.seriesIndex + 1) needs the full game" }
        return "Series \(state.seriesIndex + 1) taken"
    }

    private var completeLines: [String] {
        if state.campaignComplete, behindWall {
            return [
                "Every Series is won. Level \(state.level) of \(ProgressionEngine.progression.levelCap).",
                "Nothing you have won is lost. Replaying a match needs the full game."
            ]
        }
        if behindWall {
            return [
                "The free game is Series 1 and Series 2. This career is standing in Series \(state.seriesIndex + 1).",
                "Nothing is lost. Unlock the full game and it carries on from exactly here."
            ]
        }
        if state.campaignComplete {
            return [
                "Every Series is won. Level \(state.level) of \(ProgressionEngine.progression.levelCap).",
                "Replay any match you have won from the board. A replay pays half."
            ]
        }
        return [
            "You have won all four matches. Level \(state.level) of \(ProgressionEngine.progression.levelCap).",
            "Replay any match you have won from the board while you wait. A replay pays half."
        ]
    }

    // MARK: - The ticker

    /// The campaign news, one idea a line, in the same band the menu uses.
    /// The ticker carries what the screen does NOT already say. The card names the opponent, the
    /// arena, the house bot, the money and the Level, and the bar and the scrap bug print the
    /// rest, so the ticker used to be the card read out twice (wave P, agent B2's note). It is
    /// the season's talk now: what the other corner thinks, how far the Series has left to run,
    /// and the career's own record.
    private var tickerLines: [String] {
        var lines: [String] = []
        if let next {
            let talk = next.grudgeLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !talk.isEmpty { lines.append(talk.uppercased()) }
            lines.append(seriesRunLine(next))
        } else if state.campaignComplete {
            lines.append(behindWall
                ? "EVERY SERIES WON. REPLAYING A MATCH NEEDS THE FULL GAME."
                : "EVERY SERIES WON. REPLAY ANY MATCH FROM THE BOARD.")
        } else if behindWall {
            lines.append("SERIES \(state.seriesIndex + 1) NEEDS THE FULL GAME.")
        } else {
            lines.append("SERIES \(state.seriesIndex + 1) TAKEN. FOUR MATCHES, FOUR WINS.")
        }
        lines.append("RECORD \(state.wins) OF \(state.fightsPlayed). \(state.blueprints.count) PARTS OWNED.")
        return lines
    }

    /// "TWO MORE WINS TAKE SERIES 2." The card says which match this is; this says what is left
    /// of the Series, which it does not.
    private func seriesRunLine(_ next: NextMatch) -> String {
        if next.isReplay { return "A REPLAY PAYS HALF, OR IN FULL FOR A NEW MEDAL." }
        if case .defence(let number) = next.mode {
            return number == 1 ? "THE TITLE IS YOURS. NOW KEEP IT." : "DEFENCE \(number). THE REIGN SO FAR: \(number - 1)."
        }
        let left = SeriesProgress.matchesPerSeries - next.matchIndex
        let series = next.seriesNumber
        switch left {
        case 1: return "WIN THIS ONE AND SERIES \(series) IS YOURS."
        case 2: return "TWO MORE WINS TAKE SERIES \(series)."
        case 3: return "THREE MORE WINS TAKE SERIES \(series)."
        default: return "FOUR WINS TAKE SERIES \(series)."
        }
    }
}

/// The five Series as one line of words. `TierLine` draws it; this is the name the career screen
/// calls it by, so no screen has to say the word the player never reads.
typealias SeriesLine = TierLine

// MARK: - The next match card

/// The one boxed panel on the Series screen: which match this is, who is in the other corner,
/// where it is fought, who is guarding the house bot's corner, what a win pays as one sentence,
/// and FIGHT inside the card. Garage, Repair and Shop are text links under it.
struct NextMatchCard: View {

    let next: NextMatch
    var canFight: Bool = true
    /// The one line under FIGHT when the match cannot be taken.
    var gatingLine: String? = nil
    /// The free emergency patch-up, as a link under the gating line (owner decision 1).
    var onPatch: (() -> Void)? = nil
    var repairsOutstanding: Int = 0

    var onScout: () -> Void
    var onFight: () -> Void = {}
    var onGarage: () -> Void = {}
    var onShop: () -> Void = {}
    var onDaily: (() -> Void)? = nil
    var onRepair: () -> Void = {}
    var onCancelReplay: () -> Void = {}

    var body: some View {
        // Tight on purpose. Everything here has to fit ABOVE the Series strip, and the strip is
        // the one thing on this screen that says how far through the Series you are.
        GlassPanel(padding: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    PanelLabel(next.isReplay ? "Replay ·" : (next.isDefence ? "Defend the title ·" : "Next ·"),
                           accent: next.title)
                    Spacer(minLength: 4)
                    TextLink("Scouting ›", tint: Stage.line, focusID: "scout", action: onScout)
                }

                HStack(alignment: .center, spacing: 9) {
                    // The roboteer's own portrait (design system section 6). It stands in for
                    // nothing: the livery swatch is still there, because the swatch is the colour
                    // the machine is actually painted and the portrait is the person.
                    PortraitPlate(image: BroadcastArt.rival(next.opponent.rivalID), side: 38)
                    LiverySwatch(hex: next.opponent.liveryHex, size: 18)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(next.opponent.name.uppercased())
                            .font(Stage.display(23))
                            .kerning(Stage.Tracking.display(23))
                            .foregroundStyle(Stage.type)
                            .lineLimit(1)
                            .minimumScaleFactor(BroadcastType.floorScale(.display, size: 23, wanted: 0.6))
                        Text(opponentLine)
                            .font(Stage.body(13))
                            .foregroundStyle(Stage.typeDim)
                            .lineLimit(1)
                            .minimumScaleFactor(BroadcastType.floorScale(.body, size: 13, wanted: 0.65))
                    }
                    Spacer(minLength: 0)
                }

                // Where it is fought and who is guarding the corner: the arena's own key art as
                // a lower third, with the house bot's portrait against the trailing edge. It
                // costs 38 pt more than the sentence it replaces, which is what the Series strip
                // under this card can spare.
                ArenaBand(
                    arenaID: next.arena,
                    name: next.arenaName,
                    line: "House bot on duty: \(next.houseBotName.asName).",
                    portrait: BroadcastArt.boss(next.houseBotID),
                    height: 44
                )

                MoneySentence(money)

                StageButton("Fight", kind: .primary, enabled: canFight, focusID: "fight", action: onFight)
                    .padding(.top, 2)

                if let gatingLine {
                    Text(gatingLine)
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } else if next.attempts > 0, !next.isReplay, !next.isDefence {
                    // A replay's and a defence's `attempts` is the career's fight count (it only
                    // seeds the fight), so it is never read out as tries.
                    Text(attemptLine)
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.typeDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                CardLinks(
                    repairsOutstanding: repairsOutstanding,
                    onGarage: onGarage,
                    onShop: onShop,
                    onRepair: onRepair,
                    onPatch: onPatch,
                    onCancelReplay: next.isReplay ? onCancelReplay : nil,
                    onDaily: onDaily
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Dot Ferris · Box, 4WD, Axe · 90.4 kg", as one dim line.
    private var opponentLine: String {
        "\(next.opponent.roboteer) · \(next.partsLine) · \(BuildRules.kilograms(BuildRules.totalWeight(next.opponent.spec)))"
    }

    /// "Your second try at this one." A machine that has lost here is told so, plainly.
    private var attemptLine: String {
        switch next.attempts {
        case 1: return "Your second try at this one. The fight will not run the same way twice."
        case 2: return "Your third try at this one. The fight will not run the same way twice."
        default: return "Try number \(next.attempts + 1) at this one."
        }
    }

    /// Money is a sentence (design system section 8). The most a win can pay is every bonus of
    /// brief v5 section 3 at once, which is what "up to" means.
    private var money: [MoneyClause] {
        let rules = next.scrapRules
        let most = rules.base + rules.damageFull + rules.survivor + rules.flawless
        var clauses = [
            MoneyClause("A win pays up to", most, tint: Stage.scrap, tail: " scrap and"),
            MoneyClause("", next.winPoints, tint: Stage.line, tail: " points.")
        ]
        if next.repairsDue > 0 {
            clauses.append(MoneyClause("Repairs owing", next.repairsDue, tint: Stage.danger))
        }
        return clauses
    }
}

/// The text links under the one primary: the garage, the shop, the bill when there is one, and a
/// way out of a replay.
struct CardLinks: View {

    let repairsOutstanding: Int
    var onGarage: () -> Void
    var onShop: () -> Void = {}
    var onRepair: () -> Void
    /// Owner decision 1: when the machine is stranded, the free patch-up takes the repair link's
    /// place (a bill the bank cannot pay is not an action).
    var onPatch: (() -> Void)? = nil
    var onCancelReplay: (() -> Void)? = nil
    /// Owner decision 8: the daily exhibition, once the campaign is won.
    var onDaily: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 20) {
            Spacer(minLength: 0)
            TextLink("Garage", focusID: "garage", action: onGarage)
            if let onPatch {
                TextLink("Patch it up free", tint: Stage.line, focusID: "patch", action: onPatch)
            } else if repairsOutstanding > 0 {
                TextLink("Repair for \(repairsOutstanding)", tint: Stage.danger, focusID: "repairs", action: onRepair)
            }
            TextLink("Shop", tint: Stage.line, focusID: "shop", action: onShop)
            if let onDaily {
                TextLink("Daily", tint: Stage.line, focusID: "daily", action: onDaily)
            }
            if let onCancelReplay {
                TextLink("Leave the replay", focusID: "cancel-replay", action: onCancelReplay)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Repairs

/// The repairs sheet. One row per machine with what it still owes, so a bill can be cleared
/// without walking into the garage and back.
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
                    .minimumScaleFactor(BroadcastType.floorScale(.display, size: 13, wanted: 0.7))
                Text(bill.isPristine
                     ? "No damage."
                     : "\(Int((bill.fractionOfValue * 100).rounded()))% of its value.")
                    .font(Stage.body(13))
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
                                PlateRect().fill(scrap >= bill.total ? Stage.selectedFill : Stage.type.opacity(0.05))
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
            PlateRect()
                .fill(Stage.type.opacity(0.04))
        }
    }
}
