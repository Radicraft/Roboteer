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
            if newPath.isEmpty {
                host.showStage(bot: stageBot())
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

    // MARK: - The menu

    private var menu: some View {
        ZStack {
            StageBackdrop(host: host, still: .withBot, dim: 0.18)
            StageScrim()

            HStack(alignment: .top, spacing: 28) {
                title
                Spacer(minLength: 8)
                buttons
            }
            .padding(.horizontal, 34)
            .padding(.top, 26)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { focusItems() }
        .onChange(of: selected?.isValid ?? false) { _, _ in focusItems() }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ROBOTEER")
                .font(Stage.display(54, weight: .black))
                .kerning(2)
                .foregroundStyle(Stage.text)
                .shadow(color: .black.opacity(0.6), radius: 12, y: 2)

            Rectangle()
                .fill(Stage.text.opacity(0.85))
                .frame(width: 74, height: 3)

            if let selected {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selected.name.uppercased())
                        .font(Stage.display(20))
                        .kerning(1.2)
                        .foregroundStyle(Stage.text)
                    Text("\(BuildRules.kilograms(selected.totalWeight)). \(selected.partsLine).")
                        .font(Stage.label(13))
                        .foregroundStyle(Stage.textDim)
                    if !selected.isValid {
                        Text(BuildRules.errors(selected.spec).first ?? "")
                            .font(Stage.label(12))
                            .foregroundStyle(Stage.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .shadow(color: .black.opacity(0.7), radius: 8, y: 1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 14) {
                Text(host.arenaReady ? "Arena ready." : "Arena loading.")
                    .font(Stage.label(11))
                    .foregroundStyle(Stage.textFaint)
                PadHintBar(showsBack: false)
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
    }

    /// One of the four quiet buttons under the three big ones.
    private struct MenuChip: Identifiable {
        let id: String
        let title: String
        let route: Route
    }

    /// The quiet row, left to right. The bridge spike is a diagnostic screen, not a mode, so it
    /// only appears with `-showSpike`.
    private var chips: [MenuChip] {
        var items = [
            MenuChip(id: "events", title: "Events", route: .events),
            MenuChip(id: "ladder", title: "Ladder", route: .ladder),
            MenuChip(id: "replays", title: "Replays", route: .replays),
            MenuChip(id: "settings", title: "Settings", route: .settings)
        ]
        if ArenaHost.hasLaunchFlag("-showSpike") {
            items.append(MenuChip(id: "spike", title: "Spike", route: .spike))
        }
        return items
    }

    /// S6 (stage 6): three ways into the game, and one quiet row for everything else.
    ///
    /// Eight full sized buttons needed about 438 pt of the 356 pt this column has on a 402 pt
    /// screen, which pushed SETTINGS off the bottom. Three big ones and a row of four quiet ones
    /// is about 204 pt, so it fits the smallest landscape iPhone with room to spare and every
    /// mode is still one press from the menu.
    private var buttons: some View {
        VStack(alignment: .trailing, spacing: 12) {
            VStack(alignment: .trailing, spacing: 10) {
                StageButton("Fight", enabled: selected?.isValid ?? false, focusID: "fight") {
                    askQuickFight()
                }
                StageButton("Career", kind: .primary, focusID: "career") { path.append(.career) }
                StageButton("Workshop", focusID: "workshop") { path.append(.workshop) }
            }
            .frame(width: 250)

            HStack(spacing: 6) {
                ForEach(chips) { chip in
                    StageButton(chip.title, kind: .quiet, focusID: chip.id) {
                        path.append(chip.route)
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            Spacer(minLength: 0)
        }
        .frame(width: 336, alignment: .trailing)
    }

    /// What the pad can land on here: down the three big ones, then left to right along the quiet
    /// row. Re registered whenever the FIGHT button changes state.
    private func focusItems() {
        var items = [
            PadItem("fight", enabled: selected?.isValid ?? false) { askQuickFight() },
            PadItem("career") { path.append(.career) },
            PadItem("workshop") { path.append(.workshop) }
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
        host.sendWorkshopConfig(bot)
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
            || ArenaHost.hasLaunchFlag("-autoFight") {
            coach.finish()
        }
        if loadedFixture, path.isEmpty {
            path = [.career]
        } else if ArenaHost.hasLaunchFlag("-autoCareer"), path.isEmpty {
            path = [.career]
        } else if ArenaHost.hasLaunchFlag("-autoWorkshop"), path.isEmpty {
            path = [.workshop]
        } else if ArenaHost.hasLaunchFlag("-autoFight"), path.isEmpty {
            path = [.fight]
        }
    }
}
