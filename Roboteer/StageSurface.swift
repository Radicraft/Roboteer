//
//  StageSurface.swift
//  The one Godot view in the process, and the still that stands in for it.
//
//  There is exactly ONE `GodotAppView` for the life of the app, at the root of the window, behind
//  every screen. That is not a style choice: `UIGodotAppView` hands its own CAMetalLayer to the
//  embedded display server and drives the engine from its own CADisplayLink, so a second live view
//  would fight the first for the one surface. The menus are drawn in front of it as glass, and the
//  fight screen is the same view with the chrome taken away.
//
//  What the view shows is whatever the arena was last told: `workshop_config` puts the player's own
//  bot on the lit stage, `fight_config` puts the fight in the arena (docs/stage4-spec.md section 5).
//

import SwiftUI
import SwiftGodot
import SwiftGodotKit

/// The single embedded Godot view. Created once at the root of the window, never conditional,
/// never recreated.
///
/// Touches never reach it on their own, on ANY screen: the one Godot view is a SIBLING BELOW the
/// navigation controller's container view in the window, and that container is a plain UIView
/// which answers `hitTest` with itself even when it is clear. So the turntable the brief promises
/// (section 11: "full turntable orbit, free zoom and tilt") is not a pass through: `StageOrbitPad`
/// sits in the clear left of each stage screen, reads the gesture itself, and sends it over the
/// bridge as `stage_camera`. The fight screen is pushed in the same stack, so it is no different:
/// `FightTouchForwarder` at the bottom of its ZStack hands the arena's touches on by hand.
struct GodotSurface: View {
    @Bindable var host: ArenaHost

    var body: some View {
        GodotAppView(
            onReady: { handle in host.onReady(handle) },
            onMessage: { dictionary in host.receive(dictionary) }
        )
        .environment(\.godotApp, host.app)
        .ignoresSafeArea()
        .allowsHitTesting(host.surface == .fight)
    }
}

/// The turntable, in the clear left of a stage screen.
///
/// A drag orbits the machine and a pinch zooms it, both in screen points, both straight to the
/// arena as `stage_camera` (`ArenaHost.sendStageCamera`). It is a UIKit view because the gestures
/// have to be read where they land: the Godot view below the navigation stack never sees them.
///
/// Put it in the ZStack BELOW the screen's panels, sized to the clear area, so the panels keep
/// every touch of their own and this only ever gets what was aimed at the machine.
struct StageOrbitPad: UIViewRepresentable {

    let host: ArenaHost
    /// Called on the first drag, for the screen that shows a hint until then.
    var onOrbit: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(host: host, onOrbit: onOrbit) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.panned))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 2
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinched))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.host = host
        context.coordinator.onOrbit = onOrbit
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        var host: ArenaHost
        var onOrbit: (() -> Void)?
        private var lastTranslation: CGPoint = .zero

        init(host: ArenaHost, onOrbit: (() -> Void)?) {
            self.host = host
            self.onOrbit = onOrbit
        }

        /// Deltas, not the running translation: the arena moves the rig by what just happened.
        @objc func panned(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began:
                lastTranslation = .zero
            case .changed:
                let now = pan.translation(in: pan.view)
                let delta = CGSize(width: now.x - lastTranslation.x, height: now.y - lastTranslation.y)
                lastTranslation = now
                guard delta != .zero else { return }
                host.sendStageCamera(orbit: delta)
                onOrbit?()
            default:
                lastTranslation = .zero
            }
        }

        /// The factor since the last callback, so the arena never has to remember where a pinch
        /// started.
        @objc func pinched(_ pinch: UIPinchGestureRecognizer) {
            guard pinch.state == .changed else {
                pinch.scale = 1
                return
            }
            let factor = Double(pinch.scale)
            pinch.scale = 1
            guard factor > 0, abs(factor - 1) > 0.0001 else { return }
            host.sendStageCamera(pinch: factor)
        }

        /// Two fingers are a pinch AND an orbit, the way the fight camera works.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}

/// What a menu screen puts behind itself. On a device with the arena running this is empty, so the
/// live stage underneath shows through the glass. On the simulator, and before `arena_ready`, it is
/// the rendered still. Either way it carries the `ink` wash that keeps the type readable over the
/// brightest frame the arena can draw (design system section 7).
///
/// A screen with no live machine can ask for key art instead (`keyArt:`, design system section 5):
/// `Art/ui/backdrop_<tier>.png` or `menu_keyart.png`, which agent V1 produces and which ships as a
/// folder reference. **Every one of those lookups is allowed to fail.** A build taken before the
/// art lands falls back to the rendered still, and then to the ink wash, and no screen's chrome
/// depends on any of it.
struct StageBackdrop: View {

    @Bindable var host: ArenaHost
    var still: StageStill.Kind = .withBot
    /// How far to darken the picture under this screen's panels. The spec's key art wash is 0.4.
    var dim: Double = 0.26
    /// The name of a piece of key art in `Art/ui`, without the extension. Used only when there is
    /// no live machine to stand behind this screen.
    var keyArt: String? = nil

    private var art: UIImage? {
        guard let keyArt, host.showsStill else { return nil }
        return BroadcastArt.image(keyArt)
    }

    var body: some View {
        ZStack {
            // NOTHING opaque while the arena is live: the one Godot view is below this and the
            // live stage has to show through the glass. The ink ground is only ever painted when
            // there is no live picture to cover (docs/stage4-swift-notes.md, "no screen may put an
            // opaque full bleed colour above the surface").
            if let qa = StageQA.still {
                // QA (`-stageStill <path>`): a desktop render of the stage stands in for the live
                // view on every stage screen, so the real SwiftUI layer can be photographed over
                // the real stage on a simulator that cannot draw it.
                Stage.ink
                StageQAStill(image: qa)
            } else if host.showsStill {
                Stage.ink
            }
            if StageQA.still != nil {
                // Already drawn above.
            } else if let art {
                Image(uiImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if host.showsStill {
                StageStill(kind: still)
            }
            if dim > 0 {
                Stage.ink.opacity(dim)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The rendered stage still from `Art/direction/menu-stage.png`, downscaled into the bundle at
/// 2048 px wide. Used on the simulator, which cannot render the arena at all, and on a device
/// until the arena is ready.
struct StageStill: View {

    enum Kind {
        /// The stage with a bot on the turntable.
        case withBot
        /// The empty turntable, for screens whose own panels describe the machine.
        case empty

        var resource: String {
            switch self {
            case .withBot: return "menu-stage"
            case .empty: return "menu-stage-empty"
            }
        }
    }

    let kind: Kind

    var body: some View {
        GeometryReader { proxy in
            if let image = StageStill.image(kind) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            } else {
                fallback
            }
        }
        .ignoresSafeArea()
    }

    /// If a still is ever missing from the bundle the screen still looks deliberate.
    private var fallback: some View {
        ZStack {
            Stage.ink
            RadialGradient(
                colors: [Stage.line.opacity(0.10), SwiftUI.Color.clear],
                center: UnitPoint(x: 0.28, y: 0.46),
                startRadius: 10,
                endRadius: 520
            )
        }
    }

    private static var cache: [String: UIImage] = [:]

    static func image(_ kind: Kind) -> UIImage? {
        if let cached = cache[kind.resource] { return cached }
        guard let url = Bundle.main.url(forResource: kind.resource, withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache[kind.resource] = image
        return image
    }
}

// MARK: - QA: a desktop render of the stage, and its anchors (wave C)

/// The QA stand ins for the live stage (docs/qa-launch-flags.md, "The stage, for screenshots"):
///
/// - `-stageStill <path>`: a jpg or png, by absolute path, drawn as the backdrop of every stage
///   screen instead of the live view or the bundled still, aspect filled over the whole window.
/// - `-stageAnchors <path.json>`: one `stage_anchors` payload, or an object keyed by screen name
///   whose values are payloads. Fed to the app exactly as if the arena had sent it; with the keyed
///   form, the payload for whichever screen is in front of the stage. While this flag is on, the
///   arena's own `stage_anchors` are ignored, so a composite is never half live.
enum StageQA {

    static let stillPath: String? = ArenaHost.launchArgument("-stageStill")

    static let still: UIImage? = {
        guard let path = stillPath else { return nil }
        let image = UIImage(contentsOfFile: path)
        if image == nil { spikeLog.error("-stageStill: could not read \(path, privacy: .public)") }
        return image
    }()

    enum AnchorsFile {
        case single(StageAnchors)
        case byScreen([String: StageAnchors])
    }

    static let anchorsFile: AnchorsFile? = {
        guard let path = ArenaHost.launchArgument("-stageAnchors") else { return nil }
        guard let data = FileManager.default.contents(atPath: path),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            spikeLog.error("-stageAnchors: could not read \(path, privacy: .public)")
            return nil
        }
        // One payload has the payload's own keys at the top; anything else is keyed by screen.
        if object["parts"] != nil || object["hero"] != nil || object["points"] != nil {
            return StageAnchors(object).map { .single($0) }
        }
        var keyed: [String: StageAnchors] = [:]
        for (screen, value) in object {
            guard var payload = value as? [String: Any] else { continue }
            if payload["screen"] == nil { payload["screen"] = screen }
            if let anchors = StageAnchors(payload) { keyed[screen] = anchors }
        }
        return .byScreen(keyed)
    }()

    static var overridesAnchors: Bool { anchorsFile != nil }

    /// The QA payload for the screen in front of the stage, or nil.
    static func anchors(for screen: String?) -> StageAnchors? {
        switch anchorsFile {
        case .single(let anchors): return anchors
        case .byScreen(let keyed): return screen.flatMap { keyed[$0] }
        case nil: return nil
        }
    }
}

/// The QA still, aspect filled and centred over the full window, safe areas ignored.
private struct StageQAStill: View {
    let image: UIImage
    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .ignoresSafeArea()
    }
}

/// `stage_anchors` (docs/wave-c-menus-notes.md): where the parts the leader lines point at are on
/// screen, normalised to the full Godot view (0,0 top left, 1,1 bottom right), which fills the
/// window ignoring the safe areas.
struct StageAnchors: Equatable {

    struct Part: Equatable {
        /// The Bot's `part_key`: `wheel_fl`, `armour_top`, `weapon`, `chassis`, ...
        var key: String
        var kind: String
        var at: CGPoint
        /// On the camera's side of the machine. Only near parts get a leader.
        var near: Bool
    }

    var screen: String
    var settled: Bool
    /// The machine's projected box, x0 y0 x1 y1, normalised.
    var hero: CGRect?
    var points: [String: CGPoint]
    var parts: [Part]

    init?(_ object: [String: Any]) {
        screen = object["screen"] as? String ?? ""
        settled = object["settled"] as? Bool ?? true
        func point(_ value: Any?) -> CGPoint? {
            guard let list = value as? [Any], list.count >= 2,
                  let x = (list[0] as? NSNumber)?.doubleValue,
                  let y = (list[1] as? NSNumber)?.doubleValue else { return nil }
            return CGPoint(x: x, y: y)
        }
        if let box = object["hero"] as? [Any], box.count >= 4 {
            let n = box.compactMap { ($0 as? NSNumber)?.doubleValue }
            if n.count >= 4 { hero = CGRect(x: n[0], y: n[1], width: n[2] - n[0], height: n[3] - n[1]) }
        }
        var found: [String: CGPoint] = [:]
        for (key, value) in object["points"] as? [String: Any] ?? [:] {
            if let p = point(value) { found[key] = p }
        }
        points = found
        parts = (object["parts"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let key = entry["key"] as? String, let at = point(entry["at"]) else { return nil }
            return Part(key: key, kind: entry["kind"] as? String ?? "",
                        at: at, near: entry["near"] as? Bool ?? true)
        }
    }

    /// A near part by key. The hull answers to `chassis` and to `core`, which is what the fight's
    /// damage calls it.
    func part(_ key: String) -> Part? {
        let keys = (key == "chassis" || key == "core") ? ["chassis", "core"] : [key]
        return parts.first { keys.contains($0.key) && $0.near }
    }

    /// The first near part of a kind (`wheel`, `armour`, `weapon`), preferring the given keys.
    func part(kind: String, prefer: [String] = []) -> Part? {
        for key in prefer { if let hit = part(key) { return hit } }
        return parts.first { $0.kind == kind && $0.near }
    }
}

/// A dark wash from the top, so the title and the top of the button column hold up over the
/// brightest part of the dry ice.
struct StageScrim: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Stage.ink.opacity(0.62), location: 0),
                .init(color: Stage.ink.opacity(0.18), location: 0.5),
                .init(color: Stage.ink.opacity(0.0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Letting the arena through

/// UIKit paints an opaque background behind SwiftUI content in a `UINavigationController`, and on
/// iOS 18 that background is black. The one `GodotAppView` lives at the root of the window, BELOW
/// the navigation stack, so that black sheet hid everything Godot drew on every screen: a
/// screenshot read exactly (0,0,0) even with `Stage.ground` (7,8,10) under it and the root
/// viewport cleared to magenta (docs/simulator-rendering.md).
///
/// `.containerBackground(.clear, for: .navigation)` is the SwiftUI half of the fix. This is the
/// other half, because a clear SwiftUI background draws nothing rather than removing the UIView's
/// own colour: it walks up from the content to the window and clears every ancestor it passes,
/// which is the navigation controller's view, its wrapper and the hosting views.
struct ClearsContainerBackground: UIViewRepresentable {

    func makeUIView(context: Context) -> ClearingView { ClearingView() }

    func updateUIView(_ view: ClearingView, context: Context) {
        view.clearAncestors()
    }

    final class ClearingView: UIView {

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            clearAncestors()
            // SwiftUI sets its own colours during the same runloop turn as a push, so do it again
            // once the transition has settled.
            DispatchQueue.main.async { [weak self] in self?.clearAncestors() }
        }

        func clearAncestors() {
            backgroundColor = .clear
            var ancestor = superview
            while let view = ancestor {
                // Stop at the window: its own colour is the one thing below everything and
                // clearing it would let the host's black through anyway.
                if view is UIWindow { break }
                if view.backgroundColor != nil, view.backgroundColor != .clear {
                    view.backgroundColor = .clear
                }
                view.isOpaque = false
                ancestor = view.superview
            }
        }
    }
}

extension View {

    /// Put this on the navigation stack's root and on every destination. Both halves of the fix in
    /// one place, so no screen can forget one of them.
    func lettingTheArenaThrough() -> some View {
        self
            .containerBackground(.clear, for: .navigation)
            .background { ClearsContainerBackground() }
    }
}


// MARK: - Fight touches

/// Hands the fight screen's touches to the arena.
///
/// Two things stood between a thumb and the stick on a phone (2026-09-16 device logs). The one
/// Godot view is a sibling BELOW the navigation controller's container view, and that container
/// answers `hitTest` with itself even when it is clear, so on the pushed fight screen no touch ever
/// reached the view. And when the touches were handed to the view's own handlers, the kit's
/// `DisplayServerAppleEmbedded` bridge raised nothing inside the engine on the stock v4.6.4 slice:
/// twelve touches in, zero `InputEvent`s seen by the fight node. So this sits at the bottom of the
/// fight screen's ZStack, full screen, takes every touch the panels above it leave alone, and
/// builds the engine's own `InputEventScreenTouch` / `InputEventScreenDrag` for it, in window
/// pixels (the Godot window is sized `bounds * contentScaleFactor`, see the kit's `resizeWindow`),
/// straight into `Input.parseInputEvent`. Nothing goes through the display server.
struct FightTouchForwarder: UIViewRepresentable {

    func makeUIView(context: Context) -> ForwardingView { ForwardingView() }

    func updateUIView(_ view: ForwardingView, context: Context) {}

    final class ForwardingView: UIView {

        private weak var godot: UIGodotAppView?
        /// Godot touch index per live UITouch, 0..<32 like the engine's own table.
        private var indices: [ObjectIdentifier: Int32] = [:]
        private var lastPositions: [Int32: Vector2] = [:]
        private static var logged = 0

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = true
            isMultipleTouchEnabled = true
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            backgroundColor = .clear
            isUserInteractionEnabled = true
            isMultipleTouchEnabled = true
        }

        /// The Godot view, found once by walking the window and kept while it stays in it. It is
        /// only needed for its coordinate space and scale.
        private func target() -> UIGodotAppView? {
            if let godot, godot.window != nil { return godot }
            godot = Self.find(in: window)
            return godot
        }

        private static func find(in view: UIView?) -> UIGodotAppView? {
            guard let view else { return nil }
            if let hit = view as? UIGodotAppView { return hit }
            for sub in view.subviews {
                if let hit = find(in: sub) { return hit }
            }
            return nil
        }

        private func index(for touch: UITouch, allocating: Bool) -> Int32? {
            let key = ObjectIdentifier(touch)
            if let index = indices[key] { return index }
            guard allocating else { return nil }
            let used = Set(indices.values)
            guard let free = (0..<32).map(Int32.init).first(where: { !used.contains($0) }) else { return nil }
            indices[key] = free
            return free
        }

        private func release(_ touch: UITouch) {
            if let index = indices.removeValue(forKey: ObjectIdentifier(touch)) {
                lastPositions.removeValue(forKey: index)
            }
        }

        /// The touch in Godot window pixels.
        private func pixels(_ touch: UITouch, in godot: UIGodotAppView) -> Vector2 {
            let p = touch.location(in: godot)
            let s = godot.contentScaleFactor
            return Vector2(x: Float(p.x * s), y: Float(p.y * s))
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let godot = target() else { return }
            for touch in touches {
                // UIKit reuses UITouch objects. One arriving as "began" while we still hold an
                // index for it means its end was never delivered (a system gesture took it,
                // the app went to the background mid-press). Release the stale press first,
                // or the arena keeps a button held that no thumb is on.
                if let stale = index(for: touch, allocating: false) {
                    let ev = InputEventScreenTouch()
                    ev.index = stale
                    ev.position = lastPositions[stale] ?? pixels(touch, in: godot)
                    ev.pressed = false
                    ev.canceled = true
                    Input.parseInputEvent(ev)
                    release(touch)
                }
                guard let index = index(for: touch, allocating: true) else { continue }
                let pos = pixels(touch, in: godot)
                let ev = InputEventScreenTouch()
                ev.index = index
                ev.position = pos
                ev.pressed = true
                ev.doubleTap = touch.tapCount > 1
                Input.parseInputEvent(ev)
                lastPositions[index] = pos
                if Self.logged < 40 {
                    Self.logged += 1
                    ArenaFileLog.append("{\"level\":\"info\",\"text\":\"fwd began idx=\(index) px=(\(Int(pos.x)),\(Int(pos.y))) scale=\(godot.contentScaleFactor)\"}")
                }
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let godot = target() else { return }
            for touch in touches {
                guard let index = index(for: touch, allocating: false) else { continue }
                let pos = pixels(touch, in: godot)
                let last = lastPositions[index] ?? pos
                let ev = InputEventScreenDrag()
                ev.index = index
                ev.position = pos
                ev.relative = Vector2(x: pos.x - last.x, y: pos.y - last.y)
                Input.parseInputEvent(ev)
                lastPositions[index] = pos
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let godot = target() else { return }
            for touch in touches {
                guard let index = index(for: touch, allocating: false) else { continue }
                let ev = InputEventScreenTouch()
                ev.index = index
                ev.position = pixels(touch, in: godot)
                ev.pressed = false
                Input.parseInputEvent(ev)
                release(touch)
            }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let godot = target() else { return }
            for touch in touches {
                guard let index = index(for: touch, allocating: false) else { continue }
                let ev = InputEventScreenTouch()
                ev.index = index
                ev.position = pixels(touch, in: godot)
                ev.pressed = false
                ev.canceled = true
                Input.parseInputEvent(ev)
                release(touch)
            }
        }
    }
}
