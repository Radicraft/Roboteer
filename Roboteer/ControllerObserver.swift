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
    /// "Xbox", "DualSense", "DualShock", "Controller", or whatever the pad calls itself.
    private(set) var kind = ""

    /// QA: `-controllerHints` forces the hint state on with no pad in the room.
    static let hintsForced = ArenaHost.hasLaunchFlag("-controllerHints")

    /// Whether the button hints should be on screen.
    var showsHints: Bool { connected || Self.hintsForced }

    /// PlayStation pads mark the same two buttons differently, and a hint that shows the wrong
    /// glyph is worse than no hint.
    var activateGlyph: String { isPlayStation ? "✕" : "A" }
    var backGlyph: String { isPlayStation ? "○" : "B" }

    private var isPlayStation: Bool {
        kind.localizedCaseInsensitiveContains("dual")
    }

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var handler: ((PadEvent) -> Void)?
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
        if connected != wasConnected {
            spikeLog.info("controller \(self.connected ? "connected" : "disconnected", privacy: .public) \(self.kind, privacy: .public)")
        }
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
                if !observer.kind.isEmpty {
                    Text(observer.kind.uppercased())
                        .font(Stage.label(10, weight: .bold))
                        .kerning(1.2)
                        .foregroundStyle(Stage.textFaint)
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func hint(_ glyph: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(glyph)
                .font(Stage.label(11, weight: .bold))
                .foregroundStyle(Color.black)
                .frame(width: 18, height: 18)
                .background(Stage.text, in: Circle())
            Text(label.uppercased())
                .font(Stage.label(10, weight: .bold))
                .kerning(1.0)
                .foregroundStyle(Stage.textDim)
        }
    }
}
