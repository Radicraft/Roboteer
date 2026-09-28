//
//  MenuView.swift
//  The root of the app: the stage, and the menus drawn in front of it.
//
//  The Broadcast system (docs/design-system.md), and section 8's hierarchy rules: one hero per
//  screen, at most two boxed panels, navigation that is not the hero is a text link. The menu is
//  option M1 of docs/look/menus-options.html, chosen by the owner on 2026-09-16.
//

import SwiftUI
import SwiftData

/// The whole window: one live Godot view at the back, every screen in front of it.
struct RootView: View {
    @Bindable var host: ArenaHost

    private var settings: RoboteerSettings { RoboteerSettings.shared }

    var body: some View {
        ZStack {
            Stage.ground.ignoresSafeArea()
            GodotSurface(host: host)
            // Built from the first frame, so the QA flags that open a screen still navigate
            // underneath, but not shown until the loading screen hands over to it.
            MenuView(host: host)
                .opacity(host.preloadDone ? 1 : 0)
            // The loading screen, in front of everything, until the arena has read and drawn
            // its whole catalogue once (docs/stage-bug-2026-09-21.md). The menu is built
            // underneath it the whole time, so when this goes there is nothing left to wait
            // for: the machine is already on the turntable.
            if !host.preloadDone {
                LoadingView(host: host)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: host.preloadDone)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear { startInput() }
    }

    /// The pad and the settings are wired once, here, because both outlive every screen.
    private func startInput() {
        // L6 (stage 6): Game Center identity and any ladder results left by other players.
        GameCenterService.shared.start()
        LadderService.shared.start()

        // P6 (stage 6): the one purchase. Settles the entitlement from the local receipt and
        // starts the `Transaction.updates` listener. Idempotent, and it touches no UI.
        StoreService.shared.start()

        ControllerObserver.shared.start()
        ControllerObserver.shared.beginNavigation { event in
            // A fight belongs to the arena: libgodot reads the same pad through GameController and
            // the menus must not answer for it.
            guard host.surface == .stage else { return }
            PadFocus.shared.handle(event)
        }

        settings.onChange = { changed in
            host.sendSettings(changed.dictionary)
        }
        // Queues until `arena_ready` and goes out the moment it lands.
        host.sendSettings(settings.dictionary)
    }
}

struct MenuView: View {

    enum Route: Hashable {
        case career
        // L6 (stage 6): the async ladder.
        case ladder
        // S6 (stage 6): the five side events, and the replay archive.
        case events
        case replays
        case workshop
        case builder(PersistentIdentifier)
        case fight
        case test
        case spike
        case settings
    }

    @Bindable var host: ArenaHost
    @Environment(\.modelContext) private var context
    @Query(sort: \BotBuild.createdAt, order: .forward) private var builds: [BotBuild]
    @State private var path: [Route] = []
    @State private var didHandleLaunchArguments = false
    /// S6 (stage 6): the first launch flow, Build then Test then Fight.
    @State private var coach = OnboardingCoach.shared
    /// The quick fight card: where, who and how many, asked before the fight starts.
    @State private var showingQuickFight = false
    @State private var quickChoice: QuickFightChoice?
    @Query private var careers: [CareerState]

    private var selected: BotBuild? { Garage.selected(from: builds) }

    var body: some View {
        NavigationStack(path: $path) {
            menu
                // Both the root and every destination have to let the arena through: the one
                // Godot view sits BELOW this stack and UIKit paints an opaque black behind
                // navigation content on iOS 18 (docs/simulator-rendering.md).
                .lettingTheArenaThrough()
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                        .lettingTheArenaThrough()
                }
        }
        .tint(Stage.text)
        // S6 (stage 6): the welcome panels and the coaching callouts sit above every screen,
        // including a pushed one, so one overlay covers the whole flow.
        .overlay { onboarding }
        .sheet(isPresented: $showingQuickFight) {
            QuickFightPicker(
                host: host,
                bot: selected,
                tier: careers.first?.tier ?? .regional,
                onFight: { choice in
                    quickChoice = choice
                    showingQuickFight = false
                    path.append(.fight)
                },
                onCancel: { showingQuickFight = false }
            )
        }
        .onAppear { start() }
        // Bug 1 (docs/aaa/frontend-meta.md): the full game bought or restored while a save stands
        // at the wall carries the career on into the next Series.
        .onChange(of: StoreService.shared.isUnlocked) { _, unlocked in
            if unlocked { CareerStore.advanceSavedCareerPastWall(in: context) }
        }
        .onChange(of: stageKey) { _, _ in sendStage() }
        .onChange(of: path) { _, newPath in
            // Back at the menus: the arena has been showing the fight, so put the stage back.
            // `showStage` cannot carry the framing, so it brings the surface back with nothing on
            // it and the bot follows one line later, framed at 28 % across like every other screen.
            if newPath.isEmpty {
                host.showStage(bot: nil)
                sendStage()
            }
            // S6 (stage 6): every advance in the first launch flow is a screen change.
            coach.noteScreen(screenName(newPath))
            announceStageScreen(newPath)
        }
        // Wave C: the quick fight card is its own stage screen while it is up.
        .onChange(of: showingQuickFight) { _, showing in
            guard path.isEmpty else { return }
            host.enterStageScreen(showing ? "quick" : "menu")
        }
    }

    // MARK: - Onboarding (S6, stage 6)

    @ViewBuilder
    private var onboarding: some View {
        let screen = screenName(path)
        if coach.step == .welcome {
            OnboardingWelcome(
                onBuild: {
                    coach.startBuilding()
                    path = [.workshop]
                },
                onSkip: { coach.finish() }
            )
            .onAppear {
                PadFocus.shared.set([
                    PadItem("welcome-build") {
                        coach.startBuilding()
                        path = [.workshop]
                    },
                    PadItem("welcome-skip") { coach.finish() }
                ])
            }
            .onDisappear { focusItems() }
        } else if let text = coach.callout(on: screen) {
            OnboardingCallout(
                text: text,
                actionTitle: coach.calloutAction(on: screen)?.title,
                onAction: { onboardingAction(screen) },
                onDismiss: { coach.hideCallout() }
            )
        }
    }

    /// What the callout's button does: the next thing the player is being asked to do.
    private func onboardingAction(_ screen: String) {
        switch coach.step {
        case .build:
            path = [.workshop, .test]
        case .fight:
            if selected?.isValid == true {
                askQuickFight()
            } else if screen != "workshop" {
                path = [.workshop]
            }
        default:
            break
        }
    }

    /// Wave C: tell the stage which screen is in front of it, for the routes that do not say so
    /// themselves. The builder names its tab, the career names each of its screens, the workshop
    /// sends its own machine, and a fight owns the view.
    private func announceStageScreen(_ path: [Route]) {
        guard let route = path.last else { return }
        switch route {
        case .ladder: host.enterStageScreen("ladder")
        case .events: host.enterStageScreen("events")
        case .replays: host.enterStageScreen("replays")
        case .settings: host.enterStageScreen("settings")
        case .workshop: host.enterStageScreen("workshop")
        case .career, .builder, .fight, .test, .spike: break
        }
    }

    /// The name of the screen the player is on, as the coach knows it.
    private func screenName(_ path: [Route]) -> String {
        guard let route = path.last else { return "menu" }
        switch route {
        case .career: return "career"
        case .ladder: return "ladder"
        case .events: return "events"
        case .replays: return "replays"
        case .workshop: return "workshop"
        case .builder: return "builder"
        case .fight: return "fight"
        case .test: return "test"
        case .spike: return "spike"
        case .settings: return "settings"
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .career:
            CareerRootView(host: host)
        case .ladder:
            LadderView(host: host)
        // S6 (stage 6).
        case .events:
            EventsRootView(host: host)
        case .replays:
            ReplaysRootView(host: host)
        case .workshop:
            WorkshopView(host: host, onBuild: { build in path.append(.builder(build.persistentModelID)) },
                         onTest: { path.append(.test) },
                         onFight: { askQuickFight() })
        case .builder(let id):
            BuilderView(host: host, buildID: id)
        case .fight:
            FightView(host: host, mode: .fight, choice: quickChoice) { path.removeAll() }
        case .test:
            FightView(host: host, mode: .test) { path.removeAll() }
        case .spike:
            ContentView(host: host)
        case .settings:
            SettingsView(host: host)
        }
    }

    // MARK: - The menu (direction A, docs/look/menus-blueprint.html, wave C)

    /// Where the menu's plates are, so the leader tags stay clear of them.
    @State private var keepOut = LeaderKeepOut()

    /// Direction A's main menu: the wordmark top left, the machine large on the left of the stage
    /// with its weapon, drive and top armour called out by leader lines, a title block under it,
    /// and one column on the right: the scrap block, the career plate with CONTINUE CAREER as the
    /// only primary, the numbered rows for the other modes and the quiet links at the foot.
    ///
    /// The column is on the RIGHT because this is a stage screen: the owner has to be able to see
    /// his own machine (docs/stage4-swift-notes.md), and the stage frames it in the clear left.
    private var menu: some View {
        ZStack {
            StageBackdrop(host: host, still: .withBot, dim: 0, keyArt: "menu_keyart", shade: .right)

            // The welcome owns the screen while it is up: the menu's own buttons showing through
            // it read as tappable and are not (owner's screenshot, 2026-09-14).
            if coach.step != .welcome {
                StageLeaderLayer(anchors: host.stageAnchors, screen: "menu",
                                 leaders: menuLeaders, keepOut: keepOut)

                GeometryReader { proxy in
                    let compact = proxy.size.height < 400
                    HStack(alignment: .top, spacing: 16) {
                        // The copy sits ON the turntable's area rather than in the way of it: the
                        // pad is underneath and takes the drags the words ignore.
                        ZStack(alignment: .topLeading) {
                            StageOrbitPad(host: host)
                            leftColumn(compact: compact)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        rightColumn(compact: compact)
                            .frame(width: min(354, (proxy.size.width * 0.425).rounded()))
                    }
                    .padding(.top, compact ? 12 : 18)
                    .padding(.bottom, compact ? 4 : 10)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { focusItems() }
        .onChange(of: selected?.isValid ?? false) { _, _ in focusItems() }
    }

    /// The wordmark, the one warning a machine can carry, and the title block at the foot.
    private func leftColumn(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BlueprintWordmark(size: 30)
                .leaderKeepOut(keepOut, "wordmark")

            if let selected, !selected.isValid {
                Text(BuildRules.errors(selected.spec).first ?? "")
                    .font(Blueprint.body(14))
                    .foregroundStyle(Blueprint.danger)
                    .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320, alignment: .leading)
                    .leaderKeepOut(keepOut, "warning")
            }

            Spacer(minLength: 0)

            // "Arena loading." is the only half of this a player needs; it goes the moment there
            // is nothing to wait for (wave P, agent H).
            HStack(spacing: 14) {
                if !host.arenaReady {
                    Text("Arena loading.")
                        .font(Blueprint.ui(12))
                        .foregroundStyle(Blueprint.dim)
                }
                PadHintBar(showsBack: false)
            }

            if !titleCells.isEmpty {
                BlueprintTitleBlock(cells: titleCells, cellWidth: compact ? 84 : 90, height: compact ? 48 : 52)
                    .fixedSize()
                    .leaderKeepOut(keepOut, "title")
            }
        }
    }

    /// The title block: the drawing's own data, from the machine and the career. Nothing invented.
    private var titleCells: [BlueprintTitleBlock.Cell] {
        guard let selected else { return [] }
        var cells = [
            BlueprintTitleBlock.Cell(label: "Machine", value: selected.name),
            BlueprintTitleBlock.Cell(label: "Mass", value: BuildRules.kilograms(selected.totalWeight))
        ]
        if let career = careers.first {
            cells.append(BlueprintTitleBlock.Cell(label: "Level", value: "\(career.level)"))
            cells.append(BlueprintTitleBlock.Cell(label: "Record", value: "\(career.wins) of \(career.fightsPlayed)"))
        } else if let weapon = Catalogue.shared.weapon(selected.weaponID) {
            cells.append(BlueprintTitleBlock.Cell(label: "Weapon", value: weapon.name))
        }
        return cells
    }

    /// The scrap block, the career plate, the numbered rows and the quiet links.
    private func rightColumn(compact: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            BlueprintScrapBlock(amount: scrap)
                .leaderKeepOut(keepOut, "scrap")

            careerCard(compact: compact)
                .padding(.top, compact ? 8 : 12)
                .leaderKeepOut(keepOut, "career")

            modeRows(compact: compact)
                .padding(.top, 8)
                .leaderKeepOut(keepOut, "rows")

            Spacer(minLength: 0)

            quietRow
                .leaderKeepOut(keepOut, "quiet")
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// What the player has to spend, from the career. Nil careers read as nothing rather than
    /// hiding the number, so the top right of the menu never changes shape.
    private var scrap: Int { careers.first?.scrap ?? 0 }

    // MARK: - The one card

    /// The menu leads with what happens next: a plate naming the next career fight with one
    /// button to continue it. A player with no season reads the same plate asking them to start
    /// one (design system section 8).
    private func careerCard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(careerLabel)
                .font(Blueprint.ui(12))
                .foregroundStyle(Blueprint.dim)
                .lineLimit(1)
            Text(careerHeadline)
                .font(Blueprint.display(25))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 5)
                .padding(.bottom, 6)
            careerLine
            StageButton(careers.first == nil ? "Start your career" : "Continue career", kind: .primary, focusID: "career") {
                path.append(.career)
            }
            .padding(.top, compact ? 10 : 14)
        }
        .padding(.horizontal, 16)
        .padding(.top, compact ? 11 : 14)
        .padding(.bottom, compact ? 14 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .blueprintPlate()
    }

    /// Quick fight, Workshop and Events as the numbered rows of one plate (the career is 01).
    private func modeRows(compact: Bool) -> some View {
        let height: CGFloat = compact ? 32 : 36
        return VStack(spacing: 0) {
            BlueprintMenuRow(number: 2, title: "Quick fight", enabled: selected?.isValid ?? false,
                             focusID: "fight", height: height) { askQuickFight() }
            BlueprintRule()
            BlueprintMenuRow(number: 3, title: "Workshop", focusID: "workshop", height: height) {
                path.append(.workshop)
            }
            BlueprintRule()
            BlueprintMenuRow(number: 4, title: "Events", focusID: "events", height: height) {
                path.append(.events)
            }
        }
        .padding(.vertical, compact ? 4 : 6)
        .blueprintPlate()
    }

    /// "Career. Series 2, match 3": the career plate's label.
    private var careerLabel: String {
        let accent = careerAccent
        return accent.isEmpty ? "Career" : "Career. \(accent)"
    }

    // MARK: - The leaders

    /// Weapon, drive and top armour, named and weighed from the machine on the turntable.
    private var menuLeaders: [Leader] {
        guard let selected else { return [] }
        let catalogue = Catalogue.shared
        var out: [Leader] = []
        if let weapon = catalogue.weapon(selected.weaponID) {
            out.append(Leader(id: "weapon", target: .partOrPoint("weapon", "weapon"),
                              title: weapon.name, value: BuildRules.kilograms(weapon.weight), dx: 41, dy: -36))
        }
        if let drive = catalogue.drive(selected.driveID) {
            out.append(Leader(id: "drive", target: .kind("wheel", prefer: ["wheel_fl", "wheel_rl", "track_l"]),
                              title: drive.name, value: BuildRules.kilograms(drive.weight), dx: -50, dy: 72))
        }
        let material = catalogue.material(selected.topMaterial)?.name ?? selected.topMaterial.capitalized
        out.append(Leader(id: "top", target: .partOrPoint("armour_top", "top"),
                          title: "\(material) top",
                          value: selected.topThickness == 1 ? "1 unit" : "\(selected.topThickness) units",
                          dx: 54, dy: -68))
        return out
    }

    /// The next career match, worked out in the one place the career works it out, so the menu and
    /// the Series screen cannot disagree about who is next or what a win pays (wave P).
    private var nextMatch: NextMatch? {
        guard let career = careers.first else { return nil }
        return ProgressionEngine.nextMatch(state: career, playerBot: selected)
    }

    /// "SERIES 2, MATCH 3", the bright half of the card's label.
    private var careerAccent: String {
        guard let career = careers.first else { return "" }
        guard let match = nextMatch else { return ProgressionEngine.seriesLine(career.seriesIndex) }
        return match.isReplay ? "Replay, \(match.title)" : match.title
    }

    private var careerHeadline: String {
        guard let career = careers.first else { return "Start your career" }
        if let match = nextMatch { return "\(match.opponent.name) is next" }
        if career.campaignComplete { return "The campaign is yours" }
        // The engine refuses the match when the Series is behind the full game's wall, so the
        // menu has to say why rather than claim the Series was won.
        if ProgressionEngine.isBehindWall(state: career) {
            return "Series \(career.seriesIndex + 1) needs the full game"
        }
        return "Series \(career.seriesIndex + 1) taken"
    }

    /// One dim line under the headline. The money in it is the only coloured thing.
    @ViewBuilder
    private var careerLine: some View {
        if let match = nextMatch {
            let rules = match.scrapRules
            let most = rules.base + rules.damageFull + rules.survivor + rules.flawless
            MoneySentence(
                [MoneyClause("\(match.arenaName). \(match.houseBotName.asName) on duty. A win pays up to", most, tint: Color.white)],
                size: 14,
                tint: Color.white
            )
        } else if let career = careers.first, career.campaignComplete {
            Text(ProgressionEngine.isBehindWall(state: career)
                 ? "Every Series is won. Nothing you have won is lost: replaying a match needs the full game."
                 : "Every Series is won. Replay any match you have won from the board. A replay pays half.")
                .font(Blueprint.body(14))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
        } else if let career = careers.first, ProgressionEngine.isBehindWall(state: career) {
            Text("The free game is Series 1 and Series 2. Nothing is lost: unlock the full game and this career carries on from here.")
                .font(Blueprint.body(14))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
        } else if let career = careers.first {
            MoneySentence(
                [MoneyClause("Every match won so far. You are at Level", career.level, tint: Color.white)],
                size: 14,
                tint: Color.white
            )
        } else {
            Text("Five Series, four matches each, one Level bar that never stops.")
                .font(Blueprint.body(14))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One of the quiet text buttons at the bottom right.
    private struct MenuChip: Identifiable {
        let id: String
        let title: String
        let route: Route
    }

    /// The quiet row, left to right. The bridge spike is a diagnostic screen, not a mode, so it
    /// only appears with `-showSpike`.
    private var chips: [MenuChip] {
        var items = [
            MenuChip(id: "ladder", title: "Ladder", route: .ladder),
            MenuChip(id: "replays", title: "Replays", route: .replays),
            MenuChip(id: "settings", title: "Settings", route: .settings)
        ]
        if ArenaHost.hasLaunchFlag("-showSpike") {
            items.append(MenuChip(id: "spike", title: "Spike", route: .spike))
        }
        return items
    }

    /// The ladder, the replays and the settings as small links, bottom right, so the quietest
    /// corner of the menu stays quiet (design system section 8).
    private var quietRow: some View {
        HStack(spacing: 26) {
            Spacer(minLength: 0)
            ForEach(chips) { chip in
                TextLink(chip.title, focusID: chip.id) {
                    path.append(chip.route)
                }
            }
        }
    }

    /// The season news the ticker carries. Plain sentences in capitals, one idea each, and never a
    /// placeholder: with no career yet it says what the game is rather than nothing.
    private var tickerLines: [String] {
        var lines: [String] = []
        if let career = careers.first {
            lines.append("\(ProgressionEngine.seriesLine(career.seriesIndex).uppercased()). LEVEL \(career.level). \(career.scrap) SCRAP IN HAND.")
            if let match = nextMatch {
                lines.append("NEXT UP, \(match.title.uppercased()): \(match.opponent.name.uppercased()), RUN BY \(match.opponent.roboteer.uppercased()).")
            } else if career.campaignComplete {
                lines.append("EVERY SERIES WON. ANY MATCH CAN BE REPLAYED FOR HALF.")
            } else {
                lines.append("ALL FOUR MATCHES WON. THE NEXT SERIES IS WAITING.")
            }
            lines.append("RECORD \(career.wins) OF \(career.fightsPlayed). \(career.blueprints.count) PARTS OWNED.")
        } else {
            lines.append("BUILD A MACHINE, TEST IT, THEN TAKE IT INTO SERIES ONE.")
        }
        if let selected {
            lines.append("IN THE GARAGE: \(selected.name.uppercased()), \(BuildRules.kilograms(selected.totalWeight)).")
        }
        lines.append("ONE ROUND OF THREE MINUTES. THE HOUSE BOT COMES OUT AT TWO.")
        return lines
    }

    /// What the pad can land on here: the one card's button, down the text list, then left to
    /// right along the quiet row. Re registered whenever QUICK FIGHT changes state.
    private func focusItems() {
        var items = [
            PadItem("career") { path.append(.career) },
            PadItem("fight", enabled: selected?.isValid ?? false) { askQuickFight() },
            PadItem("workshop") { path.append(.workshop) },
            PadItem("events") { path.append(.events) }
        ]
        items.append(contentsOf: chips.map { chip in
            PadItem(chip.id) { path.append(chip.route) }
        })
        PadFocus.shared.set(items)
    }

    // MARK: - Quick fight

    /// Every way into a quick fight comes through here, so the card is never skipped.
    private func askQuickFight() {
        guard selected?.isValid == true else { return }
        showingQuickFight = true
    }

    // MARK: - The stage

    /// The bot configuration the stage should be showing, as the arena wants it.
    private func stageBot() -> [String: Any]? {
        guard let selected else { return nil }
        return selected.toBotConfig(id: FightConfigFixture.playerID, controller: "player")
    }

    /// A cheap value that changes whenever the stage would look different.
    private var stageKey: String {
        guard let bot = stageBot() else { return "" }
        return JSONText.string(from: bot)
    }

    private func sendStage() {
        // The loading screen names the machine the stage is about to build.
        if let selected {
            let machine = LoadingMachine(build: selected)
            if host.loadingMachine != machine { host.loadingMachine = machine }
        }
        // While the scouting report is up the stage belongs to the opponent's machine, so a change
        // in the player's own build must not push it off.
        guard let bot = stageBot(), host.surface == .stage, !host.scoutingOpponent else { return }
        // Wave C: on the menu itself the stage is told it is the menu; from a pushed screen the
        // machine changes and the screen in front keeps its own name.
        if path.isEmpty {
            host.sendWorkshopConfig(bot, frame: StageLayout.botFrame,
                                    screen: showingQuickFight ? "quick" : "menu")
        } else {
            host.sendWorkshopConfig(bot, frame: StageLayout.botFrame)
        }
    }

    private func start() {
        guard !didHandleLaunchArguments else { return }
        didHandleLaunchArguments = true
        // `-career <fixture.json>` replaces the whole garage and career with a saved one, so it
        // runs before the garage would seed itself.
        let loadedFixture = CareerStore.loadFixtureIfRequested(in: context)
        CareerStore.advanceSavedCareerPastWall(in: context)
        Garage.prepare(context: context)
        sendStage()
        // S6 (stage 6): `-resetOnboarding` puts the first launch flow back to the welcome panels.
        coach.begin()
        coach.noteScreen(screenName(path))

        // QA flags, all kept from Stage 3. S6: any of them means this is not a first launch, so
        // the welcome panels stay out of the way of whatever is being tested.
        if !ArenaHost.hasLaunchFlag("-resetOnboarding"),
           loadedFixture
            || ArenaHost.hasLaunchFlag("-autoCareer")
            || ArenaHost.hasLaunchFlag("-autoWorkshop")
            || ArenaHost.hasLaunchFlag("-autoBuilder")
            || ArenaHost.hasLaunchFlag("-autoTest")
            || ArenaHost.hasLaunchFlag("-autoFight")
            || ArenaHost.hasLaunchFlag("-autoEvents")
            || ArenaHost.hasLaunchFlag("-autoReplays")
            || ArenaHost.hasLaunchFlag("-autoLadder")
            || ArenaHost.hasLaunchFlag("-autoSettings")
            || ArenaHost.hasLaunchFlag("-autoQuickFight")
            // Wave P: the career's own screens, so a shop or board screenshot is not taken through
            // the welcome panel.
            || ArenaHost.hasLaunchFlag("-autoShop")
            || ArenaHost.hasLaunchFlag("-autoBoard") {
            coach.finish()
        }
        // The QA routes are pushed one beat later: a path set in the stack's own first onAppear
        // was sometimes dropped, which left a `-career ... -autoBoard` launch on the menu (wave C
        // captures, 2026-09-28).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            openLaunchRoute(loadedFixture: loadedFixture)
        }
    }

    /// The screen a QA launch flag asked for (docs/qa-launch-flags.md).
    private func openLaunchRoute(loadedFixture: Bool) {
        // `-stayOnMenu` (QA): the fixture is loaded but the menu stays in front, so the menu, the
        // workshop and the builder can be photographed with the fixture's career behind them.
        if loadedFixture, path.isEmpty, !ArenaHost.hasLaunchFlag("-stayOnMenu") {
            path = [.career]
        } else if ArenaHost.hasLaunchFlag("-autoCareer"), path.isEmpty {
            path = [.career]
        } else if ArenaHost.hasLaunchFlag("-autoWorkshop"), path.isEmpty {
            path = [.workshop]
        // The builder is only ever reached through the workshop, so the route is the real one a
        // player takes: back from the builder lands in the workshop, not on the menu.
        } else if ArenaHost.hasLaunchFlag("-autoBuilder"), path.isEmpty {
            // `selected` comes from a @Query that has not necessarily refreshed since
            // `Garage.prepare` seeded the first build one line ago, so ask the context itself.
            let seeded = (try? context.fetch(FetchDescriptor<BotBuild>())) ?? []
            if let build = selected ?? Garage.selected(from: seeded) {
                path = [.workshop, .builder(build.persistentModelID)]
            } else {
                path = [.workshop]
            }
        } else if ArenaHost.hasLaunchFlag("-autoTest"), path.isEmpty {
            path = [.test]
        } else if ArenaHost.hasLaunchFlag("-autoFight"), path.isEmpty {
            path = [.fight]
        // V3 (wave V): the rest of the package, so every screen's layout can be photographed on a
        // headless simulator without a thumb. Presentation only; none of them changes any flow.
        } else if ArenaHost.hasLaunchFlag("-autoEvents"), path.isEmpty {
            path = [.events]
        } else if ArenaHost.hasLaunchFlag("-autoReplays"), path.isEmpty {
            path = [.replays]
        } else if ArenaHost.hasLaunchFlag("-autoLadder"), path.isEmpty {
            path = [.ladder]
        } else if ArenaHost.hasLaunchFlag("-autoSettings"), path.isEmpty {
            path = [.settings]
        }
        // The quick fight card is a sheet over the menu rather than a route, so it is raised
        // instead of pushed.
        if ArenaHost.hasLaunchFlag("-autoQuickFight"), path.isEmpty, selected?.isValid == true {
            showingQuickFight = true
        }
    }
}
