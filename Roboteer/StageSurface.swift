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
