//
//  LoadingView.swift
//  The first thing anyone sees. One dark stage, the title, one sentence.
//
//  WHY IT IS HERE. The one Godot view lives behind every menu, so the app's first frame is a
//  full 3D frame: the workshop stage and its six lights, the dry ice, the arena behind it, the
//  whole FX tree, and then the player's machine bound onto the turntable. Every material in that
//  frame has its pipeline compiled and its textures uploaded the first time it is drawn, on the
//  main thread, inside one engine iteration. Until that finishes SwiftUI in front of it cannot
//  redraw either, so the menu showed its first frame and then froze: an empty turntable and a
//  menu that read as inactive (docs/stage-bug-2026-09-21.md).
//
//  So the cost is paid here instead, once, where waiting is the point. The arena walks its whole
//  catalogue (`Arena/render/warmup.gd`) and reports how far it has got; this screen shows that as
//  the lights coming up on the stage, because the thing behind the scrim IS the stage. When the
//  walk finishes the scrim is gone, the machine is already standing on the turntable, and the
//  menu appears over a picture that is already live.
//
//  THE LOOK. Broadcast, at its quietest. No spinner, no progress bar, no coloured accent, no
//  edge strokes and no diagonal rules: the only things on the screen are the title, one plain
//  sentence and the stage itself coming out of the dark.
//

import SwiftUI

struct LoadingView: View {

    @Bindable var host: ArenaHost

    /// How dark the stage is held while the walk runs. It never reaches full black: a sliver of
    /// the picture is visible from the first frame, so the screen reads as a stage in the dark
    /// rather than as a screen that has not loaded.
    private let darkest: Double = 0.88
    private let lightest: Double = 0.30

    /// The scrim, eased so the last third of the walk is where most of the light arrives.
    private var scrim: Double {
        let progress = min(1, max(0, host.preloadFraction))
        let eased = progress * progress
        return darkest - (darkest - lightest) * eased
    }

    private var line: String {
        host.preloadLine.isEmpty ? "Opening the workshop" : host.preloadLine
    }

    var body: some View {
        ZStack {
            // Before the arena is up there is no live picture at all, so the rendered still
            // stands in. Once it is up this is empty and the live stage shows through.
            if host.showsStill {
                Stage.ink
                StageStill(kind: .empty)
            }
            Stage.ink.opacity(scrim)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                Text("ROBOTEER")
                    .font(Stage.display(44))
                    .kerning(Stage.Tracking.display(44))
                    .foregroundStyle(Stage.type)
                Text(line)
                    .font(Stage.label(12))
                    .kerning(Stage.Tracking.label(12))
                    .foregroundStyle(Stage.textFaint)
                    .padding(.top, 14)
                    .animation(.easeInOut(duration: 0.35), value: line)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 48)
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.5), value: host.preloadFraction)
        // Nothing on this screen is tappable, and nothing behind it should be either while it
        // is up: a tap on the menu underneath would push a screen nobody can see.
        .contentShape(Rectangle())
        .onTapGesture { }
    }
}
