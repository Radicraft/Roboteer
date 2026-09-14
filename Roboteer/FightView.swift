//
//  FightView.swift
//  The fight screen and the test arena. Both are the one Godot view at the root of the window with
//  the menu chrome taken away: this view only sends the configuration and draws what sits on top.
//  docs/stage3-spec.md section 12, docs/stage4-spec.md sections 6 and 7.
//

import SwiftUI
import SwiftData

struct FightView: View {

    @Bindable var host: ArenaHost
    /// A real fight, or the test arena with no timer and a reset button.
    var mode: ArenaHost.FightMode = .fight
    /// What the quick fight picker chose: the arena, the opponent and whether it is a rumble.
    /// Nil means the Stage 4 fixture fight, which is what the test arena and QA still want.
    var choice: QuickFightChoice?
    /// Pops back to the root menu.
    var onBackToGarage: () -> Void

    @Query(sort: \BotBuild.createdAt, order: .forward) private var builds: [BotBuild]
    @Query private var careers: [CareerState]

    @State private var didStart = false
    @State private var showResult = false

    private var player: BotBuild? { Garage.selected(from: builds) }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // The arena itself is the root Godot view, behind this whole stack.
                if ArenaHost.isSimulator {
                    simulatorNote
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .allowsHitTesting(false)
                }
                if mode.isTest {
                    testControls
                }
            }
            .onAppear { start(fallbackInsets: proxy.safeAreaInsets) }
        }
        .statusBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onDisappear { host.arenaScreenLeft() }
        .onChange(of: host.fightState) { _, state in
            if state == .result, mode == .fight { showResult = true }
            // S6 (stage 6): the arena gave the fight up. There is no result to show, so the only
            // sensible thing is to put the player back in the garage.
            if state == .abandoned {
                host.arenaScreenLeft()
                onBackToGarage()
            }
        }
        .onChange(of: host.lastResult) { _, result in
            if result != nil, mode == .fight { showResult = true }
        }
        .sheet(isPresented: $showResult) {
            ResultSheet(host: host, result: host.lastResult, player: player) {
                showResult = false
                host.arenaScreenLeft()
                onBackToGarage()
            }
            .interactiveDismissDisabled(true)
        }
    }

    // MARK: - Starting

    /// The safe area has to be measured before the configuration goes out, because the contract
    /// allows exactly one `fight_config` per fight and no chatter after it. The measurement is
    /// taken one runloop turn after the view appears so the window has settled with the status
    /// bar already hidden. `fallbackInsets` is the layout view of the same thing, used only if
    /// there is no window to ask.
    private func start(fallbackInsets: EdgeInsets) {
        guard !didStart else { return }
        didStart = true
        // The pad belongs to the arena while a fight is up.
        PadFocus.shared.clear()
        host.arenaScreenAppeared()
        let bot = player?.toBotConfig(id: FightConfigFixture.playerID, controller: "player")
        // One seed per fight, so two quick fights in a row do not draw the same made up machine.
        let seed = Int(Date().timeIntervalSince1970) &* 7919 &+ (player?.name.hashValue ?? 0) % 9973
        let tier = careers.first?.tier ?? .regional
        let choice = self.choice
        DispatchQueue.main.async {
            guard let bot else {
                host.errorText = "There is no bot in the garage to fight with."
                return
            }
            let opponents = choice.map {
                QuickFight.opponentConfigs(for: $0, tier: tier, seed: seed)
            }
            host.startFight(
                player: bot,
                mode: mode,
                safeArea: SafeAreaPixels.current(fallback: fallbackInsets),
                arena: choice?.arenaID ?? "yard",
                opponents: opponents,
                rumble: choice?.rumble ?? false,
                seed: seed
            )
        }
    }

    // MARK: - Test arena controls

    /// The physics readout itself is Godot's overlay (docs/stage4-spec.md section 5). These two
    /// buttons are the shell's part: reset the arena, and leave.
    private var testControls: some View {
        VStack {
            HStack(spacing: 10) {
                StageButton("Back", kind: .glass) {
                    host.arenaScreenLeft()
                    onBackToGarage()
                }
                .frame(width: 110)

                Spacer()

                Text("TEST ARENA")
                    .font(Stage.display(15))
                    .kerning(1.6)
                    .foregroundStyle(Stage.textDim)

                Spacer()

                StageButton("Reset", kind: .glass) {
                    host.sendTestReset()
                }
                .frame(width: 110)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Simulator note

    /// The simulator has no Metal slice of libgodot, so it renders the arena through OpenGL ES 3
    /// (docs/simulator-rendering.md). Everything on screen is the real arena; this only says which
    /// renderer drew it. The device path is Metal and shows nothing.
    private var simulatorNote: some View {
        Text("SIMULATOR: OPENGL ES 3")
            .font(Stage.body(10))
            .kerning(1.0)
            .foregroundStyle(Stage.textFaint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Stage.panelDeep, in: Capsule())
            .padding(.leading, 16)
            .padding(.bottom, 16)
    }

    private var statusLine: String {
        let state: String
        switch host.fightState {
        case .loading: state = host.arenaReady ? "waiting for the first state" : "waiting for the arena"
        case .countdown: state = "countdown"
        case .fighting: state = "fighting"
        case .result: state = "result"
        case .abandoned: state = "abandoned"
        }
        let who = player.map { "\($0.name), \(BuildRules.kilograms($0.totalWeight))" } ?? "no bot"
        let kind = mode.isTest ? "test arena" : "fight"
        return "\(kind.capitalizedFirst). Bot: \(who). State: \(state). Opponent: \(ArenaHost.opponentAI). Safe area: \(host.sentSafeArea.left), \(host.sentSafeArea.top), \(host.sentSafeArea.right), \(host.sentSafeArea.bottom) px."
    }
}
