//
//  CareerFightView.swift
//  A career match: the chosen machine against the scouted opponent, in the Series' arena. The same
//  one Godot view at the root of the window with the chrome taken away, exactly as `FightView`
//  does it. This screen only sends the configuration and hands the result back to the career.
//
//  The quick fight in `FightView` is untouched and still sends the Stage 4 fixture opponent.
//

import SwiftUI

/// The `FightConfig` a career match sends. Same contract as `docs/bridge-spec.md`,
/// `docs/wave-g-contracts.md` and `docs/wave-p-contracts.md` ("Fight config"): the arena chosen by
/// the Series, a real opponent instead of the fixture machine, the house bot on duty in `rules`,
/// the Series' scrap rules in `rules.scrap`, and the opponent's head in its own bot block.
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
        next: NextMatch? = nil,
        opponentAI: String = "normal"
    ) -> String {
        // The house bot: which one, how it behaves and how fast it is allowed to move. G2's
        // enforcer section reads all three (contracts file, corner zone). A fight with no card
        // behind it is not a career match and gets no enforcer at all: the async ladder reuses this
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
            // Brief v5 section 9.3: the Series' own scrap rules, so the arena can tally the live
            // bug and report the breakdown. Present on a CAREER match only; a quick fight, a side
            // event, the test arena and the ladder send no `rules.scrap` and keep the bolt scrap
            // they have always had.
            rules["scrap"] = next.scrapRules.asDictionary
        }

        // The opponent's head: the Series' skill and the machine's temperament (contracts file, AI).
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
    /// Who is in the other corner, who is in the house bot's corner, and what a win pays. The card
    /// on the Series screen printed all of it before this screen was reached. Nil for the async
    /// ladder, which borrows this screen for a ghost fight and has no card, no house bot and no
    /// career scrap.
    var next: NextMatch? = nil
    /// What quitting from the pause overlay should do. Nothing passes this yet, and the default is
    /// the honest one: a match the player walked out of is a match they lost, settled with the
    /// damage it has and nothing banked, which is what `CareerStore.settleMatch` does with a fight
    /// that sent no result.
    var onQuit: (() -> Void)? = nil
    /// The result and the raw JSON it arrived as, for the fight log.
    var onResult: (FightResult?, String) -> Void

    @State private var didStart = false
    @State private var didFinish = false
    /// The arena reported the result; the Match Report waits for the finish beat (FightView.swift).
    @State private var resultReached = false
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
                quitTitle: "Give up the match",
                onQuitTimeout: { forfeit() }
            )
            .onAppear { start(fallbackInsets: proxy.safeAreaInsets) }
        }
        .statusBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onChange(of: host.fightState) { _, state in
            // B8 (combat feel): the finish beat plays before the Match Report; a tap skips it.
            if state == .result { resultReached = true }
            if (state == .countdown || state == .fighting), !didCount {
                didCount = true
                CoachPolicy.fightStarted()
            }
            // The arena gave the match up, which is what a quit from the pause overlay comes back as.
            if state == .abandoned { forfeit() }
        }
        .onChange(of: host.lastResult) { _, result in
            if result != nil { resultReached = true }
        }
        .modifier(FinishBeatGate(started: resultReached) { finish() })
    }

    /// The arena, the match and the house bot on duty sit at the top for the first moments of the
    /// fight, because a career match is the only place any of the three change.
    private var banner: some View {
        Text(bannerLine)
            .font(Stage.display(13))
            .kerning(1.8)
            .foregroundStyle(Stage.textFaint)
            .lineLimit(1)
            .minimumScaleFactor(BroadcastType.floorScale(.display, size: 13, wanted: 0.7))
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
        return "\(next.title.uppercased())  \u{00B7}  \(arenaName)  \u{00B7}  HOUSE BOT \(next.houseBotName)"
    }

    private func start(fallbackInsets: EdgeInsets) {
        guard !didStart else { return }
        didStart = true
        // Bug 6: the pad belongs to the arena while a fight is up, exactly as in `FightView`. The
        // Series screen's FIGHT must not still be live when the match report comes up.
        PadFocus.shared.clear()
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

    /// Walking out of a match. Settled as a loss with no result, once, whichever of the arena's
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
