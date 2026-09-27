//
//  LoadingView.swift
//  The first thing anyone sees: their own machine being put together on the workshop turntable.
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
//  catalogue (`Arena/render/warmup.gd`) in ~90 ms main-thread slices and reports how far it has
//  got after each one: the true fraction of files read and batches drawn, never a timer. When the
//  walk finishes this screen goes, and the menu appears over a picture that is already live.
//
//  THE LOOK (owner pick 2026-09-27, direction A of docs/look/loading-options.html, "Built on the
//  turntable"). The machine the menu will show (a new player's starter, a veteran's last build)
//  is assembled on the stage as the walk runs: the bare hull in the dark, then the drive, the
//  armour and the weapon, then the stage lights come up. The warm up's five phases each own one
//  row, and the stage hears the same progress messages (Arena/workshop/stage.gd, "the build
//  behind the loading screen"), so a part lands on the turntable as its row fills:
//
//      Hull          scenes, environments, arena materials, FX     "Opening the workshop"
//      Drive         every part model and material slot            "Fitting the drive"
//      Armour        the paint overlays                            "Bolting on the armour"
//      Weapon        every sound                                   "Mounting the weapon"
//      Stage lights  the off screen draw (the pipeline compiles)   "Warming the lights"
//
//  The column sits on the RIGHT over a shade that clears towards the machine, because every menu
//  screen frames the machine at `StageLayout.botFrame` (28 % across) and keeps its panels on the
//  right: the menu's plates then arrive where this column was, over the same lit stage, with no
//  cut and no second reveal. The mockup drew the column on the left over a centred machine; this
//  is the same design mirrored to the menu's real framing.
//
//  Everything changes in steps (a part lands, a row fills, the number ticks), because SwiftUI only
//  redraws about ten times a second while the slices run: nothing here drifts. Broadcast rules
//  (docs/design-system.md section 0): no edge strokes, no rules, no accent lines. State lives in
//  fill and weight; the only cyan is the gauge, which fills.
//

import SwiftUI

/// The machine the loading screen names and the stage builds, in the words the garage uses.
struct LoadingMachine: Equatable {
    var name: String
    var hull: String
    var drive: String
    var armour: String
    var weapon: String

    /// The warm up's last step (`ArenaWarmUp.STEP_DONE`).
    static let doneStep = 5

    init(name: String, hull: String, drive: String, armour: String, weapon: String) {
        self.name = name
        self.hull = hull
        self.drive = drive
        self.armour = armour
        self.weapon = weapon
    }

    init(build: BotBuild) {
        let catalogue = Catalogue.shared
        name = build.name
        hull = catalogue.chassis(build.chassisID)?.name ?? build.chassisID.capitalizedFirst
        drive = catalogue.drive(build.driveID)?.name ?? build.driveID.uppercased()
        let plate = catalogue.material(build.frontMaterial)?.name ?? build.frontMaterial.capitalizedFirst
        armour = "\(plate) plates"
        weapon = catalogue.weapon(build.weaponID)?.name ?? build.weaponID.capitalizedFirst
    }
}

struct LoadingView: View {

    @Bindable var host: ArenaHost

    private struct Row: Identifiable {
        let id: Int
        let title: String
        let part: String
        let fitting: String
        let waiting: String
    }

    private enum RowState { case done, now, waiting }

    private var rows: [Row] {
        let m = host.loadingMachine
        return [
            Row(id: 0, title: "Hull", part: m?.hull ?? "Chassis", fitting: "Fitting", waiting: m?.hull ?? ""),
            Row(id: 1, title: "Drive", part: m?.drive ?? "Wheels", fitting: "Fitting", waiting: m?.drive ?? ""),
            Row(id: 2, title: "Armour", part: m?.armour ?? "Plates", fitting: "Fitting", waiting: m?.armour ?? ""),
            Row(id: 3, title: "Weapon", part: m?.weapon ?? "Weapon", fitting: "Fitting", waiting: m?.weapon ?? ""),
            Row(id: 4, title: "Stage lights", part: "On", fitting: "Coming up", waiting: "Off")
        ]
    }

    /// The row being worked on. Before the first message the hull is.
    private var step: Int { max(0, host.preloadStep) }

    private func state(_ row: Row) -> RowState {
        if step > row.id { return .done }
        return step == row.id ? .now : .waiting
    }

    private var percent: Int {
        Int((min(1, max(0, host.preloadFraction)) * 100).rounded(.down))
    }

    private var line: String {
        host.preloadLine.isEmpty ? "Opening the workshop" : host.preloadLine
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 420
            ZStack(alignment: .trailing) {
                // Before the arena is up there is no live picture at all, so the rendered still
                // stands in. Once it is up the live stage shows through, and it is the stage
                // itself that is dark: the arena holds its lights down until the build is done.
                if host.showsStill {
                    Stage.ink
                    StageStill(kind: .empty)
                }
                // Between the arena coming up and its first progress message the stage has not
                // gone dark yet: hold it down here for that beat so it never flashes lit.
                Stage.ink.opacity(!host.showsStill && host.preloadStep < 0 ? 0.9 : 0)

                // Dark behind the column, clear over the machine.
                LinearGradient(
                    stops: [
                        .init(color: Stage.ink.opacity(0), location: 0.48),
                        .init(color: Stage.ink.opacity(0.55), location: 0.68),
                        .init(color: Stage.ink.opacity(0.82), location: 1.0)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )

                column(compact: compact)
                    .frame(width: compact ? 290 : 300)
                    .padding(.trailing, 62)
                    .padding(.top, compact ? 18 : 22)
                    .padding(.bottom, compact ? 18 : 24)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        // Nothing on this screen is tappable, and nothing behind it should be either while it
        // is up: a tap on the menu underneath would push a screen nobody can see.
        .contentShape(Rectangle())
        .onTapGesture { }
    }

    private func column(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Roboteer")
                .textCase(.uppercase)
                .font(Stage.display(24))
                .kerning(Stage.Tracking.display(24))
                .foregroundStyle(Stage.type)

            Text(host.loadingMachine?.name ?? "Your machine")
                .textCase(.uppercase)
                .font(Stage.display(compact ? 40 : 46))
                .kerning(Stage.Tracking.display(46))
                .foregroundStyle(Stage.type)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, compact ? 16 : 28)
            if host.loadingMachine != nil {
                Text("Your machine")
                    .font(Stage.label(14))
                    .foregroundStyle(Stage.typeDim)
                    .padding(.top, 4)
            }

            VStack(spacing: 4) {
                ForEach(rows) { row in
                    rowView(row, compact: compact)
                }
            }
            .padding(.top, compact ? 12 : 16)
            .animation(.easeOut(duration: 0.2), value: step)

            Spacer(minLength: 8)

            progress
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading, \(percent) percent. \(line).")
    }

    private func rowView(_ row: Row, compact: Bool) -> some View {
        let state = state(row)
        let value: String
        switch state {
        case .done: value = row.part
        case .now: value = row.fitting
        case .waiting: value = row.waiting
        }
        return HStack(spacing: 8) {
            Text(row.title)
                .font(Stage.label(17))
                .foregroundStyle(Stage.type)
            Spacer(minLength: 6)
            Text(value)
                .font(Stage.body(15, weight: .semibold))
                .foregroundStyle(state == .now ? Stage.type : Stage.typeDim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .frame(height: compact ? 29 : 32)
        // A shape, not a bare colour: a colour background bleeds into the safe area, and this
        // column sits against the right hand one.
        .background { Rectangle().fill(state == .now ? Stage.selectedFill : Color(hex: 0x0E1218).opacity(0.55)) }
        .opacity(state == .waiting ? 0.38 : 1)
    }

    private var progress: some View {
        HStack(alignment: .bottom, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(percent)")
                    .font(Stage.display(64))
                    .monospacedDigit()
                    .foregroundStyle(Stage.type)
                Text("%")
                    .font(Stage.display(29))
                    .foregroundStyle(Stage.typeDim)
            }
            .frame(minWidth: 112, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                gauge
                Text(line)
                    .font(Stage.body(15))
                    .foregroundStyle(Stage.type.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.bottom, 8)
        }
    }

    /// A chunky gauge that fills with the true fraction, with the light caught on its head.
    private var gauge: some View {
        GeometryReader { proxy in
            let filled = proxy.size.width * min(1, max(0, host.preloadFraction))
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.09))
                Rectangle()
                    .fill(Stage.line)
                    .overlay(alignment: .trailing) {
                        LinearGradient(colors: [.white.opacity(0), .white.opacity(0.6)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: min(28, filled))
                            .blendMode(.screen)
                    }
                    .frame(width: filled)
            }
        }
        .frame(height: 10)
    }
}
