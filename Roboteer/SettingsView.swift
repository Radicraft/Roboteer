//
//  SettingsView.swift
//  Control scheme, knockout camera, haptics, volume, restore purchases and about.
//
//  Console shaped on purpose: every row is one setting, up and down move between rows, left and
//  right change the value, and a tap does the same thing a pad does. That way the same screen
//  works with a thumb and with an Xbox or PlayStation pad and neither feels like the afterthought.
//

import SwiftUI

struct SettingsView: View {

    @Bindable var host: ArenaHost
    @Environment(\.dismiss) private var dismiss

    private var settings: RoboteerSettings { RoboteerSettings.shared }
    private var focus: PadFocus { PadFocus.shared }
    /// The one purchase (docs/stage6-store-notes.md). This screen is one of the only two places
    /// the unlock screen is ever presented from; the other is the Regional final.
    private var store: StoreService { StoreService.shared }

    @State private var showUnlock = false

    private enum Row: String {
        case scheme
        case camera
        case tips
        case haptics
        case volume
        case unlock
        case restore
        case about
    }

    var body: some View {
        ZStack {
            StageBackdrop(host: host, still: .empty, dim: 0.46)

            VStack(alignment: .leading, spacing: 12) {
                header

                HStack(alignment: .top, spacing: 18) {
                    GlassPanel(padding: 12) {
                        ScrollView {
                            VStack(spacing: 7) {
                                schemeRow
                                cameraRow
                                tipsRow
                                hapticsRow
                                volumeRow
                                unlockRow
                                restoreRow
                                aboutRow
                            }
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    sidebar
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear { registerFocus() }
        // The unlock screen takes the pad while it is up, so the rows are registered again when
        // it goes away.
        .unlockScreen(isPresented: $showUnlock, host: host) { registerFocus() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            StageButton("Back", kind: .quiet) { dismiss() }
                .frame(width: 104)

            Text("SETTINGS")
                .font(Stage.display(28))
                .kerning(1.8)
                .foregroundStyle(Stage.text)

            Spacer(minLength: 8)

            PadHintBar()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassPanel(padding: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    StageHeading("Controls")
                    StageStat(label: "Controller", value: controllerLine)
                    // Wave P, agent H: the engine's own state and version were on this panel in
                    // every build. They are a diagnostic, they mean nothing to a player, and a
                    // shipping settings screen is not the place for them. They stay behind
                    // `-showSpike`, which is already the flag for the bridge diagnostics.
                    if ArenaHost.hasLaunchFlag("-showSpike") {
                        StageStat(label: "Arena", value: host.arenaReady ? "ready" : "loading")
                        StageStat(label: "Godot", value: host.godotVersion)
                    }
                    Text("Changes reach the arena straight away.")
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 232)
    }

    /// A pad that is listed but has never been touched is not a pad in anyone's hands, and the
    /// simulator lists a phantom one. Say which of the three it is.
    private var controllerLine: String {
        let observer = ControllerObserver.shared
        guard observer.connected else { return "none" }
        guard observer.active else { return "listed, not used" }
        return observer.kindLabel.isEmpty ? "connected" : observer.kindLabel
    }

    // MARK: - Rows

    private var schemeRow: some View {
        row(
            .scheme,
            label: "Control scheme",
            value: settings.scheme.title,
            blurb: settings.scheme.blurb
        )
    }

    private var cameraRow: some View {
        row(
            .camera,
            label: "Knockout camera",
            value: settings.directorCut ? "Director cut" : "Player camera",
            blurb: settings.directorCut
                ? "The camera cuts to the best angle on a knockout."
                : "The camera stays on your machine, whatever happens."
        )
    }

    /// The how to play callouts over the opening seconds of a fight. The shell decides which
    /// fights carry them (`CoachPolicy`); this is the player saying they want them every time.
    private var tipsRow: some View {
        row(
            .tips,
            label: "Control tips",
            value: settings.controlTips ? "On" : "Off",
            blurb: settings.controlTips
                ? "Every fight opens with the controls shown on screen."
                : "The controls are still shown for your first few fights and in the test arena."
        )
    }

    private var hapticsRow: some View {
        row(.haptics, label: "Haptics", value: settings.haptics ? "On" : "Off", blurb: nil)
    }

    private var volumeRow: some View {
        row(.volume, label: "Sound", value: "\(Int((settings.volume * 100).rounded()))%", blurb: nil) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Stage.type.opacity(0.12))
                    Rectangle()
                        .fill(Stage.line)
                        .frame(width: max(2, proxy.size.width * settings.volume))
                }
            }
            .frame(height: 4)
            .padding(.top, 2)
        }
    }

    /// The full game. One purchase, one price, and this row is the only permanent way to reach it.
    private var unlockRow: some View {
        row(
            .unlock,
            label: "The full game",
            value: store.isUnlocked ? "Unlocked" : (store.priceText ?? "Locked"),
            blurb: store.isUnlocked
                ? "Thank you. Every Series, arena, house bot and part is open."
                : "Free to play Series 1 and 2, the Scrapyard and the Regional. One purchase opens the rest of the game forever. No subscription, no ads, no other purchases.",
            adjustable: false
        )
    }

    private var restoreRow: some View {
        row(
            .restore,
            label: "Restore purchases",
            value: store.state.isBusy ? "Checking" : "Tap",
            blurb: restoreBlurb,
            adjustable: false
        )
    }

    private var restoreBlurb: String {
        if let failure = store.state.failure { return failure }
        if let notice = store.notice { return notice }
        if store.isUnlocked { return "This device already has the full game." }
        return "Brings a purchase made on this Apple Account back to this device. It is also shared with your family if Family Sharing is on."
    }

    private var aboutRow: some View {
        row(
            .about,
            label: "About",
            value: settings.versionLine,
            blurb: "Roboteer. Built by Radicraft. Crowd clothing by Elvaerwyn, Mindfront, punkduck and DredNicolson, CC BY 4.0, via the MakeHuman community.",
            adjustable: false
        )
    }

    // MARK: - One row

    @ViewBuilder
    private func row<Extra: View>(
        _ id: Row,
        label: String,
        value: String,
        blurb: String?,
        adjustable: Bool = true,
        @ViewBuilder extra: () -> Extra = { EmptyView() }
    ) -> some View {
        let focused = focus.isFocused(id.rawValue)
        Button {
            activate(id)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(label.uppercased())
                        .font(Stage.display(15))
                        .kerning(0.8)
                        .foregroundStyle(Stage.text)
                    Spacer(minLength: 8)
                    if adjustable {
                        chevron("chevron.left", id: id, delta: -1)
                    }
                    Text(value)
                        .font(Stage.figure(value, size: 14))
                        .foregroundStyle(Stage.textDim)
                        .frame(minWidth: 96, alignment: .trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(BroadcastType.floorScale(.numerals, size: 14, wanted: 0.7))
                    if adjustable {
                        chevron("chevron.right", id: id, delta: 1)
                    }
                }
                extra()
                if let blurb {
                    Text(blurb)
                        .font(Stage.body(13))
                        .foregroundStyle(Stage.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background {
                PlateRect()
                    .fill(focused ? Stage.selectedFill : Stage.type.opacity(0.04))
            }
        }
        .buttonStyle(.plain)
    }

    private func chevron(_ symbol: String, id: Row, delta: Int) -> some View {
        Button {
            adjust(id, delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(Stage.textDim)
                .frame(width: 26, height: 22)
                .background {
                    PlateRect()
                        .fill(Stage.type.opacity(0.06))
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Changing a setting

    /// A tap on the row, or A on the pad: the same thing as nudging it right.
    private func activate(_ id: Row) {
        switch id {
        case .unlock:
            showUnlock = true
        case .restore:
            Task { await store.restore() }
        case .about:
            break
        default:
            adjust(id, 1)
        }
    }

    private func adjust(_ id: Row, _ delta: Int) {
        switch id {
        case .scheme:
            settings.scheme = settings.scheme == .arcade ? .tank : .arcade
        case .camera:
            settings.directorCut.toggle()
        case .tips:
            settings.controlTips.toggle()
        case .haptics:
            settings.haptics.toggle()
        case .volume:
            let steps = (settings.volume * 10).rounded() + Double(delta)
            settings.volume = min(1, max(0, steps / 10))
        case .unlock, .restore, .about:
            break
        }
    }

    // MARK: - Pad

    private func registerFocus() {
        let rows: [Row] = [.scheme, .camera, .tips, .haptics, .volume, .unlock, .restore, .about]
        focus.set(
            rows.map { row in PadItem(row.rawValue) { activate(row) } },
            back: { dismiss() },
            sideways: { event in
                guard let current = focus.currentID, let row = Row(rawValue: current) else { return false }
                adjust(row, event == .left ? -1 : 1)
                return true
            }
        )
    }
}
