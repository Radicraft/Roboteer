//
//  CareerFightView.swift
//  A career tie: the chosen machine against the scouted opponent, in the tier's arena. The same
//  one Godot view at the root of the window with the chrome taken away, exactly as `FightView`
//  does it. This screen only sends the configuration and hands the result back to the career.
//
//  The quick fight in `FightView` is untouched and still sends the Stage 4 fixture opponent.
//

import SwiftUI

/// The `FightConfig` a career tie sends. Same contract as `docs/bridge-spec.md` and
/// `docs/wave-g-contracts.md`, with the arena chosen by the tier, a real opponent instead of the
/// fixture machine, the house bot on duty in `rules`, and the opponent's head in its own bot block.
enum CareerFightConfig {

    static let playerID = "player-1"
    static let opponentID = "ai-1"

    /// One three minute round with the endgame at two minutes (brief v4 section 2). The constant
    /// itself is G1's, in `Arena/fight/fight_types.gd` as `FIGHT_DURATION_S`; this is the host's
    /// half of the same number and the two have to agree.
    static let fightDurationS = 180

    static let koCountS = 10

    static func json(
        player: [String: Any],
        opponent: [String: Any],
        arena: String,
        seed: Int,
        safeArea: SafeAreaPixels,
        next: NextFight? = nil,
        opponentAI: String = "normal"
    ) -> String {
        // The house bot: which one, how it behaves and how fast it is allowed to move. G2's
        // enforcer section reads all three (contracts file, corner zone). A fight with no card
        // behind it is not a career tie and gets no enforcer at all: the async ladder reuses this
        // screen for a ghost fight, and brief v4 section 3 puts house bots in CAREER fights.
        var rules: [String: Any] = [
            "mode": "fight",
            "duration_s": fightDurationS,
            "ko_count_s": koCountS
        ]
        if let next {
            rules["enforcer"] = next.houseBotID
            rules["enforcer_mode"] = "zone"
            rules["enforcer_speed"] = next.houseBotSpeed
        }

        // The opponent's head: the tier's skill and the machine's temperament (contracts file, AI).
        // Only the AI bot carries them; the player's block is left exactly as the garage built it.
        var opponentBot = opponent
        if let next {
            opponentBot["ai_skill"] = next.aiSkill
            opponentBot["temperament"] = next.temperament
        }

        let root: [String: Any] = [
            "schema": 1,
            "seed": seed,
            "arena": arena,
            "rules": rules,
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
            "bots": [player, opponentBot]
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
    /// Who is in the other corner, who is in the house bot's corner, and what the tie pays. The
    /// card on the season screen printed all of it before this screen was reached. Nil for the
    /// async ladder, which borrows this screen for a ghost fight and has no card and no house bot.
    var next: NextFight? = nil
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
                // The arena's touches. The one Godot view is a SIBLING BELOW the navigation
                // controller's container view, and that container answers `hitTest` with itself
                // even when it is clear, so on a PUSHED fight screen no touch ever reaches the
                // engine on its own: this hands every touch the chrome above leaves alone to
                // `Input.parseInputEvent` by hand (`FightTouchForwarder`, StageSurface.swift).
                //
                // Owner's bug, 2026-09-16: a quick fight drove and a career fight did not, because
                // `FightView` had this and this screen did not. It is the FIRST child of the stack
                // so the banner and the pause overlay keep their own touches.
                FightTouchForwarder()
                    .ignoresSafeArea()
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

    /// The arena, the round and the house bot on duty sit at the top for the first moments of the
    /// fight, because a career tie is the only place any of the three change.
    private var banner: some View {
        Text(bannerLine)
            .font(Stage.display(13))
            .kerning(1.8)
            .foregroundStyle(Stage.textFaint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Stage.glassDeep, in: CutRect(8))
            .padding(.top, 12)
            .opacity(host.fightState == .countdown || host.fightState == .loading ? 1 : 0)
            .animation(.easeOut(duration: 0.35), value: host.fightState)
    }

    private var bannerLine: String {
        let arenaName = (Catalogue.shared.arena(arena)?.name ?? arena).uppercased()
        guard let next else { return arenaName }
        return "\(next.roundTitle.uppercased())  \u{00B7}  \(arenaName)  \u{00B7}  HOUSE BOT \(next.houseBotName)"
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
                next: next,
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
