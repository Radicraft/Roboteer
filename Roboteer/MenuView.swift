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

    private var selected: BotBuild? { Garage.selected(from: builds) }

    var body: some View {
        NavigationStack(path: $path) {
            menu
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
        }
        .tint(Stage.text)
        .onAppear { start() }
        .onChange(of: stageKey) { _, _ in sendStage() }
        .onChange(of: path) { _, newPath in
            // Back at the menus: the arena has been showing the fight, so put the stage back.
            if newPath.isEmpty {
                host.showStage(bot: stageBot())
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .career:
            CareerRootView(host: host)
        case .workshop:
            WorkshopView(host: host, onBuild: { build in path.append(.builder(build.persistentModelID)) },
                         onTest: { path.append(.test) },
                         onFight: { path.append(.fight) })
        case .builder(let id):
            BuilderView(host: host, buildID: id)
        case .fight:
            FightView(host: host, mode: .fight) { path.removeAll() }
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

    private var buttons: some View {
        VStack(alignment: .trailing, spacing: 10) {
            StageButton("Career", kind: .primary, focusID: "career") { path.append(.career) }
            StageButton("Fight", enabled: selected?.isValid ?? false, focusID: "fight") {
                path.append(.fight)
            }
            StageButton("Workshop", focusID: "workshop") { path.append(.workshop) }
            StageButton("Bridge spike", focusID: "spike") { path.append(.spike) }
            Spacer(minLength: 0)
            // The dry ice is brightest at the bottom right, so the lowest button sits on glass.
            StageButton("Settings", kind: .glass, focusID: "settings") { path.append(.settings) }
        }
        .frame(width: 250)
    }

    /// What the pad can land on here. Re registered whenever the FIGHT button changes state.
    private func focusItems() {
        PadFocus.shared.set([
            PadItem("career") { path.append(.career) },
            PadItem("fight", enabled: selected?.isValid ?? false) { path.append(.fight) },
            PadItem("workshop") { path.append(.workshop) },
            PadItem("spike") { path.append(.spike) },
            PadItem("settings") { path.append(.settings) }
        ])
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

        // QA flags, all kept from Stage 3.
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
