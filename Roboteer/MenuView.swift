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

    var body: some View {
        ZStack {
            Stage.ground.ignoresSafeArea()
            GodotSurface(host: host)
            MenuView(host: host)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }
}

struct MenuView: View {

    enum Route: Hashable {
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

            Text(host.arenaReady ? "Arena ready." : "Arena loading.")
                .font(Stage.label(11))
                .foregroundStyle(Stage.textFaint)
        }
        .frame(maxWidth: 420, alignment: .leading)
    }

    private var buttons: some View {
        VStack(alignment: .trailing, spacing: 10) {
            StageButton("Fight", kind: .primary, enabled: selected?.isValid ?? false) {
                path.append(.fight)
            }
            StageButton("Workshop") { path.append(.workshop) }
            StageButton("Bridge spike") { path.append(.spike) }
            Spacer(minLength: 0)
            // The dry ice is brightest at the bottom right, so the lowest button sits on glass.
            StageButton("Settings", kind: .glass) { path.append(.settings) }
        }
        .frame(width: 250)
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
        guard let bot = stageBot(), host.surface == .stage else { return }
        host.sendWorkshopConfig(bot)
    }

    private func start() {
        guard !didHandleLaunchArguments else { return }
        didHandleLaunchArguments = true
        Garage.prepare(context: context)
        sendStage()

        // QA flags, all kept from Stage 3.
        if ArenaHost.hasLaunchFlag("-autoWorkshop"), path.isEmpty {
            path = [.workshop]
        } else if ArenaHost.hasLaunchFlag("-autoFight"), path.isEmpty {
            path = [.fight]
        }
    }
}

/// A placeholder until Stage 5 has something to put in it. It still says what the app knows.
struct SettingsView: View {

    @Bindable var host: ArenaHost
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            StageBackdrop(host: host, still: .empty, dim: 0.42)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    StageButton("Back", kind: .quiet) { dismiss() }
                        .frame(width: 110)
                    Text("SETTINGS")
                        .font(Stage.display(26))
                        .kerning(1.6)
                        .foregroundStyle(Stage.text)
                    Spacer()
                }

                GlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Settings arrive in a later stage.")
                            .font(Stage.label(15))
                            .foregroundStyle(Stage.text)
                        Text("Sound, haptics and control layout will live here.")
                            .font(Stage.body(12))
                            .foregroundStyle(Stage.textDim)
                        Divider().overlay(Stage.edge)
                        StageStat(label: "Arena", value: host.arenaReady ? "ready" : "loading")
                        StageStat(label: "Godot", value: host.godotVersion)
                        StageStat(label: "Parts", value: "\(Catalogue.shared.chassis.count) chassis, \(Catalogue.shared.weapons.count) weapons")
                    }
                    .frame(maxWidth: 420, alignment: .leading)
                }

                Spacer()
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
    }
}
