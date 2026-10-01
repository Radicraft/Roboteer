//
//  FightPause.swift
//  The pause button and the pause overlay that sit over a fight.
//
//  A fight had no way out of it but winning or losing, and no way to stop. This is the shell's
//  side of `fight_control` (docs/bridge-spec-shell-notes.md): the button sends "pause", the
//  overlay's two answers send "resume" or "quit", and the pad's START button arrives as
//  `pause_requested` and opens the same overlay. The arena keeps drawing behind it, so the
//  overlay is a wash and a panel, never a screen.
//

import SwiftUI

// MARK: - The button

/// The small glass pause button. 44 pt of hit target around a pause glyph, which is the whole
/// control: anything wordier would fight the arena for the corner.
struct PauseGlyphButton: View {

    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "pause.fill")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(Stage.type)
                .frame(width: 44, height: 44)
                .background {
                    ZStack {
                        PlateRect().fill(Stage.glassDeep)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pause")
    }
}

// MARK: - The overlay

/// Title, resume, quit. Two answers only: a pause menu that has to be read is not a pause menu.
struct FightPauseOverlay: View {

    var quitTitle: String
    var onResume: () -> Void
    var onQuit: () -> Void

    private var focus: PadFocus { PadFocus.shared }

    var body: some View {
        ZStack {
            // A wash, not a curtain: the fight stays visible underneath, frozen, so the player can
            // see the position they are going back to.
            Stage.ink.opacity(0.70)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onResume() }

            // One panel, per design system section 5. Nothing else is on this screen.
            Panel(padding: 18, deep: true) {
                VStack(alignment: .leading, spacing: 10) {
                    LowerThird(bar: Stage.line, entersFrom: .leading) {
                        Text("PAUSED")
                            .font(Stage.display(30))
                            .kerning(Stage.Tracking.display(30))
                            .foregroundStyle(Stage.type)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    Text("The fight is frozen where you left it.")
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.typeDim)
                        .fixedSize(horizontal: false, vertical: true)

                    StageButton("Resume", kind: .primary, focusID: PadID.resume) { onResume() }
                    StageButton(quitTitle, kind: .danger, focusID: PadID.quit) { onQuit() }

                    PadHintBar()
                        .padding(.top, 2)
                }
                .frame(width: 262)
            }
        }
        .transition(.opacity)
    }

    enum PadID {
        static let resume = "pause.resume"
        static let quit = "pause.quit"
    }
}

// MARK: - The layer both fight screens wear

/// Puts the button and the overlay over a fight screen, owns the pause state, and lends the pad to
/// the overlay for as long as it is up. The menus' own pad handler is gated on the stage being on
/// screen (`MenuView`), so during a fight the overlay has to borrow the pad for itself.
struct FightPauseLayer: ViewModifier {

    let host: ArenaHost
    /// What leaving is called here: the garage from a quick fight, the assessment from a tie.
    var quitTitle: String = "Quit to garage"
    /// True for the floating top right button. The test arena already has a row of controls and
    /// puts its own button in it.
    var showsButton: Bool = true
    /// Belt and braces for an arena that never answers the quit: the screen leaves anyway.
    var onQuitTimeout: () -> Void

    @State private var isPaused = false
    @State private var holdsPad = false
    @State private var didQuit = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if showsButton && canPause {
                    PauseGlyphButton { pause() }
                        .padding(.top, 10)
                        .padding(.trailing, 14)
                }
            }
            .overlay {
                if isPaused {
                    FightPauseOverlay(quitTitle: quitTitle, onResume: resume, onQuit: quit)
                }
            }
            .animation(.easeOut(duration: 0.18), value: isPaused)
            // The pad's START button, relayed by the arena.
            .onChange(of: host.pauseRequests) { _, _ in pause() }
            // A result or an abandoned fight ends the pause whatever put it up.
            .onChange(of: host.fightState) { _, state in
                if state == .result || state == .abandoned { close() }
            }
            .onDisappear { close() }
    }

    /// Pausing a fight that has not started, or one that is already over, would freeze a tick the
    /// arena is not running.
    private var canPause: Bool {
        host.fightState == .countdown || host.fightState == .fighting
    }

    func pause() {
        guard !isPaused, canPause else { return }
        host.sendFightControl("pause")
        isPaused = true
        takePad()
    }

    func resume() {
        guard isPaused else { return }
        host.sendFightControl("resume")
        close()
    }

    func quit() {
        guard !didQuit else { return }
        didQuit = true
        host.sendFightControl("quit")
        close()
        // The arena answers with `fight_state` abandoned and the screen leaves on that. If it does
        // not answer at all, the player is not left sitting in a fight they have quit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard host.fightState != .abandoned else { return }
            onQuitTimeout()
        }
    }

    private func close() {
        isPaused = false
        givePadBack()
    }

    // MARK: - The pad

    private func takePad() {
        guard !holdsPad else { return }
        holdsPad = true
        PadFocus.shared.pushContext()
        PadFocus.shared.set(
            [
                PadItem(FightPauseOverlay.PadID.resume) { resume() },
                PadItem(FightPauseOverlay.PadID.quit) { quit() }
            ],
            back: { resume() }
        )
        ControllerObserver.shared.pushNavigation { event in
            PadFocus.shared.handle(event)
        }
    }

    private func givePadBack() {
        guard holdsPad else { return }
        holdsPad = false
        ControllerObserver.shared.popNavigation()
        PadFocus.shared.popContext()
        // The arena owns the pad again the moment the fight is running.
        PadFocus.shared.clear()
    }
}

extension View {

    /// The pause button and overlay for a fight screen.
    func fightPause(
        host: ArenaHost,
        quitTitle: String = "Quit to garage",
        showsButton: Bool = true,
        onQuitTimeout: @escaping () -> Void
    ) -> some View {
        modifier(
            FightPauseLayer(
                host: host,
                quitTitle: quitTitle,
                showsButton: showsButton,
                onQuitTimeout: onQuitTimeout
            )
        )
    }
}
