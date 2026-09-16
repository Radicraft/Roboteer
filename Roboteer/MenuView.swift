//
//  MenuView.swift
//  The root of the app: the stage, and the menus drawn in front of it.
//
//  AAA cinematic, per docs/stage2-art-direction.md "Owner decision 2026-09-13": the player's own
//  bot under moving stage lights with dry ice behind dark glass panels, bold condensed white
//  capitals, gold for scrap and winner marks only.
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
            MenuView(host: host)
        }
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

    // MARK: - The menu (design system section 5)

    private static let gutter: CGFloat = 30

    /// The broadcast package. The title as display type top left, the scrap bug top right, four
    /// lower-third buttons and the quiet text row in the one column on the right, and the ticker
    /// with the season news along the bottom.
    ///
    /// The buttons sit in the RIGHT column rather than under the title, because this is a stage
    /// screen: the player's machine stands at `StageLayout.botFrame` (28 % across) and the left
    /// 45 % of the screen stays clear of chrome. That rule came from the owner not being able to
    /// see his own machine (docs/stage4-swift-notes.md) and it outranks the sketch in section 5.
    private var menu: some View {
        ZStack {
            StageBackdrop(host: host, still: .withBot, dim: 0.18, keyArt: "menu_keyart")
            StageScrim()

            // The welcome owns the screen while it is up: the menu's own buttons showing through
            // it read as tappable and are not (owner's screenshot, 2026-09-14).
            if coach.step != .welcome {
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        HStack(alignment: .top, spacing: 20) {
                            // The title is copy, so it sits ON the turntable's area rather than in
                            // the way of it: the pad is underneath and takes the drags the words
                            // ignore.
                            ZStack {
                                StageOrbitPad(host: host)
                                title
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            Spacer(minLength: 8)
                            rightColumn
                                .frame(width: StageLayout.columnWidth(proxy.size.width - 2 * Self.gutter))
                        }
                        .padding(.top, 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                        // The strip is the width of the SCREEN, not the width of the safe area, so
                        // it reads as a broadcast band rather than a floating box. The words keep
                        // the gutter.
                        Ticker(lines: tickerLines, textInset: Self.gutter)
                            .padding(.horizontal, -Self.gutter)
                            .ignoresSafeArea(edges: .horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, Self.gutter)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { focusItems() }
        .onChange(of: selected?.isValid ?? false) { _, _ in focusItems() }
    }

    /// The title block. Every word of it is in the top quarter of the screen and nothing is wider
    /// than 320 pt, because the machine stands at 28 % across and the copy used to run straight
    /// over its chest.
    private var title: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ROBOTEER")
                .font(Stage.display(44))
                .kerning(Stage.Tracking.display(44))
                .foregroundStyle(Stage.type)
                .shadow(color: Stage.ink.opacity(0.7), radius: 12, y: 2)

            Rectangle()
                .fill(Stage.line)
                .frame(width: 72, height: 3)

            if let selected {
                LowerThird(entersFrom: .leading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(selected.name.uppercased())
                            .font(Stage.display(20))
                            .kerning(Stage.Tracking.display(20))
                            .foregroundStyle(Stage.type)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("\(BuildRules.kilograms(selected.totalWeight)). \(selected.partsLine).")
                            .font(Stage.label(11))
                            .kerning(Stage.Tracking.label(11))
                            .foregroundStyle(Stage.typeDim)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                if !selected.isValid {
                    Text(BuildRules.errors(selected.spec).first ?? "")
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.danger)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            // The one line that may sit low: it is under the machine's feet, small and quiet.
            HStack(spacing: 14) {
                Text(host.arenaReady ? "Arena ready." : "Arena loading.")
                    .font(Stage.label(11))
                    .kerning(Stage.Tracking.label(11))
                    .foregroundStyle(Stage.textFaint)
                PadHintBar(showsBack: false)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: 320, alignment: .leading)
    }

    /// The scrap bug, the four buttons and the quiet row, top to bottom on the right.
    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ScoreBug(label: "Scrap", value: "\(scrap)", tint: Stage.scrap, size: 22)
            }

            buttons

            Spacer(minLength: 0)

            quietRow
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// What the player has to spend, from the career. Nil careers read as nothing rather than
    /// hiding the bug, so the top right of the menu never changes shape.
    private var scrap: Int { careers.first?.scrap ?? 0 }

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

    /// Four lower thirds, stacked. CAREER is the primary, so it is 1.5x the height of the rest.
    private var buttons: some View {
        VStack(alignment: .trailing, spacing: 8) {
            StageButton("Career", kind: .primary, focusID: "career") { path.append(.career) }
            StageButton("Quick fight", enabled: selected?.isValid ?? false, focusID: "fight") {
                askQuickFight()
            }
            StageButton("Workshop", focusID: "workshop") { path.append(.workshop) }
            StageButton("Events", focusID: "events") { path.append(.events) }
        }
        .frame(maxWidth: 270)
    }

    /// Settings, replays and the ladder as label-size text buttons rather than plates, so the
    /// bottom right of the menu stays quiet (design system section 5).
    private var quietRow: some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)
            ForEach(chips) { chip in
                MenuTextButton(title: chip.title, focusID: chip.id) {
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
            lines.append("\(career.tier.title.uppercased()) CIRCUIT. \(career.scrap) SCRAP IN HAND.")
            if let bracket = career.bracket, let opponent = bracket.playerNextOpponent,
               let match = bracket.playerMatch {
                lines.append("NEXT UP, \(CareerBracket.roundTitle(match.round, of: CareerBracket.rounds).uppercased()): \(opponent.name.uppercased()), RUN BY \(opponent.roboteer.uppercased()).")
            } else if career.bracket != nil {
                lines.append("THE BOARD PLAYED ITSELF OUT. ENTER THE NEXT SEASON WHEN YOU ARE READY.")
            } else {
                lines.append("NO SEASON ENTERED. EIGHT MACHINES, THREE ROUNDS, ONE PURSE.")
            }
            lines.append("RECORD \(career.wins) OF \(career.fightsPlayed). \(career.blueprints.count) BLUEPRINTS IN THE FOLDER.")
        } else {
            lines.append("BUILD A MACHINE, TEST IT, THEN TAKE IT ON THE CIRCUIT.")
        }
        if let selected {
            lines.append("IN THE GARAGE: \(selected.name.uppercased()), \(BuildRules.kilograms(selected.totalWeight)).")
        }
        lines.append("ONE ROUND OF THREE MINUTES. THE HOUSE BOT COMES OUT AT TWO.")
        return lines
    }

    /// What the pad can land on here: down the four buttons, then left to right along the quiet
    /// row. Re registered whenever the QUICK FIGHT button changes state.
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
        // While the scouting report is up the stage belongs to the opponent's machine, so a change
        // in the player's own build must not push it off.
        guard let bot = stageBot(), host.surface == .stage, !host.scoutingOpponent else { return }
        host.sendWorkshopConfig(bot, frame: StageLayout.botFrame)
    }

    private func start() {
        guard !didHandleLaunchArguments else { return }
        didHandleLaunchArguments = true
        // `-career <fixture.json>` replaces the whole garage and career with a saved one, so it
        // runs before the garage would seed itself.
        let loadedFixture = CareerStore.loadFixtureIfRequested(in: context)
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
            || ArenaHost.hasLaunchFlag("-autoQuickFight") {
            coach.finish()
        }
        if loadedFixture, path.isEmpty {
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

// MARK: - The quiet corner

/// A text button: label capitals with a `line` bar that appears when a pad lands on it. No plate,
/// because the bottom right of the menu is the quietest part of the broadcast package.
private struct MenuTextButton: View {

    let title: String
    let focusID: String
    var action: () -> Void

    private var focused: Bool { PadFocus.shared.isFocused(focusID) }

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(Stage.label(12))
                .kerning(Stage.Tracking.label(12))
                .foregroundStyle(focused ? Stage.type : Stage.typeDim)
                .lineLimit(1)
                .fixedSize()
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Stage.line)
                        .frame(height: 2)
                        .opacity(focused ? 1 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
