//
//  CareerFightView.swift
//  A career tie: the chosen machine against the scouted opponent, in the tier's arena. The same
//  one Godot view at the root of the window with the chrome taken away, exactly as `FightView`
//  does it. This screen only sends the configuration and hands the result back to the career.
//
//  The quick fight in `FightView` is untouched and still sends the Stage 4 fixture opponent.
//

import SwiftUI

/// The `FightConfig` a career tie sends. Same contract as `docs/bridge-spec.md`, with the arena
/// chosen by the tier and a real opponent instead of the fixture machine.
enum CareerFightConfig {

    static let playerID = "player-1"
    static let opponentID = "ai-1"

    static func json(
        player: [String: Any],
        opponent: [String: Any],
        arena: String,
        seed: Int,
        safeArea: SafeAreaPixels,
        opponentAI: String = "normal"
    ) -> String {
        let root: [String: Any] = [
            "schema": 1,
            "seed": seed,
            "arena": arena,
            "rules": ["mode": "fight", "duration_s": 90, "ko_count_s": 10],
            "presentation": [
                "safe_area_px": [
                    "left": safeArea.left,
                    "top": safeArea.top,
                    "right": safeArea.right,
                    "bottom": safeArea.bottom
                ],
                "haptics": true
            ],
            "debug": ["opponent_ai": opponentAI],
            "bots": [player, opponent]
        ]
        return JSONText.string(from: root)
    }
}

struct CareerFightView: View {

    @Bindable var host: ArenaHost

    let playerConfig: [String: Any]
    let opponentConfig: [String: Any]
    let arena: String
    let seed: Int
    /// What quitting from the pause overlay should do. Nothing passes this yet, and the default is
    /// the honest one: a tie the player walked out of is a tie they lost, settled with no damage
    /// and no scrap, exactly as `CareerStore.settle` treats a fight with no result.
    var onQuit: (() -> Void)? = nil
    /// The result and the raw JSON it arrived as, for the fight log.
    var onResult: (FightResult?, String) -> Void

    @State private var didStart = false
    @State private var didFinish = false
    /// The coach counter is spent once per fight, at the countdown.
    @State private var didCount = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // The arena itself is the root Godot view, behind this whole stack.
                banner
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .fightPause(
                host: host,
                quitTitle: "Forfeit the tie",
                onQuitTimeout: { forfeit() }
            )
            .onAppear { start(fallbackInsets: proxy.safeAreaInsets) }
        }
        .statusBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onChange(of: host.fightState) { _, state in
            if state == .result { finish() }
            if (state == .countdown || state == .fighting), !didCount {
                didCount = true
                CoachPolicy.fightStarted()
            }
            // The arena gave the tie up, which is what a quit from the pause overlay comes back as.
            if state == .abandoned { forfeit() }
        }
        .onChange(of: host.lastResult) { _, result in
            if result != nil { finish() }
        }
    }

    /// The arena name sits at the top for the first moments of the fight, because a career fight
    /// is the only place the arena changes.
    private var banner: some View {
        Text((Catalogue.shared.arena(arena)?.name ?? arena).uppercased())
            .font(Stage.display(13))
            .kerning(1.8)
            .foregroundStyle(Stage.textFaint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Stage.panelDeep, in: Capsule())
            .padding(.top, 12)
            .opacity(host.fightState == .countdown || host.fightState == .loading ? 1 : 0)
            .animation(.easeOut(duration: 0.35), value: host.fightState)
    }

    private func start(fallbackInsets: EdgeInsets) {
        guard !didStart else { return }
        didStart = true
        host.arenaScreenAppeared()
        // The how to play callouts, for a player's first fights and for anyone who asked for them.
        CoachPolicy.arm(host, mode: .fight)
        DispatchQueue.main.async {
            let safeArea = SafeAreaPixels.current(fallback: fallbackInsets)
            let json = CareerFightConfig.json(
                player: playerConfig,
                opponent: opponentConfig,
                arena: arena,
                seed: seed,
                safeArea: safeArea,
                opponentAI: "normal"
            )
            host.sentSafeArea = safeArea
            host.startCareerFight(configJSON: json)
        }
    }

    /// Walking out of a tie. Settled as a loss with no result, once, whichever of the arena's
    /// answer and the fallback timer gets here first.
    private func forfeit() {
        guard !didFinish else { return }
        didFinish = true
        host.arenaScreenLeft()
        if let onQuit {
            onQuit()
        } else {
            onResult(nil, host.resultJSON)
        }
    }

    private func finish() {
        guard !didFinish, host.lastResult != nil || host.fightState == .result else { return }
        didFinish = true
        host.arenaScreenLeft()
        onResult(host.lastResult, host.resultJSON)
    }
}
