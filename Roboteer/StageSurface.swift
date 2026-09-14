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
/// never recreated. Touches reach it only while a fight is on screen.
///
/// They cannot reach it on a menu screen whatever this says, because the one Godot view is a
/// SIBLING BELOW the navigation controller's container view in the window, and that container is a
/// plain UIView which answers `hitTest` with itself even when it is clear. So the turntable the
/// brief promises (section 11: "full turntable orbit, free zoom and tilt") is not a pass through:
/// `StageOrbitPad` sits in the clear left of each stage screen, reads the gesture itself, and
/// sends it over the bridge as `stage_camera`.
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
/// the rendered still. Either way it carries the wash that keeps white capitals readable.
struct StageBackdrop: View {

    @Bindable var host: ArenaHost
    var still: StageStill.Kind = .withBot
    /// How far to darken the picture under this screen's panels.
    var dim: Double = 0.26

    var body: some View {
        ZStack {
            if host.showsStill {
                StageStill(kind: still)
            }
            if dim > 0 {
                SwiftUI.Color.black.opacity(dim)
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
            SwiftUI.Color(hex: 0x06070A)
            RadialGradient(
                colors: [SwiftUI.Color(hex: 0x1B2740).opacity(0.9), SwiftUI.Color.clear],
                center: UnitPoint(x: 0.32, y: 0.46),
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

/// A dark wash from the top, so the title and the top of the button column hold up over the
/// brightest part of the dry ice.
struct StageScrim: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: SwiftUI.Color.black.opacity(0.55), location: 0),
                .init(color: SwiftUI.Color.black.opacity(0.16), location: 0.5),
                .init(color: SwiftUI.Color.black.opacity(0.0), location: 1)
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
