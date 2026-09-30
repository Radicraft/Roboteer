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
    /// The arena reported the result. The sheet waits for the finish beat (`FinishBeatGate`).
    @State private var resultReached = false
    /// One way out, whoever asks for it: the abandoned state, the result sheet, or a quit the
    /// arena never answered.
    @State private var didLeave = false
    /// The coach counter is spent once per fight, at the countdown.
    @State private var didCount = false

    private var player: BotBuild? { Garage.selected(from: builds) }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // The arena itself is the root Godot view, behind this whole stack. Its touches
                // have to be handed to it: the navigation container between them swallows every
                // one otherwise (`FightTouchForwarder`).
                FightTouchForwarder()
                    .ignoresSafeArea()
                if ArenaHost.isSimulator {
                    simulatorNote
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(false)
                }
                if mode.isTest {
                    testControls
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .fightPause(
                host: host,
                quitTitle: mode.isTest ? "Leave the test arena" : "Quit to garage",
                onQuitTimeout: { leave() }
            )
            .onAppear { start(fallbackInsets: proxy.safeAreaInsets) }
        }
        .statusBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onDisappear { host.arenaScreenLeft() }
        .onChange(of: host.fightState) { _, state in
            // B8 (combat feel): not on this frame. The finish beat plays first (the banner, the
            // bell, the wreck in slow motion), then the sheet; a tap skips it.
            if state == .result, mode == .fight { resultReached = true }
            // A fight the arena actually started. Counted here rather than at the tap, so the
            // three coached fights are three fights the player really had.
            if (state == .countdown || state == .fighting), !didCount, mode == .fight {
                didCount = true
                CoachPolicy.fightStarted()
                IntroPolicy.fightStarted(arena: choice?.arenaID ?? "yard")
            }
            // S6 (stage 6): the arena gave the fight up, which is also what a quit from the pause
            // overlay comes back as. There is no result to show, so the only sensible thing is to
            // put the player back in the garage.
            if state == .abandoned {
                leave()
            }
        }
        .onChange(of: host.lastResult) { _, result in
            if result != nil, mode == .fight { resultReached = true }
        }
        .modifier(FinishBeatGate(started: resultReached, seconds: host.finishBeatSeconds) { showResult = true })
        .sheet(isPresented: $showResult) {
            ResultSheet(host: host, result: host.lastResult, player: player) {
                showResult = false
                leave()
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
        // The how to play callouts, for a player's first fights, for the test arena, and for
        // anyone who asked for them in settings.
        CoachPolicy.arm(host, mode: mode)
        // The arena intro: full the first time here, short after, none in the test arena or on a
        // quick restart (`IntroPolicy`).
        IntroPolicy.arm(host, arena: choice?.arenaID ?? "yard", isTest: mode.isTest)
        // Wave D: a quick fight's walk-outs are the short ones, and no head to head.
        host.tapeNextFight = nil
        // Exhibition: the machine fights as built and carries nothing home (see BotBuild).
        let bot = player?.toBotConfig(id: FightConfigFixture.playerID, controller: "player", pristine: true)
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
            if !mode.isTest, let choice, !choice.rumble {
                host.tapeNextFight = TaleOfTheTape.forQuickFight(
                    build: player,
                    playerName: player?.name ?? "Your machine",
                    opponent: QuickFight.opponent(for: choice, tier: tier, seed: seed),
                    houseBotID: QuickFight.houseBot(for: choice, tier: tier)?.id
                )
            }
            host.startFight(
                player: bot,
                mode: mode,
                safeArea: SafeAreaPixels.current(fallback: fallbackInsets),
                arena: choice?.arenaID ?? "yard",
                opponents: opponents,
                rumble: choice?.rumble ?? false,
                houseBot: choice.flatMap { QuickFight.houseBot(for: $0, tier: tier) },
                seed: seed
            )
        }
    }

    /// Back to the garage, once. Every way out funnels through here so a quit that the arena
    /// answers and the fallback timer cannot both pop the screen.
    private func leave() {
        guard !didLeave else { return }
        didLeave = true
        host.arenaScreenLeft()
        onBackToGarage()
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
        // Clear of the pause button in the corner.
        .padding(.trailing, 54)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Simulator note

    /// The simulator has no Metal slice of libgodot, so it renders the arena through OpenGL ES 3
    /// (docs/simulator-rendering.md). Everything on screen is the real arena; this only says which
    /// renderer drew it, and it says so honestly: a run launched headless or with a dummy driver
    /// draws nothing at all, whatever the default would have been. The device path is Metal and
    /// shows nothing.
    ///
    /// It sits bottom centre, under the HUD's status line, because the bottom left corner belongs
    /// to the virtual stick.
    private var simulatorNote: some View {
        Text(host.rendersLive ? "SIMULATOR: OPENGL ES 3" : "SIMULATOR: HEADLESS ARENA")
            .font(Stage.body(13))
            .kerning(1.0)
            .foregroundStyle(Stage.textFaint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Stage.glassDeep, in: CutRect(6))
            .padding(.bottom, 10)
    }

    // `statusLine` lived here: "Fight. Bot: Tinribs, 89.5 kg. State: fighting. Opponent: normal.
    // Safe area: 59, 0, 59, 21 px." Nothing has drawn it since the fight HUD took the feed over,
    // and it is a diagnostic, so it is gone rather than left one modifier away from shipping
    // (wave P, agent H). The same facts are in the arena log and in `-showSpike`.
}


// MARK: - The finish beat

/// Owner decision 2026-09-24 (combat feel, bug B8): the result sheet and the Match Report wait
/// for a fixed finish beat after the arena reports the result, and a tap skips it. Before this the
/// sheet covered the arena on the very frame the fight ended, so the player never saw the
/// knockout they scored. The result itself has already arrived and been kept by then; only the
/// screen waits. The arena's own beat (`FINISH_BEAT_S` in Arena/fight/fight.gd: the slow motion
/// follow, the banner, the bodies still moving) is the same length, and the arena sends a longer
/// one with `fight_state` result when the house bot has a finishing ritual to play (wave D).
enum FinishBeat {
    static let seconds: Double = 3.5
    /// The longest the arena may ask for (wave D: a finishing ritual with a late hit is 8.5 s).
    static let longest: Double = 10.0
}

/// Runs `onDone` once, `FinishBeat.seconds` after `started` turns true, or at the first tap in
/// between. While the beat runs, a clear layer over the arena takes the tap; the fight's controls
/// are already off by then.
struct FinishBeatGate: ViewModifier {
    let started: Bool
    /// The arena's own beat for this fight (`ArenaHost.finishBeatSeconds`), 3.5 s by default.
    var seconds: Double = FinishBeat.seconds
    let onDone: () -> Void

    @State private var armed = false
    @State private var fired = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if started && !fired {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture { fire() }
                        .accessibilityLabel("Skip to the result")
                        .accessibilityAddTraits(.isButton)
                }
            }
            .onChange(of: started) { _, now in
                if now { arm() }
            }
            .onAppear {
                if started { arm() }
            }
    }

    private func arm() {
        guard !armed else { return }
        armed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { fire() }
    }

    private func fire() {
        guard !fired else { return }
        fired = true
        onDone()
    }
}
