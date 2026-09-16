//
//  ControllerObserver.swift
//  Xbox and PlayStation pads: knowing one is there, and driving the menus with it.
//
//  The arena itself gets its pad input from GameController inside libgodot, which installs its own
//  element handlers. So this file never installs a handler and never consumes an event: it POLLS
//  the pad state from a CADisplayLink while a menu is on screen, and stops the moment a fight is up
//  so the arena owns the pad uncontested.
//

import Foundation
import SwiftUI
import GameController

/// What the menus understand from a pad.
enum PadEvent {
    case up
    case down
    case left
    case right
    case activate
    case back
}

@Observable
final class ControllerObserver {

    static let shared = ControllerObserver()

    /// A pad is paired and awake.
    private(set) var connected = false
    /// True once a connected pad has actually produced input. GameController lists pads that are
    /// paired but in nobody's hands, and the iPhone 17 simulator lists a phantom "MFi Gamepad" the
    /// moment the app launches, so being listed is not evidence of a player holding one. Cleared
    /// when the last pad goes away.
    private(set) var active = false
    /// "Xbox", "DualSense", "DualShock", "Controller", or whatever the pad calls itself.
    private(set) var kind = ""

    /// QA: `-controllerHints` forces the hint state on with no pad in the room.
    static let hintsForced = ArenaHost.hasLaunchFlag("-controllerHints")

    /// Whether the button hints should be on screen: a pad is connected AND somebody has moved a
    /// stick or pressed a button on it. Hints over the menus with nothing in anyone's hands are
    /// worse than no hints, because they teach controls the player has no way to use.
    var showsHints: Bool { (connected && active) || Self.hintsForced }

    /// The pad's name for the hint bar, or empty when the name says nothing a player would
    /// recognise. "MFi" and "HID" are Apple's words for "some pad", not a brand, and the phantom
    /// simulator pad calls itself "MFi Gamepad".
    var kindLabel: String {
        let generic = ["mfi", "hid", "controller", "gamepad", "generic"]
        let words = kind.lowercased().split(separator: " ").map(String.init)
        if words.isEmpty { return "" }
        return words.allSatisfy { generic.contains($0) } ? "" : kind
    }

    /// PlayStation pads mark the same two buttons differently, and a hint that shows the wrong
    /// glyph is worse than no hint.
    var activateGlyph: String { isPlayStation ? "✕" : "A" }
    var backGlyph: String { isPlayStation ? "○" : "B" }

    private var isPlayStation: Bool {
        kind.localizedCaseInsensitiveContains("dual")
    }

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var handler: ((PadEvent) -> Void)?
    /// Handlers a screen has borrowed the pad with, newest last. The pause overlay takes the pad
    /// off the menus while it is up and hands it straight back.
    @ObservationIgnored private var handlerStack: [((PadEvent) -> Void)?] = []
    /// Pads whose `valueChangedHandler` has already been wrapped, so a second `refresh` does not
    /// chain a second wrapper onto the first.
    @ObservationIgnored private var instrumented: Set<ObjectIdentifier> = []
    @ObservationIgnored private var heldDirection: PadEvent?
    @ObservationIgnored private var heldSince: CFTimeInterval = 0
    @ObservationIgnored private var lastRepeatAt: CFTimeInterval = 0
    @ObservationIgnored private var activateWasDown = false
    @ObservationIgnored private var backWasDown = false

    /// A held direction waits this long before it starts repeating, then repeats at this rate.
    private let repeatDelay: CFTimeInterval = 0.42
    private let repeatInterval: CFTimeInterval = 0.13
    /// How far a stick has to move before it counts as a direction.
    private let stickThreshold: Float = 0.55

    private init() {}

    // MARK: - Knowing a pad is there

    func start() {
        refresh()
        let centre = NotificationCenter.default
        centre.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        centre.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        // Pads that are paired but asleep wake into this notification rather than DidConnect.
        centre.addObserver(forName: .GCControllerDidBecomeCurrent, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        let pads = GCController.controllers()
        let pad = GCController.current ?? pads.first
        let wasConnected = connected
        connected = pad != nil
        kind = pad.map(Self.name(for:)) ?? ""
        if !connected {
            // Nothing is listed any more, so nothing can be in anyone's hands.
            active = false
            instrumented.removeAll()
        }
        instrumented = instrumented.intersection(pads.map(ObjectIdentifier.init))
        for pad in pads { instrument(pad) }
        if connected != wasConnected {
            spikeLog.info("controller \(self.connected ? "connected" : "disconnected", privacy: .public) \(self.kind, privacy: .public)")
        }
    }

    /// Notice the first real input from a pad.
    ///
    /// libgodot reads the same pad through GameController and installs its OWN
    /// `valueChangedHandler`, so this must never simply assign over it. The previous handler is
    /// captured and called, which leaves the arena's input untouched whichever side installs
    /// first. It is belt and braces anyway: `tick()` polls for the same thing, and the poll is
    /// what catches the case where the arena installs its handler after this one.
    private func instrument(_ pad: GCController) {
        guard let gamepad = pad.extendedGamepad else { return }
        let id = ObjectIdentifier(pad)
        guard !instrumented.contains(id) else { return }
        instrumented.insert(id)
        let previous = gamepad.valueChangedHandler
        gamepad.valueChangedHandler = { [weak self] gamepad, element in
            self?.noticeInput()
            previous?(gamepad, element)
        }
    }

    /// Somebody moved something on a pad. From here on the button hints are honest.
    private func noticeInput() {
        guard !active else { return }
        // A pad handler can be called on whatever queue the reader set, and this is observable
        // state that a view is watching.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.noticeInput() }
            return
        }
        active = true
        spikeLog.info("controller input seen, hints on (\(self.kind, privacy: .public))")
        // The arena HUD draws its own glyphs from the settings message, so it has to be told.
        ArenaHost.shared.sendSettings(RoboteerSettings.shared.dictionary)
    }

    /// Apple reports `productCategory` as things like "Xbox One", "DualSense", "DualShock 4",
    /// "MFi" or "HID". Anything unrecognised keeps its own name, and an empty one is a controller.
    static func name(for pad: GCController) -> String {
        let category = pad.productCategory
        if category.localizedCaseInsensitiveContains("xbox") { return "Xbox" }
        if category.localizedCaseInsensitiveContains("dualsense") { return "DualSense" }
        if category.localizedCaseInsensitiveContains("dualshock") { return "DualShock" }
        if category.isEmpty { return "Controller" }
        return category
    }

    // MARK: - Driving the menus

    /// Start polling. Safe to call more than once.
    func beginNavigation(_ handler: @escaping (PadEvent) -> Void) {
        self.handler = handler
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 60, preferred: 30)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Borrow the pad for a screen that sits over everything else (the pause overlay). The
    /// previous handler is kept and comes back on `popNavigation`.
    func pushNavigation(_ handler: @escaping (PadEvent) -> Void) {
        handlerStack.append(self.handler)
        self.handler = handler
        heldDirection = nil
        activateWasDown = false
        backWasDown = false
        beginNavigation(handler)
    }

    func popNavigation() {
        guard let previous = handlerStack.popLast() else { return }
        handler = previous
        heldDirection = nil
        activateWasDown = false
        backWasDown = false
    }

    func endNavigation() {
        link?.invalidate()
        link = nil
        handler = nil
        heldDirection = nil
        activateWasDown = false
        backWasDown = false
    }

    @objc private func tick() {
        guard let handler, let pad = (GCController.current ?? GCController.controllers().first)?.extendedGamepad else {
            heldDirection = nil
            return
        }
        if !connected { refresh() }

        // The poll's own view of "somebody is holding this", for the case where the arena's
        // handler replaced the wrapper installed above.
        if !active, Self.isBeingUsed(pad) { noticeInput() }

        let now = CACurrentMediaTime()

        // Direction: the d-pad or the left stick, whichever is being used.
        var direction: PadEvent?
        if pad.dpad.up.isPressed || pad.leftThumbstick.yAxis.value > stickThreshold {
            direction = .up
        } else if pad.dpad.down.isPressed || pad.leftThumbstick.yAxis.value < -stickThreshold {
            direction = .down
        } else if pad.dpad.left.isPressed || pad.leftThumbstick.xAxis.value < -stickThreshold {
            direction = .left
        } else if pad.dpad.right.isPressed || pad.leftThumbstick.xAxis.value > stickThreshold {
            direction = .right
        }

        if let direction {
            if direction != heldDirection {
                heldDirection = direction
                heldSince = now
                lastRepeatAt = now
                handler(direction)
            } else if now - heldSince > repeatDelay, now - lastRepeatAt > repeatInterval {
                lastRepeatAt = now
                handler(direction)
            }
        } else {
            heldDirection = nil
        }

        // A activates, B goes back. Both fire on the press, not the release.
        let activateDown = pad.buttonA.isPressed
        if activateDown, !activateWasDown { handler(.activate) }
        activateWasDown = activateDown

        let backDown = pad.buttonB.isPressed
        if backDown, !backWasDown { handler(.back) }
        backWasDown = backDown
    }

    /// Any button down, or either stick or trigger off its rest position by more than the noise a
    /// worn pad sits at.
    private static func isBeingUsed(_ pad: GCExtendedGamepad) -> Bool {
        let noise: Float = 0.25
        if pad.buttonA.isPressed || pad.buttonB.isPressed || pad.buttonX.isPressed || pad.buttonY.isPressed { return true }
        if pad.dpad.up.isPressed || pad.dpad.down.isPressed || pad.dpad.left.isPressed || pad.dpad.right.isPressed { return true }
        if pad.leftShoulder.isPressed || pad.rightShoulder.isPressed { return true }
        if pad.leftTrigger.value > noise || pad.rightTrigger.value > noise { return true }
        if pad.buttonMenu.isPressed || pad.buttonOptions?.isPressed == true { return true }
        if abs(pad.leftThumbstick.xAxis.value) > noise || abs(pad.leftThumbstick.yAxis.value) > noise { return true }
        if abs(pad.rightThumbstick.xAxis.value) > noise || abs(pad.rightThumbstick.yAxis.value) > noise { return true }
        return false
    }
}

// MARK: - Focus

/// One control a pad can land on.
struct PadItem: Identifiable {
    let id: String
    var enabled: Bool = true
    var action: () -> Void

    init(_ id: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.id = id
        self.enabled = enabled
        self.action = action
    }
}

/// Which control the pad is on. One per app: there is one window and one player.
@Observable
final class PadFocus {

    static let shared = PadFocus()

    /// The control the pad is on, or nil when the screen has none.
    private(set) var currentID: String?
    /// The ring only appears once the pad has actually been used, so a touch player never sees it.
    private(set) var showsRing = false

    @ObservationIgnored private var items: [PadItem] = []
    @ObservationIgnored private var onBack: (() -> Void)?
    /// A screen can take left and right for itself (the builder's tabs) by returning true.
    @ObservationIgnored private var onSideways: ((PadEvent) -> Bool)?
    @ObservationIgnored private var stack: [Context] = []

    private init() {}

    /// Called by a screen when it appears and whenever what is enabled changes.
    func set(_ items: [PadItem], back: (() -> Void)? = nil, sideways: ((PadEvent) -> Bool)? = nil) {
        self.items = items
        self.onBack = back
        self.onSideways = sideways
        if let currentID, items.contains(where: { $0.id == currentID && $0.enabled }) { return }
        currentID = items.first(where: { $0.enabled })?.id
    }

    /// A sheet takes the pad for as long as it is up, then hands it back exactly as it was.
    /// Without this the screen underneath is left holding the sheet's items after it closes.
    func pushContext() {
        stack.append(Context(items: items, back: onBack, sideways: onSideways, current: currentID))
    }

    func popContext() {
        guard let context = stack.popLast() else { return }
        items = context.items
        onBack = context.back
        onSideways = context.sideways
        currentID = context.current
    }

    private struct Context {
        var items: [PadItem]
        var back: (() -> Void)?
        var sideways: ((PadEvent) -> Bool)?
        var current: String?
    }

    /// Called when a screen goes away, so a stale action can never be fired.
    func clear() {
        items = []
        onBack = nil
        onSideways = nil
        currentID = nil
    }

    func isFocused(_ id: String) -> Bool {
        showsRing && currentID == id
    }

    func handle(_ event: PadEvent) {
        switch event {
        case .up:
            move(-1)
        case .down:
            move(1)
        case .left:
            if onSideways?(.left) == true { showsRing = true } else { move(-1) }
        case .right:
            if onSideways?(.right) == true { showsRing = true } else { move(1) }
        case .activate:
            showsRing = true
            guard let currentID, let item = items.first(where: { $0.id == currentID }), item.enabled else { return }
            item.action()
        case .back:
            showsRing = true
            onBack?()
        }
    }

    private func move(_ delta: Int) {
        let usable = items.filter(\.enabled)
        guard !usable.isEmpty else { return }
        showsRing = true
        guard let currentID, let index = usable.firstIndex(where: { $0.id == currentID }) else {
            self.currentID = usable.first?.id
            return
        }
        let next = (index + delta + usable.count) % usable.count
        self.currentID = usable[next].id
    }
}

// MARK: - Hints

/// The button hints, shown only while a pad is connected (or `-controllerHints` is on).
struct PadHintBar: View {

    var showsBack: Bool = true
    private var observer: ControllerObserver { ControllerObserver.shared }

    var body: some View {
        if observer.showsHints {
            HStack(spacing: 14) {
                hint(observer.activateGlyph, "Select")
                if showsBack {
                    hint(observer.backGlyph, "Back")
                }
                if !observer.kindLabel.isEmpty {
                    Text(observer.kindLabel.uppercased())
                        .font(Stage.label(10, weight: .bold))
                        .kerning(1.2)
                        .foregroundStyle(Stage.textFaint)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .fixedSize()
            .layoutPriority(2)
            .accessibilityHidden(true)
        }
    }

    private func hint(_ glyph: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(glyph)
                .font(Stage.label(11, weight: .bold))
                .foregroundStyle(Stage.ink)
                .frame(width: 18, height: 18)
                .background(Stage.line, in: Circle())
            Text(label.uppercased())
                .font(Stage.label(10, weight: .bold))
                .kerning(1.0)
                .foregroundStyle(Stage.textDim)
                // A hint that has wrapped to "SELE / CT" reads as a fault in the game. It never
                // wraps and never truncates: it takes the width it needs or it is not drawn.
                .lineLimit(1)
                .fixedSize()
        }
        .fixedSize()
    }
}
