//
//  Onboarding.swift
//  The first five minutes. Brief section 10: the workshop test arena is the game's real tutorial,
//  so onboarding is not a slideshow of rules, it is three sentences and then a shove towards the
//  bench.
//
//  Build, Test, Fight. That is the whole shape of the game and the whole of the welcome.
//
//  The state is one string in UserDefaults, so it survives a relaunch mid flow and a player who
//  closes the app on the test arena comes back to the same prompt. `-resetOnboarding` puts it back
//  to the beginning for QA.
//

import SwiftUI

// MARK: - The state

@Observable
final class OnboardingCoach {

    /// Where the new player is in the three step shove.
    enum Step: String {
        /// Never launched before: the welcome panels are up.
        case welcome
        /// Sent to the workshop, being asked to test the machine in the arena.
        case build
        /// Inside the test arena, which is the tutorial. Nothing is drawn over it.
        case test
        /// Out of the test arena, being asked to take the machine to a fight.
        case fight
        /// Done, and never shown again.
        case done
    }

    static let shared = OnboardingCoach()

    private enum Key {
        static let step = "onboarding.step"
    }

    private(set) var step: Step = .done
    /// Set while a callout has been waved away by hand, so it does not come straight back on the
    /// same screen. It returns on the next screen change, because the player still has to do it.
    private(set) var calloutHidden = false

    private init() {
        let stored = UserDefaults.standard.string(forKey: Key.step)
        step = stored.flatMap(Step.init(rawValue:)) ?? .welcome
    }

    /// Called once at launch. `-resetOnboarding` puts a shipped build back to a first launch.
    func begin() {
        if ArenaHost.hasLaunchFlag("-resetOnboarding") {
            reset()
        }
        spikeLog.info("onboarding step \(self.step.rawValue, privacy: .public)")
    }

    func reset() {
        set(.welcome)
        calloutHidden = false
    }

    /// Give up on the whole thing. The player pressed Skip, or reached a fight by themselves.
    func finish() {
        guard step != .done else { return }
        set(.done)
    }

    /// The welcome panels have been read. Next stop is the bench.
    func startBuilding() {
        set(.build)
    }

    /// Where the player is now, as one of the menu's own route names. Every advance in the flow
    /// happens here, so the rules are in one place and a screen only has to say its own name.
    func noteScreen(_ name: String) {
        switch step {
        case .build:
            if name == "test" { set(.test) }
        case .test:
            // The first test session is over the moment they leave it. That is the tutorial done.
            if name != "test" { set(.fight) }
        case .fight:
            if name == "fight" || name == "career" { set(.done) }
        case .welcome, .done:
            break
        }
        if name != lastScreen {
            lastScreen = name
            calloutHidden = false
        }
    }

    func hideCallout() {
        calloutHidden = true
    }

    /// The sentence for this step on this screen, or nil when nothing should be said here.
    func callout(on screen: String) -> String? {
        guard !calloutHidden else { return nil }
        switch step {
        case .build where screen == "workshop":
            return "This is your machine. Change anything you like, then take it to the test arena and see how it drives."
        case .fight where screen == "menu" || screen == "workshop":
            return "That is the hard part done. Now put it in front of something that fights back."
        default:
            return nil
        }
    }

    /// What the callout's button says, and what it does.
    func calloutAction(on screen: String) -> (title: String, isRoute: Bool)? {
        switch step {
        case .build where screen == "workshop":
            return ("Test it", true)
        case .fight where screen == "menu" || screen == "workshop":
            return ("Fight", true)
        default:
            return nil
        }
    }

    @ObservationIgnored private var lastScreen = ""

    private func set(_ new: Step) {
        step = new
        UserDefaults.standard.set(new.rawValue, forKey: Key.step)
    }
}

// MARK: - The welcome

/// Three panels, one sentence each, in the same dark glass as everything else. It is a landscape
/// row, so it reads left to right in the order the game is played.
struct OnboardingWelcome: View {

    var onBuild: () -> Void
    var onSkip: () -> Void

    private struct Panel: Identifiable {
        let id: String
        let title: String
        let line: String
        let symbol: String
    }

    private let panels: [Panel] = [
        Panel(id: "build", title: "BUILD",
              line: "Pick a chassis, a weapon, a drive and armour. One hundred kilograms, no more.",
              symbol: "wrench.and.screwdriver.fill"),
        Panel(id: "test", title: "TEST",
              line: "Drive it in the test arena. Nothing is at stake and nothing is on the clock.",
              symbol: "figure.walk.motion"),
        Panel(id: "fight", title: "FIGHT",
              line: "Enter the circuit, win the purse, repair the damage and do it again.",
              symbol: "bolt.fill")
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WELCOME")
                        .font(Stage.label(12, weight: .bold))
                        .kerning(2)
                        .foregroundStyle(Stage.textFaint)
                    Text("BUILD. TEST. FIGHT.")
                        .font(Stage.display(38, weight: .black))
                        .kerning(1.4)
                        .foregroundStyle(Stage.text)
                    Rectangle()
                        .fill(Stage.text.opacity(0.85))
                        .frame(width: 66, height: 3)
                }

                HStack(alignment: .top, spacing: 12) {
                    ForEach(panels) { panel in
                        GlassPanel(padding: 14) {
                            VStack(alignment: .leading, spacing: 7) {
                                Image(systemName: panel.symbol)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(Stage.text)
                                Text(panel.title)
                                    .font(Stage.display(20))
                                    .kerning(1.2)
                                    .foregroundStyle(Stage.text)
                                Text(panel.line)
                                    .font(Stage.body(12))
                                    .foregroundStyle(Stage.textDim)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                HStack(spacing: 10) {
                    StageButton("Build a bot", kind: .primary, focusID: "welcome-build", action: onBuild)
                        .frame(width: 200)
                    StageButton("Skip", kind: .glass, focusID: "welcome-skip", action: onSkip)
                        .frame(width: 130)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .transition(.opacity)
    }
}

// MARK: - The callout

/// One sentence on glass at the bottom of the screen, with the thing it is asking for as a button
/// and a way to wave it away. It never covers the middle of the screen and never blocks a tap.
struct OnboardingCallout: View {

    let text: String
    let actionTitle: String?
    var onAction: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            GlassPanel(padding: 12) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Stage.gold)
                    Text(text)
                        .font(Stage.label(13))
                        .foregroundStyle(Stage.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let actionTitle {
                        StageButton(actionTitle, kind: .primary, action: onAction)
                            .frame(width: 130)
                    }
                    StageButton("Not now", kind: .glass, action: onDismiss)
                        .frame(width: 110)
                }
            }
            .frame(maxWidth: 700)
            .padding(.horizontal, 26)
            .padding(.bottom, 16)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
